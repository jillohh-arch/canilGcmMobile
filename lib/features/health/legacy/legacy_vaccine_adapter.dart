import '../domain/health_v1_models.dart';

import 'legacy_health_adapters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LegacyVaccineAdapter — leitura defensiva de `vacinas` (raiz).
// Fonte: `lib/features/dogs/data/dog_profile_service.dart` → VaccineRecord.
// Campos reais: id, caoId, nome, dataAplicacao, dataVencimento, status.
//
// Política:
// - Somente campos comprovados;
// - Sem fabricante/lote/createdBy/recorded_by (não existem no schema);
// - Sem normalização de `status` (string livre; catálogo de valores não
//   comprovado no código de escrita legado);
// - Sem autoria → nunca VaccinationRecord canônico; partial via
//   LegacyHealthRecordView;
// - Códigos de issue reutilizam o padrão existente (missing, no_recorded_by).
// ─────────────────────────────────────────────────────────────────────────────

final class LegacyVaccineAdapter {
  const LegacyVaccineAdapter();

  LegacyParseResult<Object> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final issues = <LegacyParseIssue>[];
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }

    final name = _nonEmptyString(data['nome']);
    if (name == null) {
      issues.add(_error('missing', 'vaccine_name', 'Nome ausente'));
    }

    final appliedAt = LegacyDateParser.parse(data['dataAplicacao']);
    if (!appliedAt.hasValue) {
      final code = appliedAt.issues.isNotEmpty
          ? appliedAt.issues.first.code
          : 'missing';
      issues.add(
        _error(code, 'applied_at', 'Data de aplicação inválida ou ausente'),
      );
    }

    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);

    // Payload bruto preservado (inclui status, dataVencimento, campos extras
    // desconhecidos). dataAplicacao normalizada para DateTime parseado.
    final view = LegacyHealthRecordView(
      sourceId: sourceId,
      dogId: dogId,
      occurredAt: appliedAt.value!,
      typeRaw: 'vaccination',
      description: name ?? '',
      originalPayload: _withCanonicalDate(data, const [
        'dataAplicacao',
      ], appliedAt.value!),
    );

    // Código existente no padrão dos adapters da Fase 1B/1C.
    return LegacyParseResult.partial(view, const [
      LegacyParseIssue(
        code: 'no_recorded_by',
        field: 'recorded_by',
        severity: LegacyIssueSeverity.warning,
        message:
            'recorded_by ausente no schema legado; entidade canônica não produzida',
      ),
    ]);
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

LegacyParseIssue _error(String code, String field, String message) =>
    LegacyParseIssue(
      code: code,
      field: field,
      severity: LegacyIssueSeverity.error,
      message: message,
    );

Map<String, Object?> _withCanonicalDate(
  Map<String, Object?> data,
  Iterable<String> candidateFields,
  DateTime parsed,
) {
  final copy = Map<String, Object?>.from(data);
  for (final field in candidateFields) {
    if (copy.containsKey(field)) {
      copy[field] = parsed;
      break;
    }
  }
  return copy;
}
