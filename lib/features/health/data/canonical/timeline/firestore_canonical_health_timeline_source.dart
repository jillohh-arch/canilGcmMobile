import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_health_timeline_entry_parser.dart';
import 'package:canil_gcm/features/health/data/canonical/timeline/canonical_timeline_cursor_codec.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';

/// Implementação concreta isolada da fonte de leitura da projeção canônica health_timeline.
///
/// Lê exclusivamente a subcoleção `dogs/{dogId}/health_timeline`.
/// Não inclui wiring no aplicativo nem de coexistência.
final class FirestoreCanonicalHealthTimelineSource
    implements HealthTimelineSource {
  FirestoreCanonicalHealthTimelineSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query) async {
    // 1. Rejeitar filtros não suportados na primeira ativação canônica (fail-closed)
    if (query.types.isNotEmpty ||
        query.caseId != null ||
        query.professional != null) {
      throw const HealthTimelineSourceException('unsupported_query_filter');
    }

    try {
      final collectionRef = _firestore
          .collection('dogs')
          .doc(query.dogId)
          .collection('health_timeline');

      Query<Map<String, dynamic>> firestoreQuery = collectionRef;

      // 2. Aplicar filtro de período (start / end em occurred_at)
      if (query.period.start != null) {
        firestoreQuery = firestoreQuery.where(
          'occurred_at',
          isGreaterThanOrEqualTo: Timestamp.fromDate(query.period.start!),
        );
      }
      if (query.period.end != null) {
        firestoreQuery = firestoreQuery.where(
          'occurred_at',
          isLessThanOrEqualTo: Timestamp.fromDate(query.period.end!),
        );
      }

      // 3. Ordenação canônica composta: occurred_at DESC, depois documentId DESC.
      //    A segunda ordenação garante desempate determinístico quando occurred_at
      //    é idêntico entre documentos — sem depender de ordering interno do Firestore.
      firestoreQuery = firestoreQuery
          .orderBy('occurred_at', descending: true)
          .orderBy(FieldPath.documentId, descending: true);

      // 4. Aplicar cursor composto por valores quando fornecido.
      //    O cursor usa exclusivamente os valores imutáveis gravados no token:
      //    [Timestamp(seconds, nanoseconds), documentId].
      //    Nenhuma leitura adicional do documento do cursor é realizada.
      //    O cursor permanece válido mesmo que o documento referenciado tenha sido
      //    removido, ou que seu occurred_at tenha sido alterado após a primeira página.
      if (query.cursor != null) {
        final position = CanonicalTimelineCursorCodec.decode(
          query.cursor!,
          dogId: query.dogId,
          query: query,
        );
        firestoreQuery = firestoreQuery.startAfter([
          position.timestamp,
          position.documentId,
        ]);
      }

      // 5. Aplicar pageSize + 1 para determinar se existem mais páginas
      final limit = query.pageSize + 1;
      firestoreQuery = firestoreQuery.limit(limit);

      // 6. Executar consulta
      final snapshot = await firestoreQuery.get();
      final docs = snapshot.docs;

      final hasMore = docs.length > query.pageSize;
      final pageDocs = hasMore ? docs.sublist(0, query.pageSize) : docs;

      if (pageDocs.isEmpty) {
        return HealthTimelinePage.empty();
      }

      // 7. Mapear cada documento (fail-closed: qualquer anomalia falha a página inteira)
      final items = <HealthTimelineEntryView>[];
      for (final doc in pageDocs) {
        final entry = CanonicalHealthTimelineEntryParser.parseDocument(
          documentId: doc.id,
          data: doc.data(),
          queryDogId: query.dogId,
        );
        items.add(entry);
      }

      // 8. Construir o próximo cursor composto por valores se houver mais resultados.
      //    Armazena occurred_at.seconds, occurred_at.nanoseconds e documentId do
      //    último item retornado — sem depender de DocumentSnapshot.
      HealthTimelineCursor? nextCursor;
      if (hasMore && pageDocs.isNotEmpty) {
        final lastDoc = pageDocs.last;
        final lastData = lastDoc.data();
        final lastOccurredAt = lastData['occurred_at'];
        if (lastOccurredAt is Timestamp) {
          nextCursor = CanonicalTimelineCursorCodec.encode(
            dogId: query.dogId,
            query: query,
            timestamp: lastOccurredAt,
            documentId: lastDoc.id,
          );
        } else {
          throw const HealthTimelineSourceException('invalid_occurred_at');
        }
      }

      return HealthTimelinePage(
        items: items,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    } on FirebaseException catch (e) {
      final isOffline =
          e.code == 'unavailable' || e.code == 'deadline-exceeded';
      throw HealthTimelineSourceException(
        'firestore_error: ${e.code}',
        isOffline: isOffline,
      );
    } catch (e) {
      if (e is HealthTimelineSourceException) rethrow;
      throw HealthTimelineSourceException('unexpected_error: $e');
    }
  }
}
