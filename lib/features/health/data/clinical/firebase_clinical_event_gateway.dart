import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/clinical_event_gateway.dart';
import '../../domain/clinical_event_read_model.dart';
import 'clinical_event_document_parser.dart';

/// Implementação Firestore somente-leitura do gateway de eventos clínicos e emendas.
///
/// Garante:
/// - Acesso estrito por subcoleção escopada ao K9 e ao Caso Clínico.
/// - Zero chamadas de mutação/escrita.
/// - Ordenação canônica: `occurred_at DESC` para eventos, `recorded_at ASC` para emendas.
/// - Fallback defensivo em memória para ordenação cronológica se ocorrer degradação de metadados.
/// - Mapeamento seguro de exceções de transporte/permissão para [ClinicalEventReadException].
final class FirebaseClinicalEventGateway implements ClinicalEventGateway {
  FirebaseClinicalEventGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _eventsRef(
    String dogId,
    String caseId,
  ) => _firestore
      .collection('dogs')
      .doc(dogId)
      .collection('clinical_cases')
      .doc(caseId)
      .collection('clinical_events');

  CollectionReference<Map<String, dynamic>> _amendmentsRef(
    String dogId,
    String caseId,
    String eventId,
  ) => _eventsRef(dogId, caseId).doc(eventId).collection('clinical_amendments');

  @override
  Stream<List<ClinicalEventReadModel>> watchCaseEvents({
    required String dogId,
    required String caseId,
  }) {
    final cleanDogId = dogId.trim();
    final cleanCaseId = caseId.trim();
    if (cleanDogId.isEmpty || cleanCaseId.isEmpty) {
      return Stream.error(
        const ClinicalEventReadException(
          'dogId e caseId não podem ser vazios para watchCaseEvents',
          code: 'invalid_arguments',
        ),
      );
    }

    return _eventsRef(cleanDogId, cleanCaseId)
        .orderBy('occurred_at', descending: true)
        .snapshots()
        .map(
          (snapshot) => _parseAndSortEvents(
            snapshot.docs,
            dogId: cleanDogId,
            caseId: cleanCaseId,
          ),
        )
        .handleError((Object error, StackTrace stackTrace) {
          if (error is FirebaseException) {
            throw ClinicalEventReadException(
              error.message ?? 'Erro ao observar eventos clínicos',
              code: error.code,
              cause: error,
            );
          }
          throw ClinicalEventReadException(
            'Falha inesperada ao observar eventos clínicos: $error',
            code: 'unknown_error',
            cause: error,
          );
        });
  }

  @override
  Future<List<ClinicalEventReadModel>> readCaseEvents({
    required String dogId,
    required String caseId,
  }) async {
    final cleanDogId = dogId.trim();
    final cleanCaseId = caseId.trim();
    if (cleanDogId.isEmpty || cleanCaseId.isEmpty) {
      throw const ClinicalEventReadException(
        'dogId e caseId não podem ser vazios para readCaseEvents',
        code: 'invalid_arguments',
      );
    }

    try {
      final snapshot = await _eventsRef(
        cleanDogId,
        cleanCaseId,
      ).orderBy('occurred_at', descending: true).get();

      return _parseAndSortEvents(
        snapshot.docs,
        dogId: cleanDogId,
        caseId: cleanCaseId,
      );
    } on FirebaseException catch (e) {
      throw ClinicalEventReadException(
        e.message ?? 'Erro ao ler eventos clínicos',
        code: e.code,
        cause: e,
      );
    } catch (e) {
      if (e is ClinicalEventReadException) rethrow;
      throw ClinicalEventReadException(
        'Falha inesperada ao ler eventos clínicos: $e',
        code: 'unknown_error',
        cause: e,
      );
    }
  }

