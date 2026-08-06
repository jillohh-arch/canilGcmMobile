import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment.dart';
import 'package:canil_gcm/features/health/domain/weight_assessment_document_parser.dart';

/// Classificação de leitura de um documento de `weight_records`.
///
/// [valid]/[invalidated] só ocorrem quando o parser central retorna sucesso;
/// [malformed]/[unsupported] são bloqueadores de leitura (documento ilegível
/// ou schema futuro) e nunca devem promover silenciosamente um registro
/// anterior a peso atual.
enum WeightReadKind { valid, invalidated, malformed, unsupported }

/// Resultado read-only da adoção do parser central em superfícies Mobile.
///
/// Não consulta, não escreve, não escolhe globalmente o peso atual e nunca
/// expõe pseudo-identificadores (RA / `legacyActorReference`), uid, nome ou
/// e-mail. A autoria só chega às façades quando factual (`recorder`).
final class WeightReadResult {
  const WeightReadResult._({
    required this.kind,
    required this.assessment,
    required this.record,
    required this.diagnosticCodes,
  });

  final WeightReadKind kind;

  /// Aggregate canônico quando o documento é parseável (valid/invalidated).
  final WeightAssessment? assessment;

  /// Façade de apresentação. Presente sempre que o registro é `valid`,
  /// inclusive em shapes legados reconhecidos sem autoria canônica — nesse
  /// caso a autoria da façade fica `null` (ausente, nunca inventada).
  final WeightRecord? record;

  /// Somente códigos técnicos seguros — sem uid, nome, RA, e-mail ou map bruto.
  final List<WeightDocumentDiagnosticCode> diagnosticCodes;

  bool get isValid => kind == WeightReadKind.valid;
  bool get isInvalidated => kind == WeightReadKind.invalidated;

  /// Documento não legível (malformed) ou schema não suportado (unsupported).
  bool get isBlocking =>
      kind == WeightReadKind.malformed || kind == WeightReadKind.unsupported;

  /// Verdadeiro quando há façade renderizável em superfícies WeightRecord.
  bool get hasFacadeRecord => record != null;
}

/// Adapter central de leitura de peso.
///
/// Invoca [WeightAssessmentDocumentParser] e traduz o resultado para as
/// façades de apresentação existentes, aplicando a política de status de
/// forma consistente entre readers. Aceita apenas o contexto de origem
/// canônico `weight_records`.
abstract final class WeightAssessmentReadAdapter {
  WeightAssessmentReadAdapter._();

  /// Contexto de origem canônico único aceito pelo adapter.
  static const String canonicalSourceCollection = 'weight_records';

  static WeightReadResult read({
    required String documentId,
    required String dogId,
    required Map<String, dynamic> data,
    String sourceCollection = canonicalSourceCollection,
  }) {
    final parsed = WeightAssessmentDocumentParser.parse(
      entityId: documentId,
      dogId: dogId,
      data: data,
      sourceCollection: sourceCollection,
    );
    final codes = parsed.diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    switch (parsed.kind) {
      case WeightAssessmentParseResultKind.malformed:
        return WeightReadResult._(
          kind: WeightReadKind.malformed,
          assessment: null,
          record: null,
          diagnosticCodes: codes,
        );
      case WeightAssessmentParseResultKind.unsupported:
        return WeightReadResult._(
          kind: WeightReadKind.unsupported,
          assessment: null,
          record: null,
          diagnosticCodes: codes,
        );
      case WeightAssessmentParseResultKind.success:
        final assessment = parsed.assessment!;
        final status = assessment.status;
        final isKnownValid =
            status.isKnown && status.value == WeightAssessmentStatus.valid;
        if (isKnownValid) {
          return WeightReadResult._(
            kind: WeightReadKind.valid,
            assessment: assessment,
            record: _toRecord(assessment),
            diagnosticCodes: codes,
          );
        }
        // `invalidated` conhecido ou status não classificável (ex.: enum futuro):
        // excluído por padrão das superfícies ordinárias, sem bloquear leitura
        // nem promover registro anterior.
        return WeightReadResult._(
          kind: WeightReadKind.invalidated,
          assessment: assessment,
          record: null,
          diagnosticCodes: codes,
        );
    }
  }

  /// Mapeia um aggregate válido para a façade [WeightRecord].
  ///
  /// Quando não há autoria factual (`recorder == null`, shape legado
  /// reconhecido) a pesagem permanece válida e renderizável, mas `recordedBy`
  /// fica `null`: não inventa autoria, não usa o getter deprecated
  /// `recordedBy` e não expõe `legacyActorReference` / RA.
  static WeightRecord _toRecord(WeightAssessment assessment) {
    final recorder = assessment.recorder;
    return WeightRecord(
      id: assessment.entityId,
      weightKg: assessment.weightKg,
      measuredAt: assessment.measuredAt,
      recordedBy: recorder == null
          ? null
          : WeightRecordedBy(
              uid: recorder.uid,
              name: recorder.name,
              internalRole: recorder.internalRole,
            ),
      schemaVersion: assessment.schemaVersion,
      context: assessment.context ?? '',
      notes: assessment.notes,
    );
  }
}
