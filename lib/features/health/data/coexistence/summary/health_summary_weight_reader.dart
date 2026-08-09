import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:canil_gcm/features/health/domain/weight_collection_policy.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_section_status.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

/// Documento bruto de `weight_records` na fronteira do reader (WEIGHT-01E-C1).
///
/// A fronteira carrega o documento inteiro — e não um par
/// peso/data já filtrado — para que a classificação continue sendo feita pelo
/// parser/adapter central e para que `entityId`, `recorded_at` e o estado
/// documental (`valid`/`invalidated`/`malformed`/`unsupported`) cheguem
/// íntegros à policy coletiva. Um seam mais estreito não conseguiria
/// representar bloqueadores nem desempate canônico.
final class HealthSummaryWeightDocument {
  const HealthSummaryWeightDocument({
    required this.entityId,
    required this.data,
  });

  final String entityId;
  final Map<String, dynamic> data;
}

/// Leitura read-only de peso a partir de `dogs/{dogId}/weight_records`.
///
/// Autoridade canônica de peso no mobile atual (ADR-006 / WeightHistoryService).
/// Não mescla `weight_history` silenciosamente.
/// Não escreve.
class HealthSummaryWeightReader {
  HealthSummaryWeightReader({
    FirebaseFirestore? firestore,
    Future<List<HealthSummaryWeightDocument>> Function(String dogId)?
    loadDocuments,
  }) : _loadDocuments =
           loadDocuments ??
           ((dogId) => _loadFromFirestore(
             firestore ?? FirebaseFirestore.instance,
             dogId,
           ));

  final Future<List<HealthSummaryWeightDocument>> Function(String dogId)
  _loadDocuments;

  static const int trendLimit = 30;

  Future<HealthSummarySectionData<HealthSummaryWeightView>> readCurrent(
    String dogId,
  ) async {
    final bundle = await readBundle(dogId);
    return bundle.current;
  }

  Future<HealthSummarySectionData<HealthSummaryWeightTrendView>> readTrend(
    String dogId,
  ) async {
    final bundle = await readBundle(dogId);
    return bundle.trend;
  }

  /// Uma única leitura de `weight_records` → atual + tendência.
  Future<
    ({
      HealthSummarySectionData<HealthSummaryWeightView> current,
      HealthSummarySectionData<HealthSummaryWeightTrendView> trend,
    })
  >
  readBundle(String dogId) async {
    try {
      final documents = await _loadDocuments(dogId);
      final analysis = analyzeWeightCollection(_classify(dogId, documents));

      // Bloqueador global (`malformed`/`unsupported`/`entityId` duplicado):
      // o peso atual é desconhecido e nenhum registro anterior é promovido.
      if (analysis.isInconclusive) {
        return (
          current:
              const HealthSummarySectionData<
                HealthSummaryWeightView
              >.unavailable(message: HealthSummaryUserCopy.weightUnavailable),
          trend:
              const HealthSummarySectionData<
                HealthSummaryWeightTrendView
              >.unavailable(message: HealthSummaryUserCopy.weightUnavailable),
        );
      }

      final current = analysis.current;
      if (current == null) {
        return (
          current:
              const HealthSummarySectionData<
                HealthSummaryWeightView
              >.notRecorded(message: HealthSummaryUserCopy.weightNotRecorded),
          trend:
              const HealthSummarySectionData<
                HealthSummaryWeightTrendView
              >.notRecorded(message: HealthSummaryUserCopy.weightNotRecorded),
        );
      }

      // Tendência derivada EM MEMÓRIA da mesma leitura (WEIGHT-01E-C1.2):
      // `validRecords` vem em ordem canônica DESC, então os `trendLimit` mais
      // recentes são o prefixo; o `reversed` final entrega a série em ordem
      // cronológica ascendente, como o consumer espera.
      //
      // O recorte acontece DEPOIS da análise: a policy já observou a coleção
      // completa, então um bloqueador fora desta janela continua visível.
      final mostRecentValid = analysis.validRecords.length > trendLimit
          ? analysis.validRecords.take(trendLimit)
          : analysis.validRecords;
      final ascending = mostRecentValid
          .toList(growable: false)
          .reversed
          .map(
            (assessment) => HealthSummaryWeightPoint(
              at: assessment.measuredAt,
              weightKg: assessment.weightKg,
            ),
          )
          .toList(growable: false);

      return (
        current: HealthSummarySectionData.available(
          HealthSummaryWeightView(
            weightKg: current.weightKg,
            measuredAt: current.measuredAt,
          ),
        ),
        // Meta/BCS não inventados — exigem fonte estruturada própria.
        trend: HealthSummarySectionData.available(
          HealthSummaryWeightTrendView(points: ascending),
        ),
      );
    } on FirebaseException catch (e) {
      debugPrint(
        '[HealthSummaryWeightReader] unavailable [${e.code}]: ${e.message}',
      );
      final msg = e.code == 'unavailable'
          ? HealthSummaryUserCopy.networkUnavailable
          : HealthSummaryUserCopy.weightUnavailable;
      return (
        current: HealthSummarySectionData<HealthSummaryWeightView>.unavailable(
          message: msg,
        ),
        trend:
            HealthSummarySectionData<HealthSummaryWeightTrendView>.unavailable(
              message: msg,
            ),
      );
    } catch (e) {
      debugPrint('[HealthSummaryWeightReader] unavailable: $e');
      return (
        current:
            const HealthSummarySectionData<HealthSummaryWeightView>.unavailable(
              message: HealthSummaryUserCopy.weightUnavailable,
            ),
        trend:
            const HealthSummarySectionData<
              HealthSummaryWeightTrendView
            >.unavailable(message: HealthSummaryUserCopy.weightUnavailable),
      );
    }
  }

