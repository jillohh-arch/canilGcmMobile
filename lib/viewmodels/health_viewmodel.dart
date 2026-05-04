import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/health_log_model.dart';
import '../services/firestore_service.dart';
import '../services/gamification_service.dart';

class HealthViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

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

      final docRef = await _firestore.collection('health_logs').add(log.toJson());
      await _syncDogHealthSnapshot(log);

      final newLog = HealthLogModel.fromJson(log.toJson(), docRef.id);
      _healthLogs.insert(0, newLog);

      developer.log('Health log added: ${docRef.id}', name: 'HealthViewModel');

      await GamificationService().evaluateHealthLog(log.dogId, log.logType);

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
      await _firestore
          .collection('health_logs')
          .doc(log.id)
          .set(log.toJson(), SetOptions(merge: true));

      await _syncDogHealthSnapshot(log);

      final index = _healthLogs.indexWhere((h) => h.id == log.id);
      if (index != -1) {
        _healthLogs[index] = log;
      }

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
      await _firestore.collection('health_logs').doc(id).delete();
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

      final snapshot = await _firestore
          .collection('health_logs')
          .where('dogId', isEqualTo: dogId)
          .get();

      final fetchedLogs = snapshot.docs
          .map((doc) => HealthLogModel.fromJson(doc.data(), doc.id))
          .toList();
      fetchedLogs.sort((a, b) => b.date.compareTo(a.date));

      _healthLogs = fetchedLogs;

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

    return _firestoreService.updateDogDates(
      log.dogId,
      lastVaccineDate: isVaccineLog ? log.date : null,
      lastBathDate: isBathLog ? log.date : null,
      weight: log.weight,
    );
  }
}
