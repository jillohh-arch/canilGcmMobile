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

  void _sortIncidents() {
    _incidents.sort((a, b) => b.date.compareTo(a.date));
  }

  void _upsertIncident(Incident incident) {
    final index = _incidents.indexWhere((i) => i.id == incident.id);
    if (index == -1) {
      _incidents.insert(0, incident);
    } else {
      _incidents[index] = incident;
    }
    _sortIncidents();
  }

  void _replaceWithFetchedIncidents(List<Incident> fetched, {String? dogId}) {
    final fetchedIds = fetched
        .map((incident) => incident.id)
        .where((id) => id.trim().isNotEmpty)
        .toSet();

    final localOpenIncidents = _incidents.where((incident) {
      if (!incident.isInProgress) return false;
      if (dogId != null && incident.dogId != dogId) return false;
      if (incident.id.trim().isEmpty) return false;
      return !fetchedIds.contains(incident.id);
    });

    _incidents = [...fetched, ...localOpenIncidents];
    _sortIncidents();
  }

  Future<void> fetchIncidentsForDog(String dogId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final raw = await _db.getIncidents(dogId: dogId);
      final fetched = raw
          .map((json) => Incident.fromJson(json as Map<String, dynamic>))
          .toList();
      _replaceWithFetchedIncidents(fetched, dogId: dogId);
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
      final fetched = raw
          .map((json) => Incident.fromJson(json as Map<String, dynamic>))
          .toList();
      _replaceWithFetchedIncidents(fetched);
    } catch (e) {
      debugPrint('Error fetching all incidents: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveIncident(Incident incident) async {
    await _db.saveIncident(incident);
    _upsertIncident(incident);

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

    final openIncident = incidents.first;
    _upsertIncident(openIncident);
    notifyListeners();

    return openIncident;
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
      _upsertIncident(incident);

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
      rethrow;
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
