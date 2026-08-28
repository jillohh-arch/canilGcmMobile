import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_document_mapper.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_integrity_exception.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_result.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_source.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Source Firestore **somente leitura** da Agenda Preventiva global (HW-4B).
///
/// Shape canônica — aprovada e comprovada em produção no HW-4A.2F, e coberta
/// pelo índice `dog_id, lifecycle_status, scheduled_for` (COLLECTION_GROUP):
/// ```
/// collectionGroup('health_schedule')
///   where dog_id in <chunk>
///   where lifecycle_status == <persistido>
///   orderBy scheduled_for ASC
/// ```
///
/// NÃO alterar esta shape sem alterar o índice e reprovar em produção:
/// remover o `orderBy` ou acrescentar um segundo campo de ordenação muda a
/// forma da query e devolve `failed-precondition`. Em particular, o reader
/// per-dog ordena por `(scheduled_for, documentId)`; aqui o desempate é
/// **local e estável**, justamente para preservar a shape aprovada.
///
/// Consulta somente `lifecycle_status` persistido. Estados temporais
/// (`today`/`upcoming`/`pending`/`overdue`) permanecem derivados na leitura
/// pela policy de apresentação e nunca são consultados nem persistidos.
final class FirestoreHealthScheduleGlobalSource
    implements HealthScheduleGlobalSource {
  FirestoreHealthScheduleGlobalSource({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const collectionId = HealthScheduleDocumentMapper.collectionId;

  /// Factory de produção (mesma instância padrão do app).
  static FirestoreHealthScheduleGlobalSource forDefault() =>
      FirestoreHealthScheduleGlobalSource();

  @override
  Future<HealthScheduleGlobalResult> loadGlobal(
    HealthScheduleGlobalQuery query,
  ) async {
    // Catálogo vazio ⇒ nada autorizado. Retorna vazio SEM emitir query.
    // Nunca degrada para collection-group irrestrita (seria negada e, pior,
    // representaria tentativa de leitura fora do escopo autorizado).
    if (query.isEmptyCatalog) {
      return HealthScheduleGlobalResult.empty();
    }

    try {
      final byIdentity = <String, HealthScheduleItem>{};
      var queriedChunks = 0;

      for (final chunk in query.chunks) {
        // SEMPRE `whereIn`, para qualquer chunk de 1..N.
        //
        // Um chunk de 1 cão NÃO degrada para `isEqualTo`: `dog_id == X` é uma
        // shape DIFERENTE de `dog_id in [X]`, e tratar as duas como
        // equivalentes é exatamente a presunção que o HW-4A proibiu — mudança
        // de shape é mudança de contrato/índice, não otimização. Manter um
        // único formato dá a propriedade que interessa: o Global Agenda Reader
        // tem UMA shape canônica, independente do tamanho do catálogo.
        final q = _db
            .collectionGroup(collectionId)
            .where('dog_id', whereIn: chunk)
            .where(
              'lifecycle_status',
              isEqualTo: query.lifecycleStatus.wireName,
            )
            .orderBy('scheduled_for', descending: false);

        // Limite por chunk: nunca carrega a coleção inteira. Busca `maxItems+1`
        // (mesmo idioma do reader per-dog) para conseguir distinguir "cabe no
        // limite" de "há mais dados" — sem esse item extra, `truncated` seria
        // sempre falso e a UI trataria lista cortada como lista completa.
        final snap = await q.limit(query.maxItems + 1).get();
        queriedChunks++;

        for (final doc in snap.docs) {
          final data = doc.data();
          // Autoridade de identidade = dog_id declarado no documento.
          // Fail-closed: documento sem dog_id canônico não vira item válido.
          final dogId =
              HealthScheduleDocumentMapper.requireCollectionGroupDogId(
                documentId: doc.id,
                data: data,
              );
          final item = HealthScheduleDocumentMapper.fromFirestore(
            dogId: dogId,
            documentId: doc.id,
            data: data,
          );
          if (query.types.isNotEmpty &&
              !query.types.contains(item.scheduleType)) {
            continue;
          }
          // Dedupe por identidade estável: chunks são disjuntos por construção,
          // mas identidade explícita protege contra sobreposição acidental.
          byIdentity['${item.dogId}/${item.id}'] = item;
        }
      }

      final merged = byIdentity.values.toList(growable: false)..sort(_compare);
      final truncated = merged.length > query.maxItems;
      final items = truncated ? merged.sublist(0, query.maxItems) : merged;

      return HealthScheduleGlobalResult(
        items: items,
        truncated: truncated,
        queriedChunks: queriedChunks,
      );
    } on HealthScheduleIntegrityException catch (e) {
      throw HealthScheduleSourceException(
        'Agenda global com documento inválido: ${e.reason}',
      );
    } on FirebaseException catch (e) {
      throw _mapFirebase(e);
    } catch (e) {
      if (e is HealthScheduleSourceException) rethrow;
      throw const HealthScheduleSourceException(
        'Falha ao carregar a agenda global.',
      );
    }
  }

  /// Ordenação global determinística.
  ///
  /// Chave primária `scheduled_for` (a mesma da query). Empate resolvido
  /// **localmente** por `dogId` e depois `id` — desempate estável sem
  /// acrescentar `orderBy` à query Firestore, que mudaria a shape aprovada.
  static int _compare(HealthScheduleItem a, HealthScheduleItem b) {
    final byDate = a.scheduledFor.compareTo(b.scheduledFor);
    if (byDate != 0) return byDate;
    final byDog = a.dogId.compareTo(b.dogId);
    if (byDog != 0) return byDog;
    return a.id.compareTo(b.id);
  }

  /// Traduz FirebaseException preservando a natureza do erro.
  ///
  /// `permission-denied` continua autorização; `failed-precondition` continua
  /// erro de query/índice. Nenhum dos dois é convertido em estado vazio.
  static HealthScheduleSourceException _mapFirebase(FirebaseException e) {
    final code = e.code.toLowerCase();
    if (code == 'unavailable' || code == 'network-request-failed') {
      return const HealthScheduleSourceException(
        'Sem conexão para carregar a agenda global.',
        isOffline: true,
      );
    }
    if (code == 'permission-denied') {
      return const HealthScheduleSourceException(
        'Sem permissão para carregar a agenda global.',
        isPermissionDenied: true,
      );
    }
    if (code == 'failed-precondition') {
      return const HealthScheduleSourceException(
        'Consulta da agenda global indisponível: índice ausente.',
      );
    }
    final lower = (e.message ?? e.toString()).toLowerCase();
    if (lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('offline') ||
        lower.contains('socket')) {
      return const HealthScheduleSourceException(
        'Sem conexão para carregar a agenda global.',
        isOffline: true,
      );
    }
    if (lower.contains('permission')) {
      return const HealthScheduleSourceException(
        'Sem permissão para carregar a agenda global.',
        isPermissionDenied: true,
      );
    }
    return const HealthScheduleSourceException(
      'Falha ao carregar a agenda global.',
    );
  }
}