  /// Classifica os documentos pelo adapter central, preservando `entityId`.
  ///
  /// A classificação é a única autoridade sobre estado documental; esta camada
  /// não reclassifica, não descarta e não decide nada por posição.
  static List<WeightCandidate> _classify(
    String dogId,
    List<HealthSummaryWeightDocument> documents,
  ) {
    final candidates = <WeightCandidate>[];
    for (final document in documents) {
      final result = WeightAssessmentReadAdapter.read(
        documentId: document.entityId,
        dogId: dogId,
        data: document.data,
      );
      candidates.add(
        WeightCandidate(
          entityId: document.entityId,
          kind: switch (result.kind) {
            WeightReadKind.valid => WeightCandidateKind.valid,
            WeightReadKind.invalidated => WeightCandidateKind.invalidated,
            WeightReadKind.malformed => WeightCandidateKind.malformed,
            WeightReadKind.unsupported => WeightCandidateKind.unsupported,
          },
          assessment: result.assessment,
        ),
      );
    }
    return candidates;
  }

  /// Carrega a coleção COMPLETA do cão em uma única leitura (WEIGHT-01E-C1.2).
  ///
  /// Sem `limit` e sem `orderBy`: a policy exige visibilidade global para
  /// detectar `malformed`/`unsupported`/`entityId` duplicado em QUALQUER
  /// posição, e um `limit` aqui esconderia bloqueadores fora da janela
  /// (finding do WEIGHT-01E-C1.1). A ordenação é responsabilidade de
  /// [compareWeightRecency]; [trendLimit] é aplicado somente em memória, após
  /// a análise canônica.
  ///
  /// Consequência conhecida: custo de leitura O(histórico do cão) por chamada.
  /// Reduzir isso exige um read model canônico, não reintroduzir `limit`.
  static Future<List<HealthSummaryWeightDocument>> _loadFromFirestore(
    FirebaseFirestore firestore,
    String dogId,
  ) async {
    final snap = await firestore
        .collection('dogs')
        .doc(dogId)
        .collection('weight_records')
        .get();

    return snap.docs
        .map(
          (doc) =>
              HealthSummaryWeightDocument(entityId: doc.id, data: doc.data()),
        )
        .toList(growable: false);
  }
}
