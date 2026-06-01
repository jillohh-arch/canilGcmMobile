import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'package:canil_gcm/core/services/active_shift_identity_service.dart';
import 'package:canil_gcm/core/services/handler_identity_service.dart';
import 'package:canil_gcm/core/services/audit_service.dart';
import 'package:canil_gcm/features/training/data/training_repository.dart';
import 'package:canil_gcm/features/training/domain/training_model.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';

class TrainingService {
  TrainingService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _repository = TrainingRepository(
        firestore: firestore ?? FirebaseFirestore.instance,
      );

  final FirebaseFirestore _firestore;
  final TrainingRepository _repository;

  Future<TrainingSessionModel> addTrainingSession(
    TrainingSessionModel session,
  ) async {
    final docRef = _firestore.collection('trainings').doc();
    final entry = AuditService.buildInlineEntry(action: 'created');
    final after = {...await _trainingPayload(session), 'id': docRef.id};

    await docRef.set({
      ...after,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': [entry],
    });

    await AuditService.log(
      action: 'created',
      entityType: 'training',
      entityId: docRef.id,
      summary: _summaryFor(session, 'Treino registrado'),
      after: after,
    );

    return TrainingSessionModel.fromJson(after, docRef.id);
  }

  Future<void> updateTrainingSession(TrainingSessionModel session) async {
    if (session.id == null) return;
    final docRef = _firestore.collection('trainings').doc(session.id);
    final snapshot = await docRef.get();
    final before = snapshot.data();
    final after = await _trainingPayload(session);
    final entry = AuditService.buildInlineEntry(action: 'updated');

    await docRef.set({
      ...after,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    }, SetOptions(merge: true));

    await AuditService.log(
      action: 'updated',
      entityType: 'training',
      entityId: session.id!,
      summary: _summaryFor(session, 'Treino atualizado'),
      before: before,
      after: after,
    );
  }

