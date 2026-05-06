import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/routine_model.dart';
import 'package:canil_gcm/services/gamification_service.dart';

class RoutineViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<RoutineModel> _routines = [];
  List<RoutineModel> get routines => _routines;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> addRoutine(RoutineModel routine) async {
    try {
      _setLoading(true);

      final docRef = _firestore.collection('routines').doc();
      final data = routine.toJson()..['id'] = docRef.id;
      await docRef.set(data);
      final newRoutine = RoutineModel.fromJson(data, docRef.id);
      _routines.insert(0, newRoutine);

      if (routine.handlerId.isNotEmpty) {
        await GamificationService().evaluateRoutine(routine.handlerId);
      }

      developer.log('Routine added: ${docRef.id}', name: 'RoutineViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error adding routine: $e',
        name: 'RoutineViewModel',
        error: e,
      );
      throw Exception('Falha ao salvar rotina: $e');
    }
  }

  Future<void> updateRoutine(RoutineModel routine) async {
    if (routine.id == null) return;

    try {
      _setLoading(true);

      await _firestore
          .collection('routines')
          .doc(routine.id)
          .set(routine.toJson(), SetOptions(merge: true));

      final index = _routines.indexWhere((r) => r.id == routine.id);
      if (index != -1) {
        _routines[index] = routine;
      }

      developer.log('Routine updated: ${routine.id}', name: 'RoutineViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error updating routine: $e',
        name: 'RoutineViewModel',
        error: e,
      );
      throw Exception('Falha ao atualizar rotina: $e');
    }
  }

  Future<void> deleteRoutine(String id) async {
    try {
      _setLoading(true);

      await _firestore.collection('routines').doc(id).delete();
      _routines.removeWhere((r) => r.id == id);

      developer.log('Routine deleted: $id', name: 'RoutineViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error deleting routine: $e',
        name: 'RoutineViewModel',
        error: e,
      );
      throw Exception('Falha ao excluir rotina: $e');
    }
  }

  Future<void> fetchRoutinesForDog(String dogId) async {
    try {
      _setLoading(true);

      final snapshot = await _firestore
          .collection('routines')
          .where('dogId', isEqualTo: dogId)
          .get();

      final fetchedRoutines = snapshot.docs
          .map((doc) => RoutineModel.fromJson(doc.data(), doc.id))
          .toList();
      fetchedRoutines.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _routines = fetchedRoutines;

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log(
        'Error fetching routines for dog $dogId: $e',
        name: 'RoutineViewModel',
        error: e,
      );
      throw Exception('Falha ao buscar rotinas: $e');
    }
  }
}
