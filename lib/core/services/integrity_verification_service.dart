import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';

/// Estado documental do selo.
///
/// FF-OCC-09: `broken` só pode vir de um veredito autoritativo do servidor.
/// Divergência do recálculo local, indisponibilidade do verificador e mídia
/// divergente NÃO são autoridade para acusar adulteração do documento.
enum IntegrityStatus { intact, broken, legacy, unsealed, unverified }

typedef MediaHashReader = Future<String?> Function(String url, {int maxBytes});

class IntegrityVerdict {
  final IntegrityStatus status;
  final String? storedHash;
  final String? recomputedHash;
  final int? hashVersion;
  final int checkedMediaCount;
  final List<String> mediaIssues;

  const IntegrityVerdict({
    required this.status,
    this.storedHash,
    this.recomputedHash,
    this.hashVersion,
    this.checkedMediaCount = 0,
    this.mediaIssues = const [],
  });

  bool get isIntact => status == IntegrityStatus.intact;
  bool get hasMediaIssues => mediaIssues.isNotEmpty;

  String get label => switch (status) {
    IntegrityStatus.intact => 'Integro',
    IntegrityStatus.broken => 'Selo quebrado - possivel adulteracao',
    IntegrityStatus.legacy => 'Selo legado nao recalculavel',
    IntegrityStatus.unsealed => 'Nao selado',
    IntegrityStatus.unverified => 'Verificacao nao disponivel',
  };

  IntegrityVerdict copyWith({
    IntegrityStatus? status,
    String? storedHash,
    String? recomputedHash,
    int? hashVersion,
    int? checkedMediaCount,
    List<String>? mediaIssues,
  }) {
    return IntegrityVerdict(
      status: status ?? this.status,
      storedHash: storedHash ?? this.storedHash,
      recomputedHash: recomputedHash ?? this.recomputedHash,
      hashVersion: hashVersion ?? this.hashVersion,
      checkedMediaCount: checkedMediaCount ?? this.checkedMediaCount,
      mediaIssues: mediaIssues ?? this.mediaIssues,
    );
  }
}

class IntegrityVerificationService {
  IntegrityVerificationService({
    OccurrenceRepository? occurrenceRepository,
    OccurrenceEventRepository? eventRepository,
    SignatureRepository? signatureRepository,
    FirebaseFirestore? firestore,
    MediaHashReader? mediaHashReader,
    http.Client? httpClient,
  }) : _occurrenceRepository = occurrenceRepository,
       _eventRepository = eventRepository,
       _signatureRepository = signatureRepository,
       _firestore = firestore,
       _mediaHashReader = mediaHashReader,
       _httpClient = httpClient;

  /// Base do verificador oficial. O documento é selado e verificado no
  /// servidor; o Mobile apenas apresenta o veredito.
  static const _verifierBaseUrl = String.fromEnvironment(
    'K9_INTEGRITY_VERIFIER_BASE_URL',
    defaultValue:
        'https://southamerica-east1-canil-gcm.cloudfunctions.net/verifyOccurrence/v',
  );

  static const _verifierTimeout = Duration(seconds: 8);

  final OccurrenceRepository? _occurrenceRepository;
  final OccurrenceEventRepository? _eventRepository;
  final SignatureRepository? _signatureRepository;
  final FirebaseFirestore? _firestore;
  final MediaHashReader? _mediaHashReader;
  final http.Client? _httpClient;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  OccurrenceRepository get _occurrences =>
      _occurrenceRepository ?? OccurrenceRepository(_db);
  OccurrenceEventRepository get _events =>
      _eventRepository ?? OccurrenceEventRepository(_db);
  SignatureRepository get _signatures =>
      _signatureRepository ?? SignatureRepository(firestore: _firestore);
  MediaHashReader get _readMediaHash =>
      _mediaHashReader ?? StorageService().sha256FromUrl;