  @override
  Stream<List<ClinicalAmendmentReadModel>> watchEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  }) {
    final cleanDogId = dogId.trim();
    final cleanCaseId = caseId.trim();
    final cleanEventId = eventId.trim();
    if (cleanDogId.isEmpty || cleanCaseId.isEmpty || cleanEventId.isEmpty) {
      return Stream.error(
        const ClinicalEventReadException(
          'dogId, caseId e eventId não podem ser vazios para watchEventAmendments',
          code: 'invalid_arguments',
        ),
      );
    }

    return _amendmentsRef(cleanDogId, cleanCaseId, cleanEventId)
        .orderBy('recorded_at', descending: false)
        .snapshots()
        .map(
          (snapshot) => _parseAndSortAmendments(
            snapshot.docs,
            dogId: cleanDogId,
            caseId: cleanCaseId,
            eventId: cleanEventId,
          ),
        )
        .handleError((Object error, StackTrace stackTrace) {
          if (error is FirebaseException) {
            throw ClinicalEventReadException(
              error.message ?? 'Erro ao observar emendas clínicas',
              code: error.code,
              cause: error,
            );
          }
          throw ClinicalEventReadException(
            'Falha inesperada ao observar emendas clínicas: $error',
            code: 'unknown_error',
            cause: error,
          );
        });
  }

  @override
  Future<List<ClinicalAmendmentReadModel>> readEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  }) async {
    final cleanDogId = dogId.trim();
    final cleanCaseId = caseId.trim();
    final cleanEventId = eventId.trim();
    if (cleanDogId.isEmpty || cleanCaseId.isEmpty || cleanEventId.isEmpty) {
      throw const ClinicalEventReadException(
        'dogId, caseId e eventId não podem ser vazios para readEventAmendments',
        code: 'invalid_arguments',
      );
    }

    try {
      final snapshot = await _amendmentsRef(
        cleanDogId,
        cleanCaseId,
        cleanEventId,
      ).orderBy('recorded_at', descending: false).get();

      return _parseAndSortAmendments(
        snapshot.docs,
        dogId: cleanDogId,
        caseId: cleanCaseId,
        eventId: cleanEventId,
      );
    } on FirebaseException catch (e) {
      throw ClinicalEventReadException(
        e.message ?? 'Erro ao ler emendas clínicas',
        code: e.code,
        cause: e,
      );
    } catch (e) {
      if (e is ClinicalEventReadException) rethrow;
      throw ClinicalEventReadException(
        'Falha inesperada ao ler emendas clínicas: $e',
        code: 'unknown_error',
        cause: e,
      );
    }
  }

  @override
  Future<ClinicalEventReadModel?> readEvent({
    required String dogId,
    required String caseId,
    required String eventId,
  }) async {
    final cleanDogId = dogId.trim();
    final cleanCaseId = caseId.trim();
    final cleanEventId = eventId.trim();
    if (cleanDogId.isEmpty || cleanCaseId.isEmpty || cleanEventId.isEmpty) {
      throw const ClinicalEventReadException(
        'dogId, caseId e eventId não podem ser vazios para readEvent',
        code: 'invalid_arguments',
      );
    }

    try {
      final doc = await _eventsRef(
        cleanDogId,
        cleanCaseId,
      ).doc(cleanEventId).get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return ClinicalEventDocumentParser.parseEvent(
        dogId: cleanDogId,
        caseId: cleanCaseId,
        eventId: cleanEventId,
        data: doc.data()!,
      );
    } on FirebaseException catch (e) {
      throw ClinicalEventReadException(
        e.message ?? 'Erro ao ler evento clínico',
        code: e.code,
        cause: e,
      );
    } catch (e) {
      if (e is ClinicalEventReadException) rethrow;
      throw ClinicalEventReadException(
        'Falha inesperada ao ler evento clínico: $e',
        code: 'unknown_error',
        cause: e,
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Parsing & Ordering Helpers
  // ───────────────────────────────────────────────────────────────────────────

  List<ClinicalEventReadModel> _parseAndSortEvents(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String dogId,
    required String caseId,
  }) {
    final events = <ClinicalEventReadModel>[];
    for (final doc in docs) {
      final data = doc.data();
      final event = ClinicalEventDocumentParser.parseEvent(
        dogId: dogId,
        caseId: caseId,
        eventId: doc.id,
        data: data,
      );
      events.add(event);
    }

    // Ordenação defensiva em memória garantindo occurred_at decrescente
    // mesmo se algum documento tiver timestamp fallback.
    events.sort(
      (a, b) => b.occurredAtOrFallback.compareTo(a.occurredAtOrFallback),
    );
    return List<ClinicalEventReadModel>.unmodifiable(events);
  }

  List<ClinicalAmendmentReadModel> _parseAndSortAmendments(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String dogId,
    required String caseId,
    required String eventId,
  }) {
    final amendments = <ClinicalAmendmentReadModel>[];
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final data = doc.data();
      final amendment = ClinicalEventDocumentParser.parseAmendment(
        dogId: dogId,
        caseId: caseId,
        eventId: eventId,
        amendmentId: doc.id,
        data: data,
        ordinal: i + 1,
      );
      amendments.add(amendment);
    }

    // Ordenação cronológica crescente: recorded_at ASC
    amendments.sort((a, b) {
      final aTime = a.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.recordedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });

    return List<ClinicalAmendmentReadModel>.unmodifiable(amendments);
  }
}
