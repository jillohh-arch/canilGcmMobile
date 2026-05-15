import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/features/incidents/domain/occurrence_nature.dart';

class IncidentService {
  IncidentService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> saveIncident(Incident incident) async {
    await _db.collection('incidents').doc(incident.id).set(incident.toJson());
  }

  Future<void> deleteIncident(String id) async {
    await _db.collection('incidents').doc(id).delete();
  }

  Future<List<dynamic>> getIncidents({String? dogId}) async {
    try {
      // Tenta query com filtro e ordenação (requer índice composto)
      Query query = _db.collection('incidents');
      if (dogId != null) {
        query = query.where('dogId', isEqualTo: dogId);
      }
      query = query.orderBy('date', descending: true);

      final snapshot = await query.get();
      return snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      // Fallback: busca sem orderBy (índice composto pode não existir)
      try {
        Query query = _db.collection('incidents');
        if (dogId != null) {
          query = query.where('dogId', isEqualTo: dogId);
        }

        final snapshot = await query.get();
        final results = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          data['id'] = doc.id;
          return data;
        }).toList();

        // Ordena localmente por date desc
        results.sort((a, b) {
          final dateA = a['date'];
          final dateB = b['date'];
          if (dateA is Timestamp && dateB is Timestamp) {
            return dateB.compareTo(dateA);
          }
          return 0;
        });
        return results;
      } catch (e2) {
        // Último fallback: busca TODOS e filtra localmente
        final snapshot = await _db.collection('incidents').get();
        final results = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          data['id'] = doc.id;
          return data;
        }).toList();

        // Filtra por dogId localmente
        final filtered = dogId != null
            ? results.where((d) => d['dogId'] == dogId).toList()
            : results;

        // Ordena localmente
        filtered.sort((a, b) {
          final dateA = a['date'];
          final dateB = b['date'];
          if (dateA is Timestamp && dateB is Timestamp) {
            return dateB.compareTo(dateA);
          }
          return 0;
        });
        return filtered;
      }
    }
  }

  Future<List<dynamic>> getOpenIncidents({String? dogId}) async {
    Query query = _db
        .collection('incidents')
        .where('status', whereIn: ['Em andamento', 'Aberta']);

    if (dogId != null) {
      query = query.where('dogId', isEqualTo: dogId);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  Future<List<OccurrenceNature>> getOccurrenceNatures() async {
    final snapshot = await _db
        .collection('occurrence_natures')
        .where('active', isEqualTo: true)
        .get();

    final natures =
        snapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data['code'] ??= doc.id;
              return OccurrenceNature.fromJson(data);
            })
            .where((nature) => nature.name.trim().isNotEmpty)
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));

    return natures;
  }
}
