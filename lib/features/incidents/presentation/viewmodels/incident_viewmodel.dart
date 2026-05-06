import 'package:flutter/material.dart';
import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/services/firestore_service.dart';
import 'package:canil_gcm/services/gamification_service.dart';

class IncidentViewModel extends ChangeNotifier {
  final FirestoreService _db = FirestoreService();
  List<Incident> _incidents = [];
  bool _isLoading = false;

  List<Incident> get incidents => _incidents;
  bool get isLoading => _isLoading;

  Future<void> fetchIncidentsForDog(String dogId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final raw = await _db.getIncidents(dogId: dogId);
      _incidents = raw
          .map((json) => Incident.fromJson(json as Map<String, dynamic>))
          .toList();
      _incidents.sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('Error fetching incidents: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAllIncidents() async {
    _isLoading = true;
    notifyListeners();
    try {
      final raw = await _db.getIncidents();
      _incidents = raw
          .map((json) => Incident.fromJson(json as Map<String, dynamic>))
          .toList();
      _incidents.sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('Error fetching all incidents: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveIncident(Incident incident) async {
    await _db.saveIncident(incident);
    _incidents.insert(0, incident);

    // GAMIFICATION TRIGGER
    if (incident.handlerId.isNotEmpty && incident.status == 'Concluída') {
      await GamificationService().evaluateIncidents(
        incident.handlerId,
        incident.displayResult,
        incident.type ?? '',
      );
    }

    notifyListeners();
  }

  Future<Incident?> findOpenIncident({String? dogId}) async {
    final raw = await _db.getOpenIncidents(dogId: dogId);
    if (raw.isEmpty) return null;

    final incidents =
        raw
            .map((json) => Incident.fromJson(json as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return incidents.first;
  }

  Future<void> updateIncident(Incident incident) async {
    _isLoading = true;
    notifyListeners();
    try {
      final previous = _incidents.cast<Incident?>().firstWhere(
        (i) => i?.id == incident.id,
        orElse: () => null,
      );
      await _db.saveIncident(incident); // set() handles upsert
      final index = _incidents.indexWhere((i) => i.id == incident.id);
      if (index != -1) {
        _incidents[index] = incident;
      }

      final wasClosed = previous?.status == 'Concluída';
      if (incident.handlerId.isNotEmpty &&
          incident.status == 'Concluída' &&
          !wasClosed) {
        await GamificationService().evaluateIncidents(
          incident.handlerId,
          incident.displayResult,
          incident.type ?? '',
        );
      }
    } catch (e) {
      debugPrint('Error updating incident: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteIncident(String id) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _db.deleteIncident(id);
      _incidents.removeWhere((i) => i.id == id);
    } catch (e) {
      debugPrint('Error deleting incident: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
