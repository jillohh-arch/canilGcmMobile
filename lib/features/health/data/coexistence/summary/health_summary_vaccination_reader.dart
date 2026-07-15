import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/core/mixins/soft_deletable.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';

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

  Future<HealthSummarySectionData<HealthSummaryVaccinationView>> read(
    String dogId,
  ) async {
    try {
      final facts = await _loadFacts(dogId);
      if (facts.isEmpty) {
        return const HealthSummarySectionData.notRecorded(
          message: 'Nenhuma vacinação registrada',
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
      return HealthSummarySectionData.unavailable(
        message: e.message ?? 'Falha ao ler vacinação [${e.code}]',
      );
    } catch (e) {
      return HealthSummarySectionData.unavailable(
        message: 'Falha ao ler vacinação: $e',
      );
    }
  }

  static Future<List<HealthSummaryVaccinationFact>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    // Fallback `vacinas` **somente** quando a fonte principal responde vazia.
    // Se health_events falhar (permission-denied / offline), NÃO esconder via fallback.
    final fromEvents = await _fromHealthEvents(firestore, dogId);
    if (fromEvents.isNotEmpty) return fromEvents;
    return _fromVacinasRoot(firestore, dogId);
  }

  static Future<List<HealthSummaryVaccinationFact>> _fromHealthEvents(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final query = firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_events');
    final active = SoftDeletable.activeOnly(
      query,
    ).orderBy('date', descending: true).limit(50);
    final snap = await active.get();
    final facts = <HealthSummaryVaccinationFact>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] ?? data['logType'])?.toString().toLowerCase();
      if (type != 'vaccination' && type != 'vacina' && type != 'vacinação') {
        continue;
      }
      final at = HealthSummaryDateParse.tryParse(data['date']);
      if (at == null) continue;
      final subtype = data['subtype']?.toString().trim();
      final name = (subtype != null && subtype.isNotEmpty)
          ? subtype
          : data['healthObservations']?.toString().trim();
      // nextDueDate é o campo explícito de próxima dose no health_events.
      facts.add(
        HealthSummaryVaccinationFact(
          occurredAt: at,
          name: name,
          nextDueAt: HealthSummaryDateParse.tryParse(data['nextDueDate']),
        ),
      );
    }
    return facts;
  }

  static Future<List<HealthSummaryVaccinationFact>> _fromVacinasRoot(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    try {
      final snap = await firestore
          .collection('vacinas')
          .where('caoId', isEqualTo: dogId)
          .orderBy('dataAplicacao', descending: true)
          .limit(20)
          .get();
      return _mapVacinas(snap.docs);
    } on FirebaseException catch (e) {
      // permission/auth: não mascarar com segunda tentativa.
      if (e.code == 'permission-denied' ||
          e.code == 'unauthenticated' ||
          e.code == 'unavailable') {
        rethrow;
      }
      // Provável índice ausente — tenta sem orderBy e ordena no cliente.
      final snap = await firestore
          .collection('vacinas')
          .where('caoId', isEqualTo: dogId)
          .limit(40)
          .get();
      final facts = _mapVacinas(snap.docs);
      facts.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      return facts;
    }
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
}