  /// Soft delete: marca o treino como excluído sem removê-lo fisicamente.
  /// Grava `deleted_at`, `deleted_by`, `delete_reason` e registra no audit trail.
  ///
  /// [id] — ID do documento.
  /// [reason] — motivo obrigatório da exclusão.
  /// [collectionPath] — path da collection onde o documento reside.
  ///   Valores possíveis: 'trainings', 'training_sessions',
  ///   ou 'dogs/{dogId}/training_sessions'. Default: 'trainings'.
  Future<void> deleteTrainingSession(
    String id, {
    required String reason,
    String collectionPath = 'trainings',
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw StateError('Usuário deve estar autenticado para excluir treino');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('Motivo da exclusão não pode ser vazio');
    }

    final docRef = _firestore.collection(collectionPath).doc(id);

    final entry = AuditService.buildInlineEntry(
      action: 'deleted',
      reason: reason,
    );

    await docRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': userId,
      'delete_reason': reason,
      'deleted_reason': reason,
      'updated_at': FieldValue.serverTimestamp(),
      'audit_trail': FieldValue.arrayUnion([entry]),
    });

    await AuditService.log(
      action: 'deleted',
      entityType: 'training',
      entityId: id,
      summary: 'Sessão de treino excluída: $reason',
      reason: reason,
      metadata: {'collection': collectionPath},
    );
  }

  Future<List<TrainingSessionModel>> getTrainingsForDog(String dogId) async {
    final byKey = <String, TrainingSessionModel>{};

    // Buscar de cada collection independentemente para resiliência
    try {
      final query = SoftDeletable.activeOnly(
        _firestore.collection('trainings').where('dogId', isEqualTo: dogId),
      );
      final legacyTrainings = await query.get();
      for (final doc in legacyTrainings.docs) {
        final training = TrainingSessionModel.fromJson(doc.data(), doc.id);
        if (training.dogId == dogId) {
          byKey['${doc.reference.path}:${doc.id}'] = training;
        }
      }
    } catch (e) {
      debugPrint('[TrainingService] Erro ao buscar trainings: $e');
    }

    try {
      final query = SoftDeletable.activeOnly(
        _firestore.collection('trainings').where('dog_id', isEqualTo: dogId),
      );
      final legacyTrainings = await query.get();
      for (final doc in legacyTrainings.docs) {
        final training = TrainingSessionModel.fromJson(doc.data(), doc.id);
        if (training.dogId == dogId) {
          byKey['${doc.reference.path}:${doc.id}'] = training;
        }
      }
    } catch (e) {
      debugPrint('[TrainingService] Erro ao buscar trainings por dog_id: $e');
    }

    try {
      final query = SoftDeletable.activeOnly(
        _firestore
            .collection('training_sessions')
            .where('dogId', isEqualTo: dogId),
      );
      final rootSessions = await query.get();
      for (final doc in rootSessions.docs) {
        final training = TrainingSessionModel.fromJson(doc.data(), doc.id);
        if (training.dogId == dogId) {
          byKey['${doc.reference.path}:${doc.id}'] = training;
        }
      }
    } catch (e) {
      debugPrint('[TrainingService] Erro ao buscar training_sessions: $e');
    }

    try {
      final query = SoftDeletable.activeOnly(
        _firestore
            .collection('training_sessions')
            .where('dog_id', isEqualTo: dogId),
      );
      final rootSessions = await query.get();
      for (final doc in rootSessions.docs) {
        final training = TrainingSessionModel.fromJson(doc.data(), doc.id);
        if (training.dogId == dogId) {
          byKey['${doc.reference.path}:${doc.id}'] = training;
        }
      }
    } catch (e) {
      debugPrint(
        '[TrainingService] Erro ao buscar training_sessions por dog_id: $e',
      );
    }

    try {
      final query = SoftDeletable.activeOnly(
        _firestore
            .collection('dogs')
            .doc(dogId)
            .collection('training_sessions'),
      );
      final dogSessions = await query.get();
      for (final doc in dogSessions.docs) {
        final training = TrainingSessionModel.fromJson(doc.data(), doc.id);
        if (training.dogId == dogId || training.dogId.isEmpty) {
          // dogId pode estar vazio em subcollection (implícito pelo path)
          byKey['${doc.reference.path}:${doc.id}'] = training;
        }
      }
    } catch (e) {
      debugPrint(
        '[TrainingService] Erro ao buscar dogs/$dogId/training_sessions: $e',
      );
    }

    final trainings = byKey.values.toList();
    trainings.sort((a, b) => b.date.compareTo(a.date));
    return trainings;
  }

  Future<List<TrainingSessionModel>> getAllTrainings() async {
    final query = SoftDeletable.activeOnly(_firestore.collection('trainings'));
    final snapshot = await query.get();
    final trainings = snapshot.docs
        .map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id))
        .toList();
    trainings.sort((a, b) => b.date.compareTo(a.date));
    return trainings;
  }

  Stream<List<TrainingHubSession>> watchSessionsForDog(String dogId) {
    return _repository.watchSessionsForDog(dogId);
  }

  Stream<List<TrainingSpecialtyModel>> watchSpecialtiesForDog(String dogId) {
    return _repository.watchSpecialtiesForDog(dogId);
  }

  TrainingHubData buildHubData({
    required List<TrainingSpecialtyModel> specialties,
    required List<TrainingHubSession> sessions,
  }) {
    final sortedSessions = [...sessions]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final enhancedSpecialties = _enhanceSpecialties(
      specialties,
      sortedSessions,
    );
    final generalTrainings = _buildGeneralTrainings(
      sortedSessions,
      enhancedSpecialties,
    );
    final weekStart = _startOfWeek(DateTime.now());
    final weekCount = sortedSessions
        .where((session) => !session.date.isBefore(weekStart))
        .length;
    final lastTraining = sortedSessions.isEmpty ? null : sortedSessions.first;

    return TrainingHubData(
      specialties: enhancedSpecialties,
      generalTrainings: generalTrainings,
      recentSessions: sortedSessions.take(3).toList(),
      trainingsThisWeek: weekCount,
      lastTrainingLabel: formatRelativeTrainingDate(lastTraining?.date),
      suggestedFocus: _suggestNextFocus(enhancedSpecialties, sortedSessions),
    );
  }

  List<TrainingSpecialtyModel> _enhanceSpecialties(
    List<TrainingSpecialtyModel> specialties,
    List<TrainingHubSession> sessions,
  ) {
    return specialties.map((specialty) {
      final matchingSessions = sessions
          .where((session) => _matchesSpecialty(session, specialty))
          .toList();
      final lastSession = matchingSessions.isEmpty
          ? null
          : matchingSessions.first;

      return specialty.copyWith(
        lastTrainingDate: specialty.lastTrainingDate ?? lastSession?.date,
        progressPercentage: specialty.progressPercentage == 0
            ? _progressFromSpecialty(specialty)
            : specialty.progressPercentage,
      );
    }).toList()..sort((a, b) {
      final activeCompare = b.isActive.toString().compareTo(
        a.isActive.toString(),
      );
      if (activeCompare != 0) return activeCompare;
      return a.name.compareTo(b.name);
    });
  }

  List<TrainingGeneralTypeModel> _buildGeneralTrainings(
    List<TrainingHubSession> sessions,
    List<TrainingSpecialtyModel> specialties,
  ) {
    final grouped = <String, List<TrainingHubSession>>{};

    for (final session in sessions) {
      final isSpecialty = specialties.any(
        (specialty) => _matchesSpecialty(session, specialty),
      );
      if (isSpecialty || _isSpecialtyTrainingType(session.trainingType)) {
        continue;
      }

      final key = normalizeTrainingKey(session.trainingType);
      grouped.putIfAbsent(key, () => []).add(session);
    }

    final result = grouped.entries.map((entry) {
      final items = entry.value..sort((a, b) => b.date.compareTo(a.date));
      final latest = items.first;
      return TrainingGeneralTypeModel(
        id: entry.key,
        name: latest.trainingType,
        status: latest.statusLabel,
        lastTrainingDate: latest.date,
        sessionCount: items.length,
      );
    }).toList();

    for (final defaultName in const ['Obediência', 'Condicionamento']) {
      final key = normalizeTrainingKey(defaultName);
      final exists = result.any(
        (training) => normalizeTrainingKey(training.name) == key,
      );
      if (!exists) {
        result.add(
          TrainingGeneralTypeModel(
            id: key,
            name: defaultName,
            status: 'Disponível',
            lastTrainingDate: null,
            sessionCount: 0,
          ),
        );
      }
    }

    result.sort((a, b) {
      final aDate =
          a.lastTrainingDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.lastTrainingDate ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return result;
  }

  bool _matchesSpecialty(
    TrainingHubSession session,
    TrainingSpecialtyModel specialty,
  ) {
    final specialtyKey = normalizeTrainingKey(specialty.name);
    final sessionSpecialty = normalizeTrainingKey(session.specialty);
    final sessionType = normalizeTrainingKey(session.trainingType);

    return sessionSpecialty == specialtyKey ||
        sessionType == specialtyKey ||
        sessionSpecialty.contains(specialtyKey) ||
        specialtyKey.contains(sessionSpecialty) && sessionSpecialty.isNotEmpty;
  }

  bool _isSpecialtyTrainingType(String value) {
    final key = normalizeTrainingKey(value);
    return key.contains('detec') ||
        key.contains('faro') ||
        key.contains('scent') ||
        key.contains('guarda') ||
        key.contains('protec') ||
        key.contains('busca') ||
        key.contains('captura') ||
        key.contains('rastro');
  }

  int _progressFromSpecialty(TrainingSpecialtyModel specialty) {
    if (specialty.subAreas.isNotEmpty) {
      final operational = specialty.subAreas
          .where((subArea) => subArea.isOperational)
          .length;
      return ((operational / specialty.subAreas.length) * 100).round().clamp(
        0,
        100,
      );
    }
    if (specialty.isOperational) return 100;
    if (specialty.isInFormation) return 40;
    return 0;
  }

  String _suggestNextFocus(
    List<TrainingSpecialtyModel> specialties,
    List<TrainingHubSession> sessions,
  ) {
    if (specialties.isEmpty && sessions.isEmpty) return 'Sem dados';

    final formation = specialties.where(
      (specialty) => specialty.isInFormation || specialty.isNotStarted,
    );
    if (formation.isNotEmpty) {
      final ordered = formation.toList()
        ..sort((a, b) => a.progressPercentage.compareTo(b.progressPercentage));
      return ordered.first.name;
    }

    final lowProgress = specialties.where(
      (specialty) => specialty.progressPercentage < 75,
    );
    if (lowProgress.isNotEmpty) {
      final ordered = lowProgress.toList()
        ..sort((a, b) => a.progressPercentage.compareTo(b.progressPercentage));
      return ordered.first.name;
    }

    final withDates = specialties.where((s) => s.lastTrainingDate != null);
    if (withDates.isNotEmpty) {
      final ordered = withDates.toList()
        ..sort((a, b) => a.lastTrainingDate!.compareTo(b.lastTrainingDate!));
      return ordered.first.name;
    }

    if (specialties.isNotEmpty) return specialties.first.name;
    return sessions.first.trainingType;
  }

  DateTime _startOfWeek(DateTime now) {
    final start = now.subtract(Duration(days: now.weekday - 1));
    return DateTime(start.year, start.month, start.day);
  }

  String _summaryFor(TrainingSessionModel session, String prefix) {
    final dog = session.dogName.trim().isNotEmpty
        ? session.dogName.trim()
        : session.dogId;
    return '$prefix: ${session.trainingType} - $dog';
  }

  Future<Map<String, dynamic>> _trainingPayload(
    TrainingSessionModel session,
  ) async {
    final activeShift = await ActiveShiftIdentityService.resolve(
      firestore: _firestore,
      preferredRa: session.handlerId,
    );
    final handlerRa =
        activeShift?.handlerId ??
        _currentHandlerRa() ??
        session.handlerId.trim();
    final dogId = activeShift?.dogId ?? session.dogId;
    final payload = Map<String, dynamic>.from(session.toJson());
    payload['dogId'] = dogId;
    payload['dog_id'] = dogId;
    if (handlerRa.isNotEmpty) {
      payload['handlerId'] = handlerRa;
      payload['handler_id'] = handlerRa;
    }
    return payload;
  }

  String? _currentHandlerRa() {
    try {
      return HandlerIdentityService.raFromUser(
        FirebaseAuth.instance.currentUser,
      );
    } catch (_) {
      return null;
    }
  }
}
