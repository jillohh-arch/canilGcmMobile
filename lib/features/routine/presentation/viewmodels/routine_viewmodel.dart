import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'package:canil_gcm/features/gamification/data/gamification_service.dart';
import 'package:canil_gcm/features/routine/data/routine_service.dart';
import 'package:canil_gcm/features/routine/domain/routine_model.dart';

class RoutineViewModel extends ChangeNotifier {
  final RoutineService _routineService = RoutineService();

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

      final newRoutine = await _routineService.addRoutine(routine);
      _routines.insert(0, newRoutine);

      if (routine.handlerId.isNotEmpty) {
        await GamificationService().evaluateRoutine(routine.handlerId);
      }

      developer.log(
        'Routine added: ${newRoutine.id}',
        name: 'RoutineViewModel',
      );
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

      await _routineService.updateRoutine(routine);

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

      await _routineService.deleteRoutine(id);
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

      _routines = await _routineService.getRoutinesForDog(dogId);

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
