import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_soft_delete.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

/// Fato de vacinação já materializado (sem inventar status clínico).
final class HealthSummaryVaccinationFact {
  const HealthSummaryVaccinationFact({
    required this.occurredAt,
    this.name,
    this.nextDueAt,
  });

  final DateTime occurredAt;
  final String? name;
  final DateTime? nextDueAt;
}

/// Leitura conservadora de vacinação a partir de fontes legadas.
///
/// Ordem de autoridade:
/// 1. `dogs/{dogId}/health_events` com `type == vaccination` (CRUD mobile ativo);
/// 2. fallback `vacinas` raiz filtrado por `caoId` (sem normalizar `status`).
///
/// **Nunca** inventa "Em dia" / "Atrasado". `summaryLabel` permanece null
/// salvo se no futuro houver campo explícito de resumo (não existe hoje).
class HealthSummaryVaccinationReader {
  HealthSummaryVaccinationReader({
    FirebaseFirestore? firestore,
    Future<List<HealthSummaryVaccinationFact>> Function(String dogId)?
    loadFacts,
  }) : _loadFacts =
           loadFacts ??
           ((dogId) => _loadFromFirestore(
             firestore ?? FirebaseFirestore.instance,
             dogId,
           ));

  final Future<List<HealthSummaryVaccinationFact>> Function(String dogId)
  _loadFacts;

  /// Quantos fatos de vacinação ativos buscar (1 basta para o card; margem para
  /// ordenação / próximos).
  static const int activeVaccinationTarget = 5;

  Future<HealthSummarySectionData<HealthSummaryVaccinationView>> read(
    String dogId,
  ) async {
    try {
      final facts = await _loadFacts(dogId);
      if (facts.isEmpty) {
        return const HealthSummarySectionData.notRecorded(
          message: HealthSummaryUserCopy.vaccinationNotRecorded,
        );
      }
      facts.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final latest = facts.first;
      final name = latest.name?.trim();
      return HealthSummarySectionData.available(
        HealthSummaryVaccinationView(
          // Sem status clínico inventado — apenas fatos.
          summaryLabel: null,
          lastRecordLabel: (name == null || name.isEmpty) ? null : name,
          nextDueAt: latest.nextDueAt,
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryVaccinationReader] unavailable [${e.code}]: ${e.message}',
      );
      return HealthSummarySectionData.unavailable(
        message: _unavailableMessage(e),
      );
    } on HealthSummaryScanTruncatedException catch (e) {
      debugPrint('[HealthSummaryVaccinationReader] truncated: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.vaccinationUnavailable,
      );
    } catch (e) {
      debugPrint('[HealthSummaryVaccinationReader] unavailable: $e');
      return const HealthSummarySectionData.unavailable(
        message: HealthSummaryUserCopy.vaccinationUnavailable,
      );
    }
  }

  static String _unavailableMessage(FirebaseException e) {
    if (e.code == 'unavailable') {
      return HealthSummaryUserCopy.networkUnavailable;
    }
    return HealthSummaryUserCopy.vaccinationUnavailable;
  }

