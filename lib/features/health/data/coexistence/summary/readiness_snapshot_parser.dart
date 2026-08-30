import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/readiness_snapshot.dart';

/// Motivo pelo qual um snapshot não pôde ser aceito como veredito clínico.
///
/// Preservado para diagnóstico: a UI pode dobrar tudo em "indisponível", mas o
/// teste distingue a causa. Falha técnica nunca vira estado clínico.
enum ReadinessParseFailure {
  /// Documento ausente.
  missing,

  /// `schema_version` não suportado por esta versão do Mobile.
  unsupportedSchema,

  /// `projection_status` desconhecido — contrato divergente.
  unknownProjectionStatus,

  /// `readiness_status` fora dos cinco estados oficiais.
  unknownClinicalStatus,

  /// Campo clínico obrigatório ausente ou malformado.
  malformedClinicalField,

  /// Restrição, alerta, contagem ou completude com forma inválida.
  malformedStructure,
}

/// Resultado da interpretação de `health_summary/current`.
sealed class ReadinessParseResult {
  const ReadinessParseResult();
}

/// Snapshot válido — pode ser `ready` ou `unavailable` técnico.
final class ReadinessParseSuccess extends ReadinessParseResult {
  const ReadinessParseSuccess(this.snapshot);
  final ReadinessSnapshot snapshot;
}

/// Snapshot inutilizável. Sempre tratado como indisponibilidade técnica.
final class ReadinessParseIncompatible extends ReadinessParseResult {
  const ReadinessParseIncompatible(this.failure, {this.detail});
  final ReadinessParseFailure failure;
  final String? detail;
}

/// Parser estrito de `dogs/{dogId}/health_summary/current`.
///
/// READINESS-V1 Gate 6.
///
/// Princípios não negociáveis:
/// - enum clínico desconhecido → incompatível, **nunca** `operational`;
/// - `projection_status == unavailable` → indisponibilidade técnica, mesmo com
///   campos clínicos preservados (que viram `lastKnownGood`, não estado atual);
/// - campo clínico crítico malformado sob `ready` → indisponível, nunca veredito
///   parcial;
/// - nada é "reparado" silenciosamente.
abstract final class ReadinessSnapshotParser {
  ReadinessSnapshotParser._();

  /// Maior `schema_version` que este Mobile entende.
  static const supportedSchemaVersion = 1;

