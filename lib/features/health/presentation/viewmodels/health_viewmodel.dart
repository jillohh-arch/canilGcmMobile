import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:canil_gcm/features/dogs/data/dog_service.dart';
import 'package:canil_gcm/features/gamification/data/gamification_service.dart';
import 'package:canil_gcm/features/health/data/health_service.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';

class HealthViewModel extends ChangeNotifier {
  final HealthService _healthService = HealthService();
  final DogService _dogService = DogService();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<HealthLogModel> _healthLogs = [];
  List<HealthLogModel> get healthLogs => _healthLogs;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> addHealthLog(HealthLogModel log) async {
    try {
      _setLoading(true);

      final newLog = await _healthService.addHealthLog(log);
      _healthLogs.insert(0, newLog);

      developer.log('Health log added: ${newLog.id}', name: 'HealthViewModel');

      await _syncDogHealthSnapshotSafely(newLog);
      await _evaluateGamificationSafely(newLog);

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error adding health log: $e',
        name: 'HealthViewModel',
        error: e,
      );
      throw Exception('Falha ao salvar registro médico: $e');
    }
  }

  Future<void> updateHealthLog(HealthLogModel log) async {
    if (log.id == null) return;
    try {
      _setLoading(true);
      await _healthService.updateHealthLog(log);

      final index = _healthLogs.indexWhere((h) => h.id == log.id);
      if (index != -1) {
        _healthLogs[index] = log;
      }

      await _syncDogHealthSnapshotSafely(log);

      developer.log('Health log updated: ${log.id}', name: 'HealthViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error updating health log: $e',
        name: 'HealthViewModel',
        error: e,
      );
      throw Exception('Falha ao atualizar registro médico: $e');
    }
  }

  Future<void> deleteHealthLog(String id) async {
    try {
      _setLoading(true);
      await _healthService.deleteHealthLog(id);
      _healthLogs.removeWhere((h) => h.id == id);

      developer.log('Health log deleted: $id', name: 'HealthViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error deleting health log: $e',
        name: 'HealthViewModel',
        error: e,
      );
      throw Exception('Falha ao excluir registro médico: $e');
    }
  }

  Future<void> fetchHealthLogsForDog(String dogId) async {
    try {
      _setLoading(true);

      _healthLogs = await _healthService.getHealthLogsForDog(dogId);

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error fetching health logs for dog $dogId: $e',
        name: 'HealthViewModel',
        error: e,
      );
      throw Exception('Falha ao buscar registros médicos: $e');
    }
  }

  Future<void> _syncDogHealthSnapshot(HealthLogModel log) {
    final isBathLog = log.logType == 'Banho';
    final isVaccineLog = log.logType == 'Vacina';

    return _dogService.updateDogDates(
      log.dogId,
      lastVaccineDate: isVaccineLog ? log.date : null,
      lastBathDate: isBathLog ? log.date : null,
      weight: log.weight,
    );
  }

  Future<void> _syncDogHealthSnapshotSafely(HealthLogModel log) async {
    try {
      await _syncDogHealthSnapshot(log);
    } catch (e) {
      developer.log(
        'Health log saved, but dog health snapshot sync failed: $e',
        name: 'HealthViewModel',
        error: e,
      );
    }
  }

  Future<void> _evaluateGamificationSafely(HealthLogModel log) async {
    try {
      await GamificationService().evaluateHealthLog(log.dogId, log.logType);
    } catch (e) {
      developer.log(
        'Health log saved, but gamification evaluation failed: $e',
        name: 'HealthViewModel',
        error: e,
      );
    }
  }
}
