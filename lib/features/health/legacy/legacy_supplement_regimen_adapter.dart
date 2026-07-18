import '../domain/legacy_nutrition_views.dart';
import 'legacy_health_adapters.dart';

// ─────────────────────────────────────────────────────────────────────────────
// nutrition_supplements (legado) → LegacySupplementRegimenView
// NUNCA → SupplementLog (D13–D16). ZERO administração inventada.
// ─────────────────────────────────────────────────────────────────────────────

final class LegacySupplementRegimenAdapter {
  const LegacySupplementRegimenAdapter();

  LegacyParseResult<LegacySupplementRegimenView> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
    String legacySource = 'nutrition_supplements',
  }) {
    final issues = <LegacyParseIssue>[];
    if (sourceId.trim().isEmpty) {
      issues.add(
        const LegacyParseIssue(
          code: 'missing',
          field: 'source_id',
          severity: LegacyIssueSeverity.error,
          message: 'Identificador ausente',
        ),
      );
    }
    if (dogId.trim().isEmpty) {
      issues.add(
        const LegacyParseIssue(
          code: 'missing',
          field: 'dog_id',
          severity: LegacyIssueSeverity.error,
          message: 'K9 ausente',
        ),
      );
    }

    final name = _nonEmpty(data, const [
      'name',
      'supplement_name',
      'title',
    ]);
    if (name == null) {
      issues.add(
        const LegacyParseIssue(
          code: 'missing',
          field: 'name',
          severity: LegacyIssueSeverity.error,
          message: 'Nome do suplemento ausente',
        ),
      );
    }

    // Dose permanece textual — não forçar numérico canônico.
    final doseText = _nonEmpty(data, const [
          'dose',
          'dose_text',
          'dosage',
        ]) ??
        '';

    final startedAt = LegacyDateParser.parse(
      data['started_at'] ??
          data['start_date'] ??
          data['created_at'] ??
          data['valid_from'],
    );
    final endedAt = LegacyDateParser.parse(
      data['ended_at'] ?? data['end_date'] ?? data['valid_until'],
    );

    if (endedAt.state == LegacyParseState.failure) {
      issues.add(
        LegacyParseIssue(
          code: endedAt.issues.first.code,
          field: 'ended_at',
          severity: LegacyIssueSeverity.error,
          message: 'ended_at inválido',
        ),
      );
    }

    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);

    final warnings = <LegacyParseIssue>[
      const LegacyParseIssue(
        code: 'not_administration_log',
        field: 'type',
        severity: LegacyIssueSeverity.warning,
        message:
            'nutrition_supplements é regime/estado em uso — não SupplementLog',
      ),
    ];

    final view = LegacySupplementRegimenView(
      id: sourceId,
      dogId: dogId,
      name: name!,
      doseText: doseText,
      unitText: _nonEmpty(data, const ['unit', 'dose_unit']),
      frequencyText: _nonEmpty(data, const ['frequency', 'freq']),
      startedAt: startedAt.hasValue ? startedAt.value : null,
      endedAt: endedAt.hasValue ? endedAt.value : null,
      status: _nonEmpty(data, const ['status']),
      notes: _nonEmpty(data, const ['notes', 'observations', 'instructions']),
      legacySource: legacySource,
      legacyId: sourceId,
    );

    assert(!view.isAdministration);
    return LegacyParseResult.partial(view, warnings);
  }
}

String? _nonEmpty(Map data, List<String> keys) {
  for (final key in keys) {
    final v = data[key]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}
