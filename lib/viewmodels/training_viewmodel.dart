import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/training_session_model.dart';
import '../services/firestore_service.dart';
import '../services/gamification_service.dart';
import 'dart:developer' as developer;

class TrainingViewModel extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();
  
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
      
      final docRef = await _firestore.collection('trainings').add(session.toJson());
      
      // Update Dog's lastTrainingDate
      await _firestoreService.updateDogDates(session.dogId, lastTrainingDate: session.date);
      
      // Update local state by assigning the generated ID to the new model
      final newSession = TrainingSessionModel.fromJson(session.toJson(), docRef.id);
      _trainings.insert(0, newSession);
      
      developer.log('Training session added: ${docRef.id}', name: 'TrainingViewModel');
      
      // GAMIFICATION TRIGGER
      if (session.handlerId.isNotEmpty) {
        bool hasDistraction = false;
        if (session.metadata != null && session.metadata!['ambiente_com_distracao'] == true) {
          hasDistraction = true;
        }

        await GamificationService().evaluateTrainingSession(
          session.handlerId, 
          session.trainingType, 
          session.searchDuration ?? 0, 
          hasDistraction
        );
      }

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log('Error adding training session: $e', name: 'TrainingViewModel', error: e);
      throw Exception('Falha ao salvar treino: $e');
    }
  }

  // Update an existing training session
  Future<void> updateTrainingSession(TrainingSessionModel session) async {
    if (session.id == null) return;
    try {
      _setLoading(true);
      
      await _firestore.collection('trainings').doc(session.id).set(session.toJson(), SetOptions(merge: true));
      
      // Update local state
      final index = _trainings.indexWhere((t) => t.id == session.id);
      if (index != -1) {
        _trainings[index] = session;
      }
      
      developer.log('Training session updated: ${session.id}', name: 'TrainingViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log('Error updating training session: $e', name: 'TrainingViewModel', error: e);
      throw Exception('Falha ao atualizar treino: $e');
    }
  }

  // Delete a training session
  Future<void> deleteTrainingSession(String id) async {
    try {
      _setLoading(true);
      
      await _firestore.collection('trainings').doc(id).delete();
      
      // Update local state
      _trainings.removeWhere((t) => t.id == id);
      
      developer.log('Training session deleted: $id', name: 'TrainingViewModel');
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log('Error deleting training session: $e', name: 'TrainingViewModel', error: e);
      throw Exception('Falha ao excluir treino: $e');
    }
  }

  // Fetch training sessions for a specific dog
  Future<void> fetchTrainingsForDog(String dogId) async {
    try {
      _setLoading(true);
      
      final snapshot = await _firestore
          .collection('trainings')
          .where('dogId', isEqualTo: dogId)
          .get();

      final fetchedTrainings = snapshot.docs.map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id)).toList();
      
      // Sort locally to avoid requiring Firebase composite index
      fetchedTrainings.sort((a, b) => b.date.compareTo(a.date));
      _trainings = fetchedTrainings;
      
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log('Error fetching trainings for dog $dogId: $e', name: 'TrainingViewModel', error: e);
      // Depending on the use case, you might want to rethrow or just keep _trainings empty
      throw Exception('Falha ao buscar treinos: $e');
    }
  }

  // Fetch all trainings (For Gamification Ranking)
  Future<void> fetchAllTrainings() async {
    try {
      _setLoading(true);
      final snapshot = await _firestore.collection('trainings').get();
      final fetchedTrainings = snapshot.docs.map((doc) => TrainingSessionModel.fromJson(doc.data(), doc.id)).toList();
      fetchedTrainings.sort((a, b) => b.date.compareTo(a.date));
      _trainings = fetchedTrainings;
      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      developer.log('Error fetching all trainings: $e', name: 'TrainingViewModel', error: e);
      throw Exception('Falha ao buscar todos os treinos: $e');
    }
  }
}
