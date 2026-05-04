import 'package:flutter/material.dart';
import '../models/dog.dart';
import '../services/firestore_service.dart';

class DogViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  List<Dog> _dogs = [];
  bool _isLoading = false;
  String? _error;

  List<Dog> get dogs => _dogs;
  bool get isLoading => _isLoading;
  String? get error => _error;

  DogViewModel() {
    _listenToDogs();
  }

  void _listenToDogs() {
    _setLoading(true);
    _firestoreService.getDogs().listen(
      (dogsData) {
        _dogs = dogsData;
        _setLoading(false);
      },
      onError: (e) {
        _error = e.toString();
        _setLoading(false);
      },
    );
  }

  Future<void> saveDog(Dog dog) async {
    try {
      await _firestoreService.saveDog(dog);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      throw Exception('Falha ao salvar: $e');
    }
  }

  Future<void> updateDogWeight(String dogId, double weight) async {
    try {
      await _firestoreService.updateDogWeight(dogId, weight);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      throw Exception('Falha ao atualizar peso: $e');
    }
  }

  Future<void> deleteDog(String id) async {
    try {
      await _firestoreService.deleteDog(id);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  bool hasTrainingAlert(Dog dog) {
    if (dog.lastTrainingDate == null) return true; // No training ever
    final diff = DateTime.now().difference(dog.lastTrainingDate!);
    return diff.inDays > 3;
  }

  bool hasHealthAlert(Dog dog) {
    if (dog.lastVaccineDate == null) return true; // No vaccines ever
    final diff = DateTime.now().difference(dog.lastVaccineDate!);
    return diff.inDays > 365;
  }
}