  Future<IntegrityVerdict> verifyById(
    String occurrenceId, {
    bool verifyMediaBytes = false,
  }) async {
    final occurrence = await _occurrences.getById(occurrenceId);
    if (occurrence == null) {
      return const IntegrityVerdict(status: IntegrityStatus.unsealed);
    }
    final events = await _events.listByOccurrence(occurrenceId);
    final signatures = await _signatures.getSignatures(
      occurrenceId,
      activeRoundOnly: false,
    );
    final participations = await _loadParticipations(occurrenceId);
    final correctionRequests = await _loadCorrectionRequests(occurrenceId);

    // O recálculo local permanece apenas como diagnóstico: Dart e a Function
    // canonicalizam de forma independente, então uma divergência aqui não prova
    // adulteração. Quem decide o estado documental é o verificador oficial.
    //
    // FF-OCC-09.C2: o diagnóstico é isolado. Se ele falhar (dado malformado,
    // por exemplo), a consulta autoritativa ainda acontece — diagnóstico não
    // pode ser pré-requisito da verdade.
    IntegrityVerdict local;
    try {
      local = verify(
        occurrence.copyWith(
          signatures: signatures,
          participations: participations,
          correctionRequests: correctionRequests,
        ),
        events: events,
      );
    } catch (error) {
      debugPrint(
        '[IntegrityVerification] Recalculo local (diagnostico) falhou para '
        '$occurrenceId: $error',
      );
      // Placeholder sem autoridade documental: preserva o selo armazenado e a
      // versão para exibição, sem recomputedHash e sem afirmar intact/broken.
      local = IntegrityVerdict(
        status: IntegrityStatus.unverified,
        storedHash: occurrence.integrityHash,
        hashVersion: occurrence.hashVersion,
      );
    }

    final verdict = await _authoritativeVerdict(occurrenceId, local);

    if (!verifyMediaBytes ||
        verdict.status != IntegrityStatus.intact ||
        (verdict.hashVersion ?? 1) < 2) {
      return verdict;
    }

    final mediaResult = await _verifyMediaBytes(occurrence, events);
    if (mediaResult.issues.isNotEmpty) {
      debugPrint(
        '[IntegrityVerification] Midia divergente para $occurrenceId: '
        '${mediaResult.issues.join(' | ')}',
      );
    }
    // FF-OCC-09: mídia divergente NÃO sobrescreve o estado documental. O selo
    // do documento continua valendo o que o servidor disse; a divergência de
    // mídia é reportada pelo canal próprio (mediaIssues).
    return verdict.copyWith(
      checkedMediaCount: mediaResult.checkedCount,
      mediaIssues: mediaResult.issues,
    );
  }

  /// Consulta o verificador oficial e traduz o veredito autoritativo.
  ///
  /// Qualquer indisponibilidade (rede, timeout, HTTP não-2xx, JSON malformado,
  /// status desconhecido ou payload incoerente) resulta em
  /// [IntegrityStatus.unverified] — nunca em [IntegrityStatus.broken].
  Future<IntegrityVerdict> _authoritativeVerdict(
    String occurrenceId,
    IntegrityVerdict local,
  ) async {
    final diagnostic = local.copyWith(status: IntegrityStatus.unverified);
    final client = _httpClient ?? http.Client();
    try {
      final uri = Uri.parse(
        '${_verifierBaseUrl.replaceFirst(RegExp(r'/+$'), '')}'
        '/${Uri.encodeComponent(occurrenceId)}?format=json',
      );
      final response = await client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_verifierTimeout);

      if (response.statusCode != 200) {
        debugPrint(
          '[IntegrityVerification] Verificador respondeu '
          'HTTP ${response.statusCode} para $occurrenceId',
        );
        return diagnostic;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return diagnostic;
      return _mapServerPayload(occurrenceId, decoded, diagnostic);
    } catch (error) {
      debugPrint(
        '[IntegrityVerification] Verificador indisponivel para '
        '$occurrenceId: $error',
      );
      return diagnostic;
    } finally {
      // Fecha somente o cliente que este serviço criou.
      if (_httpClient == null) client.close();
    }
  }

  IntegrityVerdict _mapServerPayload(
    String occurrenceId,
    Map<String, dynamic> payload,
    IntegrityVerdict diagnostic,
  ) {
    if (payload['occurrence_id']?.toString() != occurrenceId) {
      return diagnostic;
    }

    final serverStatus = payload['status']?.toString();
    final storedHash = payload['stored_hash']?.toString();
    final rawVersion = payload['hash_version'];
    final version = rawVersion is num
        ? rawVersion.round()
        : int.tryParse(rawVersion?.toString() ?? '');
    final documentIntact = payload['document_intact'] ?? payload['intact'];

    IntegrityVerdict withStatus(IntegrityStatus status) => diagnostic.copyWith(
      status: status,
      storedHash: storedHash?.isNotEmpty == true ? storedHash : null,
      hashVersion: version,
    );

    switch (serverStatus) {
      case 'intact':
        // Coerência exigida: um documento íntegro não pode declarar o
        // contrário no campo booleano.
        if (documentIntact == false) return diagnostic;
        return withStatus(IntegrityStatus.intact);
      case 'media_broken':
        // Documento íntegro com mídia divergente: o estado documental
        // permanece íntegro e a mídia é reportada em mediaIssues.
        if (documentIntact == false) return withStatus(IntegrityStatus.broken);
        return withStatus(
          IntegrityStatus.intact,
        ).copyWith(mediaIssues: _serverMediaIssues(payload));
      case 'broken':
        if (documentIntact == true) return diagnostic;
        return withStatus(IntegrityStatus.broken);
      case 'unsealed':
        return withStatus(IntegrityStatus.unsealed);
      case 'unsupported_version':
        return withStatus(IntegrityStatus.legacy);
      default:
        // not_found, error e qualquer status desconhecido.
        return diagnostic;
    }
  }

