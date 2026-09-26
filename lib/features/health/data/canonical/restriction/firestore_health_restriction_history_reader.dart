import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/canonical/restriction/canonical_operational_restriction_parser.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_history_reader.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';

/// Leitor Firestore para a subcoleção `dogs/{dogId}/operational_restrictions`.
final class FirestoreHealthRestrictionHistoryReader
    implements HealthRestrictionHistoryReader {
  FirestoreHealthRestrictionHistoryReader({FirebaseFirestore? firestore})
    : _explicitFirestore = firestore;

  final FirebaseFirestore? _explicitFirestore;

  FirebaseFirestore get _firestore =>
      _explicitFirestore ?? FirebaseFirestore.instance;

  @override
  Future<List<OperationalRestriction>> getRestrictionsForDog(
    String dogId,
  ) async {
    final normalized = dogId.trim();
    if (normalized.isEmpty) return const [];

    try {
      final snapshot = await _firestore
          .collection('dogs')
          .doc(normalized)
          .collection('operational_restrictions')
          .get();

      final results = <OperationalRestriction>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        try {
          final restriction =
              CanonicalOperationalRestrictionParser.parseDocument(
                documentId: doc.id,
                queryDogId: normalized,
                data: data,
              );
          results.add(restriction);
        } catch (e) {
          debugPrint(
            '[FirestoreHealthRestrictionHistoryReader] falha ao parsear restrição ${doc.id}: $e',
          );
        }
      }
      return results;
    } catch (e) {
      debugPrint(
        '[FirestoreHealthRestrictionHistoryReader] erro na consulta Firestore: $e',
      );
      rethrow;
    }
  }
}

/// Leitor em memória para testes e composição isolada.
final class MemoryHealthRestrictionHistoryReader
    implements HealthRestrictionHistoryReader {
  MemoryHealthRestrictionHistoryReader({
    Map<String, List<OperationalRestriction>>? restrictionsByDogId,
    bool shouldFail = false,
    Exception? failureException,
  }) : _restrictionsByDogId = Map.of(restrictionsByDogId ?? const {}),
       _shouldFail = shouldFail,
       _failureException = failureException;

  final Map<String, List<OperationalRestriction>> _restrictionsByDogId;
  bool _shouldFail;
  Exception? _failureException;
  final List<String> queriedDogIds = [];

  void setShouldFail(bool shouldFail, [Exception? exception]) {
    _shouldFail = shouldFail;
    _failureException = exception;
  }

  void setRestrictions(String dogId, List<OperationalRestriction> restrictions) {
    _restrictionsByDogId[dogId.trim()] = List.of(restrictions);
  }

  @override
  Future<List<OperationalRestriction>> getRestrictionsForDog(
    String dogId,
  ) async {
    final normalized = dogId.trim();
    queriedDogIds.add(normalized);
    if (_shouldFail) {
      throw _failureException ??
          Exception('Falha simulada na leitura de restrições operacionais');
    }
    return List.unmodifiable(_restrictionsByDogId[normalized] ?? const []);
  }
}
