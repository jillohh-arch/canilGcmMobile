import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/training/data/training_service.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'package:canil_gcm/core/services/audit_service.dart';

class TrainingViewModel extends ChangeNotifier {
  final TrainingService _trainingService = TrainingService();
  final DogService _dogService = DogService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<TrainingSessionModel> _trainings = [];
  List<TrainingSessionModel> get trainings => _trainings;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Add a new training session
  Future<void> addTrainingSession(TrainingSessionModel session) async {
    try {
      _setLoading(true);

      final newSession = await _trainingService.addTrainingSession(session);

      // Update Dog's lastTrainingDate
      await _dogService.updateDogDates(
        session.dogId,
        lastTrainingDate: session.date,
      );

      _trainings.insert(0, newSession);

      AuditService.log(
        action: 'create',
        entityType: 'training',
        entityId: newSession.id ?? '',
        summary: 'Treino registrado: ${session.trainingType} — ${session.dogId}',
        after: {'trainingType': session.trainingType, 'dogId': session.dogId, 'duration': session.searchDuration},
      );

      developer.log(
        'Training session added: ${newSession.id}',
        name: 'TrainingViewModel',
      );

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error adding training session: $e',
        name: 'TrainingViewModel',
        error: e,
      );
      throw Exception('Falha ao salvar treino: $e');
    }
  }

  // Update an existing training session
  Future<void> updateTrainingSession(TrainingSessionModel session) async {
    if (session.id == null) return;
    try {
      _setLoading(true);

      await _trainingService.updateTrainingSession(session);

      // Update local state
      final index = _trainings.indexWhere((t) => t.id == session.id);
      if (index != -1) {
        _trainings[index] = session;
      }

      developer.log(
        'Training session updated: ${session.id}',
        name: 'TrainingViewModel',
      );
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error updating training session: $e',
        name: 'TrainingViewModel',
        error: e,
      );
      throw Exception('Falha ao atualizar treino: $e');
    }
  }

  // Delete a training session
  Future<void> deleteTrainingSession(String id) async {
    try {
      _setLoading(true);

      await _trainingService.deleteTrainingSession(id);

      // Update local state
      _trainings.removeWhere((t) => t.id == id);

      developer.log('Training session deleted: $id', name: 'TrainingViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error deleting training session: $e',
        name: 'TrainingViewModel',
        error: e,
      );
      throw Exception('Falha ao excluir treino: $e');
    }
  }

  // Fetch training sessions for a specific dog
  Future<void> fetchTrainingsForDog(String dogId) async {
    try {
      _setLoading(true);

      _trainings = await _trainingService.getTrainingsForDog(dogId);

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error fetching trainings for dog $dogId: $e',
        name: 'TrainingViewModel',
        error: e,
      );
      // Depending on the use case, you might want to rethrow or just keep _trainings empty
      throw Exception('Falha ao buscar treinos: $e');
    }
  }

  // Fetch all trainings
  Future<void> fetchAllTrainings() async {
    try {
      _setLoading(true);
      _trainings = await _trainingService.getAllTrainings();
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error fetching all trainings: $e',
        name: 'TrainingViewModel',
        error: e,
      );
      throw Exception('Falha ao buscar todos os treinos: $e');
    }
  }
}