  static List<String> _serverMediaIssues(Map<String, dynamic> payload) {
    final raw = payload['media_issues'];
    if (raw is! List) return const [];
    return raw
        .map((issue) => issue?.toString() ?? '')
        .where((issue) => issue.isNotEmpty)
        .toList();
  }

  static IntegrityVerdict verify(
    Occurrence occurrence, {
    List<OccurrenceEvent> events = const [],
  }) {
    final stored = occurrence.integrityHash;
    if (stored == null || stored.isEmpty) {
      return const IntegrityVerdict(status: IntegrityStatus.unsealed);
    }

    final version = occurrence.hashVersion ?? 1;
    if (version < 1 || version > 4) {
      return IntegrityVerdict(
        status: IntegrityStatus.legacy,
        storedHash: stored,
        hashVersion: version,
      );
    }

    final recomputed = OccurrenceFinalizationService.calculateIntegrityHashFor(
      occurrence,
      version: version,
      events: events,
    );
    final intact = recomputed == stored;
    if (!intact) {
      debugPrint(
        '[IntegrityVerification] Selo divergente para ${occurrence.id}: '
        'armazenado=$stored recalculado=$recomputed',
      );
    }
    return IntegrityVerdict(
      status: intact ? IntegrityStatus.intact : IntegrityStatus.broken,
      storedHash: stored,
      recomputedHash: recomputed,
      hashVersion: version,
    );
  }

  Future<List<OccurrenceParticipation>> _loadParticipations(
    String occurrenceId,
  ) async {
    final snapshot = await _db
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('participations')
        .get();
    return snapshot.docs
        .map((doc) => OccurrenceParticipation.fromJson(doc.data()))
        .where((participation) => participation.handlerId.isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadCorrectionRequests(
    String occurrenceId,
  ) async {
    final snapshot = await _db
        .collection('occurrences')
        .doc(occurrenceId)
        .collection('correction_requests')
        .get();
    return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
  }

  Future<_MediaVerificationResult> _verifyMediaBytes(
    Occurrence occurrence,
    List<OccurrenceEvent> events,
  ) async {
    final expectedMedia = <_ExpectedMedia>[
      for (final event in events) ..._eventMedia(event),
      ..._finalizationMedia(occurrence),
    ];
    final issues = <String>[];
    var checkedCount = 0;

    for (final media in expectedMedia) {
      if (media.url.isEmpty) continue;
      if (media.expectedHash == null || media.expectedHash!.isEmpty) {
        issues.add('${media.label}: hash esperado ausente');
        continue;
      }
      try {
        final actualHash = await _readMediaHash(
          media.url,
          maxBytes: _maxMediaVerificationBytes,
        );
        checkedCount++;
        if (actualHash == null || actualHash.isEmpty) {
          issues.add('${media.label}: arquivo ausente no Storage');
        } else if (actualHash != media.expectedHash) {
          issues.add('${media.label}: SHA-256 da midia nao confere');
        }
      } catch (error) {
        issues.add('${media.label}: falha ao verificar midia ($error)');
      }
    }

    return _MediaVerificationResult(checkedCount: checkedCount, issues: issues);
  }

  static Iterable<_ExpectedMedia> _eventMedia(OccurrenceEvent event) sync* {
    final metadataByUrl = <String, Map<String, dynamic>>{};
    for (final metadata in event.photoMetadata) {
      final url = metadata['url']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        metadataByUrl[url] = metadata;
      }
    }

    for (var i = 0; i < event.photoUrls.length; i++) {
      final url = event.photoUrls[i].trim();
      final metadata =
          metadataByUrl[url] ??
          (i < event.photoMetadata.length ? event.photoMetadata[i] : null);
      yield _ExpectedMedia(
        label: 'evento ${event.id} foto ${i + 1}',
        url: url,
        expectedHash: metadata?['sha256']?.toString(),
      );
    }
  }

  static Iterable<_ExpectedMedia> _finalizationMedia(
    Occurrence occurrence,
  ) sync* {
    for (var i = 0; i < occurrence.finalizationPhotos.length; i++) {
      yield _ExpectedMedia(
        label: 'finalizacao foto ${i + 1}',
        url: occurrence.finalizationPhotos[i].trim(),
        expectedHash: i < occurrence.finalizationPhotoHashes.length
            ? occurrence.finalizationPhotoHashes[i].trim()
            : null,
      );
    }
  }
}

const _maxMediaVerificationBytes = 20 * 1024 * 1024;

class _ExpectedMedia {
  final String label;
  final String url;
  final String? expectedHash;

  const _ExpectedMedia({
    required this.label,
    required this.url,
    required this.expectedHash,
  });
}

class _MediaVerificationResult {
  final int checkedCount;
  final List<String> issues;

  const _MediaVerificationResult({
    required this.checkedCount,
    required this.issues,
  });
}
