import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_cursor_codec.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_document_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_integrity_exception.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Source Firestore **somente leitura** da Agenda Preventiva (Fase 4C).
///
/// Caminho canônico: `dogs/{dogId}/health_schedule`.
///
/// Query operacional (estável na própria query):
/// ```
/// where lifecycle_status == open (default se query.lifecycleStatuses vazio)
/// orderBy scheduled_for ASC
/// orderBy FieldPath.documentId ASC
/// startAfter(scheduled_for, documentId)  // páginas seguintes
/// limit pageSize+1
/// ```
///
/// Cursor opaco: `HealthScheduleCursor` (timestamp + id), sem vazar
/// `DocumentSnapshot` para presentation/domain. Internamente, quando o
/// documento do cursor ainda existe, usa `startAfterDocument` (compatível
/// com Fake e Firestore real); senão, `startAfter([ts, id])`.
///
/// **Sem writes.** Não consulta coleções legadas.
final class FirestoreHealthScheduleSource implements HealthScheduleSource {
  FirestoreHealthScheduleSource({FirebaseFirestore? firestore})
    : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  static const collectionId = HealthScheduleDocumentMapper.collectionId;

  /// Factory de produção (mesma instância padrão do app).
  static FirestoreHealthScheduleSource forDefault() =>
      FirestoreHealthScheduleSource();

  @override
  Future<HealthSchedulePage> loadPage(HealthScheduleQuery query) async {
    try {
      final dogId = query.dogId;
      final pageSize = query.pageSize.clamp(1, 100);

      // Contrato operacional 4C: lifecycle vazio ⇒ apenas open.
      final statuses = query.lifecycleStatuses.isEmpty
          ? <ScheduleLifecycleStatus>{ScheduleLifecycleStatus.open}
          : query.lifecycleStatuses;

      final col = _db.collection('dogs').doc(dogId).collection(collectionId);

      Query<Map<String, dynamic>> q = col;

      if (statuses.length == 1) {
        q = q.where('lifecycle_status', isEqualTo: statuses.first.wireName);
      } else {
        q = q.where(
          'lifecycle_status',
          whereIn: statuses.map((s) => s.wireName).toList(),
        );
      }

      // Ordenação determinística na query Firestore.
      q = q
          .orderBy('scheduled_for', descending: false)
          .orderBy(FieldPath.documentId, descending: false);

      final cursor = query.cursor;
      if (cursor != null) {
        final pos = HealthScheduleCursorCodec.decode(cursor);
        q = await _applyStartAfter(base: q, collection: col, position: pos);
      }

      final snap = await q.limit(pageSize + 1).get();
      final docs = snap.docs;
      final hasMore = docs.length > pageSize;
      final pageDocs = hasMore ? docs.sublist(0, pageSize) : docs;

      if (pageDocs.isEmpty) {
        return HealthSchedulePage.empty();
      }

      final items = <HealthScheduleItem>[];
      for (final doc in pageDocs) {
        final item = HealthScheduleDocumentMapper.fromFirestore(
          dogId: dogId,
          documentId: doc.id,
          data: doc.data(),
        );
        // Filtro de tipo continua local (sem índice/query remota nesta fase).
        if (query.types.isNotEmpty &&
            !query.types.contains(item.scheduleType)) {
          continue;
        }
        items.add(item);
      }

      // Cursor do último documento da página Firestore (não do filtro local).
      final lastDoc = pageDocs.last;
      final lastTs = lastDoc.data()['scheduled_for'];
      final lastScheduled = lastTs is Timestamp
          ? lastTs.toDate().toUtc()
          : (items.isNotEmpty
                ? items.last.scheduledFor.toUtc()
                : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));

      final nextCursor = hasMore
          ? HealthScheduleCursorCodec.encode(
              HealthScheduleCursorPosition(
                scheduledFor: lastScheduled,
                documentId: lastDoc.id,
              ),
            )
          : null;

      if (items.isEmpty) {
        if (hasMore && nextCursor != null) {
          return HealthSchedulePage(
            items: const [],
            nextCursor: nextCursor,
            hasMore: true,
          );
        }
        return HealthSchedulePage.empty();
      }

      return HealthSchedulePage(
        items: items,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    } on HealthScheduleIntegrityException catch (e) {
      throw HealthScheduleSourceException(
        'Dados da agenda inconsistentes (doc=${e.documentId}).',
      );
    } on FormatException catch (e) {
      throw HealthScheduleSourceException(
        'Cursor de paginação inválido: ${e.message}',
      );
    } on FirebaseException catch (e) {
      throw _mapFirebase(e);
    } catch (e) {
      if (e is HealthScheduleSourceException) rethrow;
      throw const HealthScheduleSourceException(
        'Falha ao carregar a agenda preventiva.',
      );
    }
  }

  /// Aplica avanço de cursor com ordenação (scheduled_for, documentId).
  ///
  /// Preferência: `startAfterDocument` quando o doc ainda existe (valores
  /// de ordenação alinhados ao índice). Fallback: `startAfter([ts, id])`.
  static Future<Query<Map<String, dynamic>>> _applyStartAfter({
    required Query<Map<String, dynamic>> base,
    required CollectionReference<Map<String, dynamic>> collection,
    required HealthScheduleCursorPosition position,
  }) async {
    final snap = await collection.doc(position.documentId).get();
    if (snap.exists) {
      return base.startAfterDocument(snap);
    }
    // Documento removido: avança por valores explícitos da ordenação.
    return base.startAfter([
      Timestamp.fromDate(position.scheduledFor.toUtc()),
      position.documentId,
    ]);
  }

  static HealthScheduleSourceException _mapFirebase(FirebaseException e) {
    final code = e.code.toLowerCase();
    if (code == 'unavailable' || code == 'network-request-failed') {
      return const HealthScheduleSourceException(
        'Sem conexão para carregar a agenda preventiva.',
        isOffline: true,
      );
    }
    if (code == 'permission-denied') {
      return const HealthScheduleSourceException(
        'Sem permissão para carregar a agenda preventiva.',
        isPermissionDenied: true,
      );
    }
    if (code == 'failed-precondition') {
      return const HealthScheduleSourceException(
        'Consulta de agenda temporariamente indisponível.',
      );
    }
    final lower = (e.message ?? e.toString()).toLowerCase();
    if (lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('offline') ||
        lower.contains('socket')) {
      return const HealthScheduleSourceException(
        'Sem conexão para carregar a agenda preventiva.',
        isOffline: true,
      );
    }
    if (lower.contains('permission')) {
      return const HealthScheduleSourceException(
        'Sem permissão para carregar a agenda preventiva.',
        isPermissionDenied: true,
      );
    }
    return const HealthScheduleSourceException(
      'Falha ao carregar a agenda preventiva.',
    );
  }
}
