import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/core/services/storage_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';

enum IntegrityStatus { intact, broken, legacy, unsealed }

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
  }) : _occurrenceRepository = occurrenceRepository,
       _eventRepository = eventRepository,
       _signatureRepository = signatureRepository,
       _firestore = firestore,
       _mediaHashReader = mediaHashReader;

  final OccurrenceRepository? _occurrenceRepository;
  final OccurrenceEventRepository? _eventRepository;
  final SignatureRepository? _signatureRepository;
  final FirebaseFirestore? _firestore;
  final MediaHashReader? _mediaHashReader;

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
    bool verifyMediaBytes = true,
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
    final verdict = verify(
      occurrence.copyWith(
        signatures: signatures,
        participations: participations,
        correctionRequests: correctionRequests,
      ),
      events: events,
    );
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
      return verdict.copyWith(
        status: IntegrityStatus.broken,
        checkedMediaCount: mediaResult.checkedCount,
        mediaIssues: mediaResult.issues,
      );
    }
    return verdict.copyWith(checkedMediaCount: mediaResult.checkedCount);
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