  static Future<List<HealthSummaryVaccinationFact>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    // Fallback `vacinas` **somente** quando a fonte principal está
    // **conclusivamente** vazia. Truncamento por maxPages → unavailable
    // (não fingir vazio nem acionar fallback).
    final scan = await _fromHealthEvents(firestore, dogId);
    if (scan.truncated) {
      throw HealthSummaryScanTruncatedException(
        scope: 'health_events/vaccination',
        pageSize: HealthSummarySoftDelete.defaultPageSize,
        maxPages: HealthSummarySoftDelete.defaultMaxPages,
        targetActive: activeVaccinationTarget,
        pagesScanned: scan.pagesScanned,
        itemsFound: scan.items.length,
      );
    }
    if (scan.items.isNotEmpty) return List.of(scan.items);
    // isConclusiveEmpty (ou items vazios com exhausted).
    return _fromVacinasRoot(firestore, dogId);
  }

  static Future<
    HealthSummaryPaginatedActiveResult<HealthSummaryVaccinationFact>
  >
  _fromHealthEvents(FirebaseFirestore firestore, String dogId) async {
    // Sem SoftDeletable.activeOnly + orderBy (índice composto).
    // Pagina orderBy(date) e filtra soft-delete + tipo no cliente até achar
    // vacinas ativas — evita janela só com deletados.
    final ordered = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events')
        .orderBy('date', descending: true);

    return HealthSummarySoftDelete.paginateActiveMapped(
      orderedQuery: ordered,
      targetActive: activeVaccinationTarget,
      debugScope: 'health_events/vaccination',
      tryMap: (doc) {
        final data = doc.data();
        if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
        final type = (data['type'] ?? data['logType'])
            ?.toString()
            .toLowerCase();
        if (type != 'vaccination' && type != 'vacina' && type != 'vacinação') {
          return null;
        }
        final at = HealthSummaryDateParse.tryParse(data['date']);
        if (at == null) return null;
        final subtype = data['subtype']?.toString().trim();
        final name = (subtype != null && subtype.isNotEmpty)
            ? subtype
            : data['healthObservations']?.toString().trim();
        return HealthSummaryVaccinationFact(
          occurredAt: at,
          name: name,
          nextDueAt: HealthSummaryDateParse.tryParse(data['nextDueDate']),
        );
      },
    );
  }

  static Future<List<HealthSummaryVaccinationFact>> _fromVacinasRoot(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    // Apenas equality em caoId — sem orderBy (evita índice composto).
    // Ordenação no cliente. Sem soft-delete canônico nesta coleção legada.
    final snap = await firestore
        .collection('vacinas')
        .where('caoId', isEqualTo: dogId)
        .limit(40)
        .get();
    final facts = _mapVacinas(snap.docs);
    facts.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return facts;
  }

  static List<HealthSummaryVaccinationFact> _mapVacinas(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final facts = <HealthSummaryVaccinationFact>[];
    for (final doc in docs) {
      final data = doc.data();
      final at = HealthSummaryDateParse.tryParse(data['dataAplicacao']);
      if (at == null) continue;
      final nome = data['nome']?.toString().trim();
      // NÃO mapear dataVencimento → nextDueAt: no legado costuma ser validade
      // do produto, e a UI 2C rotula nextDueAt como "Próxima dose".
      // status livre da coleção vacinas é ignorado (não normalizado).
      facts.add(
        HealthSummaryVaccinationFact(
          occurredAt: at,
          name: (nome == null || nome.isEmpty) ? null : nome,
          nextDueAt: null,
        ),
      );
    }
    return facts;
  }

  /// Mapeia docs de health_events (já em ordem) → fatos de vacinação ativos.
  /// Exposto para testes de soft-delete + janela sem Firebase.
  @visibleForTesting
  static HealthSummaryPaginatedActiveResult<HealthSummaryVaccinationFact>
  mapHealthEventDocsForTest(
    List<Map<String, dynamic>> docs, {
    int? targetActive,
    int pageSize = HealthSummarySoftDelete.defaultPageSize,
    int maxPages = HealthSummarySoftDelete.defaultMaxPages,
  }) {
    final target = targetActive ?? activeVaccinationTarget;
    return HealthSummarySoftDelete.collectActiveFromPagesResult(
      pages: [docs],
      targetActive: target,
      pageSize: pageSize,
      maxPages: maxPages,
      tryMap: (data, pageIndex, docIndex) {
        if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
        final type = (data['type'] ?? data['logType'])
            ?.toString()
            .toLowerCase();
        if (type != 'vaccination' && type != 'vacina' && type != 'vacinação') {
          return null;
        }
        final at = HealthSummaryDateParse.tryParse(data['date']);
        if (at == null) return null;
        return HealthSummaryVaccinationFact(
          occurredAt: at,
          name: data['subtype']?.toString(),
          nextDueAt: HealthSummaryDateParse.tryParse(data['nextDueDate']),
        );
      },
    );
  }

  /// Coleta multi-página (testes) com a mesma semântica de truncamento.
  @visibleForTesting
  static HealthSummaryPaginatedActiveResult<HealthSummaryVaccinationFact>
  collectVaccinationFromPagesForTest(
    List<List<Map<String, dynamic>>> pages, {
    int? targetActive,
    int pageSize = HealthSummarySoftDelete.defaultPageSize,
    int maxPages = HealthSummarySoftDelete.defaultMaxPages,
  }) {
    final target = targetActive ?? activeVaccinationTarget;
    return HealthSummarySoftDelete.collectActiveFromPagesResult(
      pages: pages,
      targetActive: target,
      pageSize: pageSize,
      maxPages: maxPages,
      tryMap: (data, pageIndex, docIndex) {
        if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
        final type = (data['type'] ?? data['logType'])
            ?.toString()
            .toLowerCase();
        if (type != 'vaccination' && type != 'vacina' && type != 'vacinação') {
          return null;
        }
        final at = HealthSummaryDateParse.tryParse(data['date']);
        if (at == null) return null;
        return HealthSummaryVaccinationFact(
          occurredAt: at,
          name: data['subtype']?.toString(),
          nextDueAt: HealthSummaryDateParse.tryParse(data['nextDueDate']),
        );
      },
    );
  }
}
