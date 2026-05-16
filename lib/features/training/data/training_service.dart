import 'package:cloud_firestore/cloud_firestore.dart';

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
    final docRef = await _firestore
        .collection('trainings')
        .add(session.toJson());
    return TrainingSessionModel.fromJson(session.toJson(), docRef.id);
  }

  Future<void> updateTrainingSession(TrainingSessionModel session) async {
    if (session.id == null) return;
    await _firestore
        .collection('trainings')
        .doc(session.id)
        .set(session.toJson(), SetOptions(merge: true));
  }

  Future<void> deleteTrainingSession(String id) {
    return _firestore.collection('trainings').doc(id).delete();
  }

  Future<List<TrainingSessionModel>> getTrainingsForDog(String dogId) async {
    final snapshot = await _firestore
        .collection('trainings')
        .where('dogId', isEqualTo: dogId)
        .get();

    final trainings = snapshot.docs
        .map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id))
        .toList();
    trainings.sort((a, b) => b.date.compareTo(a.date));
    return trainings;
  }

  Future<List<TrainingSessionModel>> getAllTrainings() async {
    final snapshot = await _firestore.collection('trainings').get();
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
}
