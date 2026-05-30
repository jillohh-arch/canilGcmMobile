import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/domain/occurrence_participation.dart';
import 'package:canil_gcm/core/services/occurrence_finalization_service.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_event.dart';

enum IntegrityStatus { intact, broken, legacy, unsealed }

class IntegrityVerdict {
  final IntegrityStatus status;
  final String? storedHash;
  final String? recomputedHash;
  final int? hashVersion;

  const IntegrityVerdict({
    required this.status,
    this.storedHash,
    this.recomputedHash,
    this.hashVersion,
  });

  bool get isIntact => status == IntegrityStatus.intact;

  String get label => switch (status) {
    IntegrityStatus.intact => 'Integro',
    IntegrityStatus.broken => 'Selo quebrado - possivel adulteracao',
    IntegrityStatus.legacy => 'Selo legado nao recalculavel',
    IntegrityStatus.unsealed => 'Nao selado',
  };
}

class IntegrityVerificationService {
  IntegrityVerificationService({
    OccurrenceRepository? occurrenceRepository,
    OccurrenceEventRepository? eventRepository,
    SignatureRepository? signatureRepository,
    FirebaseFirestore? firestore,
  }) : _occurrenceRepository = occurrenceRepository,
       _eventRepository = eventRepository,
       _signatureRepository = signatureRepository,
       _firestore = firestore;

  final OccurrenceRepository? _occurrenceRepository;
  final OccurrenceEventRepository? _eventRepository;
  final SignatureRepository? _signatureRepository;
  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  OccurrenceRepository get _occurrences =>
      _occurrenceRepository ?? OccurrenceRepository(_db);
  OccurrenceEventRepository get _events =>
      _eventRepository ?? OccurrenceEventRepository(_db);
  SignatureRepository get _signatures =>
      _signatureRepository ?? SignatureRepository(firestore: _firestore);

  Future<IntegrityVerdict> verifyById(String occurrenceId) async {
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
    return verify(
      occurrence.copyWith(
        signatures: signatures,
        participations: participations,
        correctionRequests: correctionRequests,
      ),
      events: events,
    );
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
}