  static ReadinessParseResult parse(Map<String, Object?>? data) {
    if (data == null || data.isEmpty) {
      return const ReadinessParseIncompatible(ReadinessParseFailure.missing);
    }

    // ── schema_version ────────────────────────────────────────────────────
    final rawSchema = data['schema_version'];
    if (rawSchema is! int || rawSchema <= 0) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.unsupportedSchema,
        detail: 'schema_version ausente ou inválido',
      );
    }
    if (rawSchema > supportedSchemaVersion) {
      return ReadinessParseIncompatible(
        ReadinessParseFailure.unsupportedSchema,
        detail: 'schema_version $rawSchema acima do suportado',
      );
    }

    // ── projection_status (plano técnico) ─────────────────────────────────
    final projection = ReadinessProjectionStatus.fromWire(
      _stringOrNull(data['projection_status']),
    );
    if (projection == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.unknownProjectionStatus,
      );
    }

    final attemptedAt = HealthSummaryDateParse.tryParse(
      data['projection_attempted_at'],
    );
    if (attemptedAt == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'projection_attempted_at ausente ou inválido',
      );
    }

    // ── unavailable: metadata técnica; clínico preservado é last-known-good ─
    if (projection == ReadinessProjectionStatus.unavailable) {
      final blockers = _stringList(data['technical_blockers']);
      // Campos clínicos podem ter sido preservados pelo servidor. Só são
      // aproveitados se formarem um veredito COMPLETO; caso contrário são
      // descartados — nunca exibidos parcialmente.
      final preserved = _tryParseVerdict(data);
      return ReadinessParseSuccess(
        ReadinessSnapshot.unavailable(
          projectionAttemptedAt: attemptedAt,
          technicalBlockers: blockers ?? const [],
          schemaVersion: rawSchema,
          lastKnownGood: preserved is ReadinessParseSuccess
              ? (preserved.snapshot.verdict)
              : null,
        ),
      );
    }

    // ── ready: exige veredito clínico completo e válido ───────────────────
    final verdictResult = _tryParseVerdict(data);
    if (verdictResult is ReadinessParseIncompatible) {
      return verdictResult;
    }
    final verdict = (verdictResult as ReadinessParseSuccess).snapshot.verdict!;

    return ReadinessParseSuccess(
      ReadinessSnapshot.ready(
        verdict: verdict,
        projectionAttemptedAt: attemptedAt,
        schemaVersion: rawSchema,
      ),
    );
  }

  /// Tenta montar um veredito clínico completo.
  ///
  /// Envolve o veredito num `ReadinessSnapshot.ready` sintético apenas para
  /// reaproveitar o tipo de resultado; o chamador extrai `verdict`.
  static ReadinessParseResult _tryParseVerdict(Map<String, Object?> data) {
    final status = _readinessStatusFromWire(
      _stringOrNull(data['readiness_status']),
    );
    if (status == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.unknownClinicalStatus,
      );
    }

    final label = _stringOrNull(data['readiness_label']);
    if (label == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'readiness_label ausente',
      );
    }

    final reason = _stringOrNull(data['readiness_reason']);
    if (reason == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'readiness_reason ausente',
      );
    }

    final reasonCode = _stringOrNull(data['readiness_reason_code']);
    if (reasonCode == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'readiness_reason_code ausente',
      );
    }

    final updatedAt = HealthSummaryDateParse.tryParse(
      data['readiness_updated_at'],
    );
    if (updatedAt == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'readiness_updated_at ausente ou inválido',
      );
    }

    final completeness = _parseCompleteness(data['data_completeness']);
    if (completeness == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedStructure,
        detail: 'data_completeness inválido',
      );
    }

    final restrictions = _parseRestrictions(data['active_restrictions']);
    if (restrictions == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedStructure,
        detail: 'active_restrictions inválido',
      );
    }

    final count = _parseRestrictionCount(data['restriction_count']);
    if (count == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedStructure,
        detail: 'restriction_count inválido',
      );
    }

    final alerts = _parseAlerts(data['open_alerts']);
    if (alerts == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedStructure,
        detail: 'open_alerts inválido',
      );
    }

    // last_evaluated_at é opcional e legitimamente null (nunca avaliado).
    // Só é rejeitado se presente e não parseável.
    final rawLastEvaluated = data['last_evaluated_at'];
    final lastEvaluatedAt = HealthSummaryDateParse.tryParse(rawLastEvaluated);
    if (rawLastEvaluated != null && lastEvaluatedAt == null) {
      return const ReadinessParseIncompatible(
        ReadinessParseFailure.malformedClinicalField,
        detail: 'last_evaluated_at presente mas inválido',
      );
    }

    return ReadinessParseSuccess(
      ReadinessSnapshot.ready(
        verdict: ReadinessClinicalVerdict(
          status: status,
          label: label,
          reason: reason,
          reasonCode: reasonCode,
          updatedAt: updatedAt,
          completeness: completeness,
          activeRestrictions: restrictions,
          restrictionCount: count,
          openAlerts: alerts,
          lastEvaluatedAt: lastEvaluatedAt,
        ),
        projectionAttemptedAt: updatedAt,
        schemaVersion: supportedSchemaVersion,
      ),
    );
  }

  /// Converte o wire name do servidor no enum clínico canônico.
  ///
  /// Valor desconhecido → null → incompatível. Jamais um default otimista.
  static ReadinessStatus? _readinessStatusFromWire(String? wire) =>
      switch (wire) {
        'operational' => ReadinessStatus.operational,
        'operational_attention' => ReadinessStatus.operationalAttention,
        'fit_with_restrictions' => ReadinessStatus.fitWithRestrictions,
        'temporarily_unfit' => ReadinessStatus.temporarilyUnfit,
        'not_evaluated' => ReadinessStatus.notEvaluated,
        _ => null,
      };

  static ReadinessCompleteness? _parseCompleteness(Object? raw) {
    if (raw is! Map) return null;
    final weight = raw['has_recent_weight'];
    final vaccination = raw['has_vaccination_current'];
    final consultation = raw['has_recent_consultation'];
    final nutrition = raw['has_active_nutrition'];
    if (weight is! bool ||
        vaccination is! bool ||
        consultation is! bool ||
        nutrition is! bool) {
      return null;
    }
    return ReadinessCompleteness(
      hasRecentWeight: weight,
      hasVaccinationCurrent: vaccination,
      hasRecentConsultation: consultation,
      hasActiveNutrition: nutrition,
    );
  }

  static List<ReadinessRestriction>? _parseRestrictions(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) return null;

    final out = <ReadinessRestriction>[];
    for (final entry in raw) {
      if (entry is! Map) return null;

      final id = _stringOrNull(entry['id']);
      final level = ReadinessRestrictionLevel.fromWire(
        _stringOrNull(entry['level']),
      );
      final category = _stringOrNull(entry['category']);
      final description = _stringOrNull(entry['description']);
      final since = HealthSummaryDateParse.tryParse(entry['since']);
      final activities = _stringList(entry['activities_restricted']);
      final isOverdue = entry['is_overdue'];

      // Restrição é a evidência mais consequente do modelo: qualquer campo
      // inválido invalida o snapshot inteiro em vez de omitir a restrição.
      if (id == null ||
          level == null ||
          category == null ||
          description == null ||
          since == null ||
          activities == null ||
          isOverdue is! bool) {
        return null;
      }

      final rawExpectedEnd = entry['expected_end'];
      final expectedEnd = HealthSummaryDateParse.tryParse(rawExpectedEnd);
      if (rawExpectedEnd != null && expectedEnd == null) return null;

      out.add(
        ReadinessRestriction(
          id: id,
          level: level,
          category: category,
          description: description,
          activitiesRestricted: activities,
          since: since,
          expectedEnd: expectedEnd,
          isOverdue: isOverdue,
        ),
      );
    }
    return out;
  }

  static ReadinessRestrictionCount? _parseRestrictionCount(Object? raw) {
    if (raw is! Map) return null;
    final absolute = raw['absolute'];
    final partial = raw['partial'];
    final attention = raw['attention'];
    if (absolute is! int ||
        partial is! int ||
        attention is! int ||
        absolute < 0 ||
        partial < 0 ||
        attention < 0) {
      return null;
    }
    return ReadinessRestrictionCount(
      absolute: absolute,
      partial: partial,
      attention: attention,
    );
  }

  static List<ReadinessAlert>? _parseAlerts(Object? raw) {
    if (raw == null) return const [];
    if (raw is! List) return null;

    final out = <ReadinessAlert>[];
    for (final entry in raw) {
      if (entry is! Map) return null;
      final code = _stringOrNull(entry['code']);
      final severity = _stringOrNull(entry['severity']);
      final message = _stringOrNull(entry['message']);
      if (code == null || severity == null || message == null) return null;
      out.add(
        ReadinessAlert(code: code, severity: severity, message: message),
      );
    }
    return out;
  }

  static String? _stringOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Lista de strings não vazias. `null`/ausente → lista vazia.
  /// Forma inválida → null (rejeita o snapshot).
  static List<String>? _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List) return null;
    final out = <String>[];
    for (final entry in value) {
      final parsed = _stringOrNull(entry);
      if (parsed == null) return null;
      out.add(parsed);
    }
    return out;
  }
}
