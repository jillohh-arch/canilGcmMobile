import 'package:flutter/foundation.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_date_parse.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_soft_delete.dart';
import 'package:canil_gcm/features/health/data/coexistence/timeline/timeline_mapping_result.dart';
import 'package:canil_gcm/features/health/data/weight/weight_assessment_read_adapter.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_source.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';

/// Mappers defensivos legado → [TimelineMappingResult].
///
/// ## Ordem conceitual (segura)
/// 1. soft-delete → [TimelineIgnored]
/// 2. filtro de tipo (quando o tipo é confiável **sem** data) → ignored
/// 3. parse de data obrigatória → missing/invalid → [TimelineInvalid]
/// 4. demais campos estruturais → invalid se obrigatório
/// 5. montagem da entry + filtros que dependem de data/campos
///    (period, caseId, professional) → ignored se fora
///
/// ## Política
/// - soft-deleted / irrelevante por filtro → ignorado;
/// - ativo relevante com `occurredAt` impossível → **inconclusivo**;
/// - tipo desconhecido com data válida → mapped (unknown);
/// - sem inventar data (sem `now()`, epoch ou created_at como occurredAt).
abstract final class HealthTimelineMappers {
  HealthTimelineMappers._();

  static const sourceHealthEvents = 'health_events';
  static const sourceWeightRecords = 'weight_records';
  static const sourceFeedingEvents = 'feeding_events';
  static const sourceFeedings = 'feedings';
  static const sourceVacinas = 'vacinas';
  static const sourceMealLogs = 'meal_logs';
  static const sourceSupplementLogs = 'supplement_logs';

  static String globalId(String sourceKey, String docId) => '$sourceKey:$docId';

  static String _formatGramValue(num grams) {
    return grams == grams.roundToDouble()
        ? '${grams.toInt()} g'
        : '${grams.toStringAsFixed(1).replaceAll('.', ',')} g';
  }

  /// Mensagem pública para leitura inconclusiva (sem PHI / reason bruto).
  static const inconclusivePublicMessage =
      'Histórico clínico incompleto: há registros que não puderam ser '
      'interpretados com segurança.';

  /// Propaga unmappable estrutural como falha de source (sanitizada).
  static Never throwInconclusive({
    required String sourceKey,
    required TimelineMappingInvalidReason reason,
  }) {
    debugPrint(
      '[timeline] mapping inconclusive sourceKey=$sourceKey '
      'reason=${reason.name}',
    );
    throw const HealthTimelineSourceException(inconclusivePublicMessage);
  }

  /// Aplica filtros estruturados da query sobre uma entrada já mapeada.
  static bool matchesFilters(
    HealthTimelineEntryView entry,
    HealthTimelineQuery query,
  ) {
    if (query.types.isNotEmpty) {
      final known = entry.type.known;
      if (known == null || !query.types.contains(known)) return false;
    }
    final period = query.period;
    if (period.start != null && entry.occurredAt.isBefore(period.start!)) {
      return false;
    }
    if (period.end != null && entry.occurredAt.isAfter(period.end!)) {
      return false;
    }
    final caseId = query.caseId;
    if (caseId != null) {
      if (entry.caseId != caseId) return false;
    }
    final prof = query.professional;
    if (prof != null) {
      final p = entry.professional;
      if (p == null) return false;
      if (prof.name != null &&
          p.name.trim().toLowerCase() != prof.name!.trim().toLowerCase()) {
        return false;
      }
      // registration* não existe em ProfessionalIdentitySummary — filtro por
      // registration sem name não casa (não inventa match).
      if (prof.name == null &&
          (prof.registrationType != null || prof.registrationNumber != null)) {
        return false;
      }
    }
    return true;
  }

  /// true se o tipo conhecido (ou ausência de tipo no filtro) prova
  /// irrelevância **antes** de exigir `occurredAt`.
  static bool _typeFilterExcludes(
    HealthTimelineTypeView typeView,
    HealthTimelineQuery filters,
  ) {
    if (filters.types.isEmpty) return false;
    final known = typeView.known;
    // Unknown não casa com filtro de tipos conhecidos → irrelevante.
    if (known == null) return true;
    return !filters.types.contains(known);
  }

  static TimelineMappingInvalidReason _dateReason(Object? raw) {
    if (raw == null) return TimelineMappingInvalidReason.missingRequiredDate;
    return TimelineMappingInvalidReason.invalidRequiredDate;
  }

  /// Espelho dual-write de pesagem mobile (3E-D3).
  ///
  /// Registros legados de pesagem em `health_events` são apenas reconhecidos
  /// para evitar duplicidade durante a coexistência. A escrita Mobile canônica
  /// ocorre exclusivamente pelo callable de `weight_records`.
  ///
  /// IDs distintos (sem `source_id` / docId compartilhado) — identidade
  /// lógica vem do **contrato de escrita dual comprovado**, não de
  /// heurística de timestamp.
  ///
  /// Canônico na Timeline: [mapWeightRecord] / `weight_records` (ADR-006).
  /// Este espelho é ignorado no read-side para evitar duas entradas do
  /// mesmo ato operacional.
  ///
  /// **Não** suprime:
  /// - health_events sem `weight` numérico;
  /// - health_events com outros subtype/type (consulta, vacina, etc.);
  /// - weight_records (permanecem).
  static bool isProvenWeightDualWriteMirror(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['logType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final subtype = (data['subtype'] ?? '').toString().trim().toLowerCase();
    final weight = data['weight'];
    final hasWeight = weight is num && weight.isFinite && weight > 0;
    if (!hasWeight) return false;
    // Payload canônico do dual-write em WeightHistoryScreen.
    return type == 'other' && subtype == 'pesagem';
  }

  static TimelineMappingResult mapHealthEvent({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  }) {
    // 1. Soft-delete — ignorável mesmo com data inválida.
    if (HealthSummarySoftDelete.isSoftDeleted(data)) {
      return const TimelineIgnored('soft_deleted');
    }

    // 1b. Espelho dual-write de pesagem (3E-D3) — antes de type/data.
    // Independente de página: não precisa do weight_record no mesmo batch.
    if (isProvenWeightDualWriteMirror(data)) {
      return const TimelineIgnored('weight_dual_write_mirror');
    }

    final typeRaw = (data['type'] ?? data['logType'] ?? '').toString().trim();
    if (typeRaw.isEmpty) {
      return const TimelineInvalid(
        TimelineMappingInvalidReason.invalidRequiredStructure,
      );
    }

    final typeView = _mapHealthEventType(typeRaw);

    // 2. Filtro de tipo confiável antes da data.
    if (_typeFilterExcludes(typeView, filters)) {
      return const TimelineIgnored('type_filter');
    }

    // 3. Data estrutural obrigatória para posicionar.
    final dateRaw = data['date'];
    final occurredAt = HealthSummaryDateParse.tryParse(dateRaw);
    if (occurredAt == null) {
      return TimelineInvalid(_dateReason(dateRaw));
    }

    final subtype = data['subtype']?.toString().trim();
    final title = _healthEventTitle(typeView, typeRaw, subtype);
    final obs = data['healthObservations']?.toString().trim();

    final statusRaw = data['status']?.toString().toLowerCase().trim();
    final status = statusRaw == 'cancelled' || statusRaw == 'canceled'
        ? HealthTimelineEntryStatus.cancelled
        : HealthTimelineEntryStatus.finalised;

    ProfessionalIdentitySummary? professional;
    final vetName = data['vetName']?.toString().trim();
    if (vetName != null && vetName.isNotEmpty) {
      final clinic = data['professionalClinic']?.toString().trim();
      professional = ProfessionalIdentitySummary(
        name: vetName,
        specialty: (clinic == null || clinic.isEmpty) ? null : clinic,
      );
    }

    final hasAttachment =
        (data['attachmentUrl']?.toString().trim().isNotEmpty ?? false) ||
        (data['mediaAttachments'] is List &&
            (data['mediaAttachments'] as List).isNotEmpty);

    final id = globalId(sourceHealthEvents, docId);
    final entry = HealthTimelineEntryView(
      id: id,
      dogId: dogId,
      type: typeView,
      occurredAt: occurredAt,
      recordedAt:
          HealthSummaryDateParse.tryParse(data['created_at']) ??
          HealthSummaryDateParse.tryParse(data['createdAt']) ??
          occurredAt,
      title: title,
      subtitle: (obs == null || obs.isEmpty) ? null : obs,
      status: status,
      caseId: data['caseId']?.toString() ?? data['case_id']?.toString(),
      professional: professional,
      hasAttachments: hasAttachment,
      attachmentCount: hasAttachment
          ? (data['mediaAttachments'] is List
                ? (data['mediaAttachments'] as List).length
                : 1)
          : null,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceHealthEvents,
        sourceId: docId,
        caseId: data['caseId']?.toString() ?? data['case_id']?.toString(),
      ),
      traceability: HealthTimelineTraceability(
        sourceCollection: 'dogs/{dogId}/health_events',
        sourceId: docId,
      ),
    );

    // 5. Filtros que dependem de data / campos (period, case, professional).
    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  /// Mapeia `weight_records` via parser central (ADR-008 §11.4).
  ///
  /// - `valid` → evento (a timeline não carrega autoria; shapes legados sem
  ///   `recorder` também viram evento);
  /// - `invalidated` → [TimelineIgnored] (excluído da timeline ordinária, sem
  ///   bloquear a completude);
  /// - `malformed`/`unsupported` → [TimelineInvalid] (documento ativo
  ///   estruturalmente inutilizável → leitura inconclusiva, nunca evento);
  /// - metadata interna (`legacyActorReference`) nunca é usada como texto;
  /// - `created_at` permanece apenas como fallback derivado de `recordedAt`.
  static TimelineMappingResult mapWeightRecord({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  }) {
    if (data.containsKey('deleted_at') &&
        HealthSummarySoftDelete.isSoftDeleted(data)) {
      return const TimelineIgnored('soft_deleted');
    }

    // Fonte é sempre weight — filtro de tipo antes do parse.
    if (filters.types.isNotEmpty &&
        !filters.types.contains(HealthTimelineType.weight)) {
      return const TimelineIgnored('type_filter');
    }

    final result = WeightAssessmentReadAdapter.read(
      documentId: docId,
      dogId: dogId,
      data: data,
    );
    switch (result.kind) {
      case WeightReadKind.invalidated:
        return const TimelineIgnored('invalidated');
      case WeightReadKind.malformed:
      case WeightReadKind.unsupported:
        return const TimelineInvalid(
          TimelineMappingInvalidReason.invalidRequiredStructure,
        );
      case WeightReadKind.valid:
        break;
    }

    final assessment = result.assessment!;
    final occurredAt = assessment.measuredAt;
    final kg = assessment.weightKg;
    final label = kg == kg.roundToDouble()
        ? '${kg.toInt()} kg'
        : '${kg.toStringAsFixed(1).replaceAll('.', ',')} kg';

    final entry = HealthTimelineEntryView(
      id: globalId(sourceWeightRecords, docId),
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.weight),
      occurredAt: occurredAt,
      recordedAt:
          HealthSummaryDateParse.tryParse(data['created_at']) ?? occurredAt,
      title: 'Pesagem',
      subtitle: label,
      status: HealthTimelineEntryStatus.finalised,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceWeightRecords,
        sourceId: docId,
      ),
      traceability: HealthTimelineTraceability(
        sourceCollection: 'dogs/{dogId}/weight_records',
        sourceId: docId,
      ),
    );
    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  static TimelineMappingResult mapFeeding({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
    required String sourceKey,
  }) {
    if (HealthSummarySoftDelete.isSoftDeleted(data)) {
      return const TimelineIgnored('soft_deleted');
    }

    if (filters.types.isNotEmpty &&
        !filters.types.contains(HealthTimelineType.meal)) {
      return const TimelineIgnored('type_filter');
    }

    final dateRaw = data['fed_at'];
    final occurredAt = HealthSummaryDateParse.tryParse(dateRaw);
    if (occurredAt == null) {
      return TimelineInvalid(_dateReason(dateRaw));
    }

    final grams = data['amount_grams'];
    String? subtitle;
    if (grams is num && grams.isFinite) {
      subtitle = grams == grams.roundToDouble()
          ? '${grams.toInt()} g'
          : '${grams.toStringAsFixed(1).replaceAll('.', ',')} g';
    }

    final entry = HealthTimelineEntryView(
      id: 'feeding:$docId',
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.meal),
      occurredAt: occurredAt,
      recordedAt:
          HealthSummaryDateParse.tryParse(data['created_at']) ?? occurredAt,
      title: 'Alimentação registrada',
      subtitle: subtitle,
      status: HealthTimelineEntryStatus.finalised,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceKey,
        sourceId: docId,
      ),
      traceability: HealthTimelineTraceability(
        sourceCollection: 'dogs/{dogId}/$sourceKey',
        sourceId: docId,
        legacySource: sourceKey,
        legacyId: docId,
      ),
    );
    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  static TimelineMappingResult mapCanonicalMealLog({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  }) {
    if (HealthSummarySoftDelete.isSoftDeleted(data)) {
      return const TimelineIgnored('soft_deleted');
    }

    if (filters.types.isNotEmpty &&
        !filters.types.contains(HealthTimelineType.meal)) {
      return const TimelineIgnored('type_filter');
    }

    final dateRaw = data['fed_at'];
    final occurredAt = HealthSummaryDateParse.tryParse(dateRaw);
    if (occurredAt == null) {
      return TimelineInvalid(_dateReason(dateRaw));
    }

    final rawConsumed = data['consumed_grams'];
    final rawOffered =
        data['offered_grams'] ??
        data['legacy_amount_grams'] ??
        data['amount_grams'];

    String subtitle;
    if (rawConsumed != null) {
      if (rawConsumed is num && rawConsumed.isFinite) {
        subtitle = '${_formatGramValue(rawConsumed)} consumidos';
      } else {
        return const TimelineInvalid(
          TimelineMappingInvalidReason.invalidRequiredStructure,
        );
      }
    } else if (rawOffered != null) {
      if (rawOffered is num && rawOffered.isFinite) {
        subtitle =
            '${_formatGramValue(rawOffered)} oferecidos · consumo não informado';
      } else {
        return const TimelineInvalid(
          TimelineMappingInvalidReason.invalidRequiredStructure,
        );
      }
    } else {
      subtitle = 'Consumo não informado';
    }

    final title = 'Alimentação registrada';

    ProfessionalIdentitySummary? professional;
    final profRaw = data['professional'];
    if (profRaw is Map) {
      final pName = profRaw['name']?.toString().trim();
      if (pName != null && pName.isNotEmpty) {
        final clinic = profRaw['clinic']?.toString().trim();
        professional = ProfessionalIdentitySummary(
          name: pName,
          specialty: (clinic == null || clinic.isEmpty) ? null : clinic,
        );
      }
    }

    final hasAttachment =
        (data['attachment_refs'] is List &&
        (data['attachment_refs'] as List).isNotEmpty);

    final legacyId = data['legacy_id']?.toString().trim();
    final legacySource = data['legacy_source']?.toString().trim();
    final String entryId;
    if (legacyId != null && legacyId.isNotEmpty) {
      if (legacySource == 'feedings' || legacySource == 'feeding_events') {
        entryId = 'feeding:$legacyId';
      } else if (legacySource == 'vacinas') {
        entryId = 'vacinas:$legacyId';
      } else if (legacySource != null && legacySource.isNotEmpty) {
        entryId = '$legacySource:$legacyId';
      } else {
        entryId = globalId(sourceMealLogs, docId);
      }
    } else {
      entryId = globalId(sourceMealLogs, docId);
    }

    final entry = HealthTimelineEntryView(
      id: entryId,
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.meal),
      occurredAt: occurredAt,
      recordedAt:
          HealthSummaryDateParse.tryParse(data['created_at']) ??
          HealthSummaryDateParse.tryParse(data['createdAt']) ??
          occurredAt,
      title: title,
      subtitle: subtitle,
      status: HealthTimelineEntryStatus.finalised,
      caseId: data['case_id']?.toString() ?? data['caseId']?.toString(),
      professional: professional,
      hasAttachments: hasAttachment,
      attachmentCount: hasAttachment
          ? (data['attachment_refs'] as List).length
          : null,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceMealLogs,
        sourceId: docId,
        caseId: data['case_id']?.toString() ?? data['caseId']?.toString(),
      ),
      traceability: HealthTimelineTraceability(
        sourceCollection: 'dogs/{dogId}/meal_logs',
        sourceId: docId,
        legacySource: legacySource,
        legacyId: legacyId,
      ),
    );

    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  static TimelineMappingResult mapCanonicalSupplementLog({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  }) {
    if (HealthSummarySoftDelete.isSoftDeleted(data)) {
      return const TimelineIgnored('soft_deleted');
    }

    if (filters.types.isNotEmpty &&
        !filters.types.contains(HealthTimelineType.supplement)) {
      return const TimelineIgnored('type_filter');
    }

    final dateRaw = data['administered_at'];
    final occurredAt = HealthSummaryDateParse.tryParse(dateRaw);
    if (occurredAt == null) {
      return TimelineInvalid(_dateReason(dateRaw));
    }

    final name = data['supplement_name']?.toString().trim() ?? 'Suplemento';
    final dose = data['dose'];
    final unit = data['unit']?.toString().trim();

    String? subtitle;
    if (dose != null) {
      final unitStr = unit != null ? ' $unit' : '';
      subtitle = '$dose$unitStr';
    }

    ProfessionalIdentitySummary? professional;
    final profRaw = data['professional'];
    if (profRaw is Map) {
      final pName = profRaw['name']?.toString().trim();
      if (pName != null && pName.isNotEmpty) {
        final clinic = profRaw['clinic']?.toString().trim();
        professional = ProfessionalIdentitySummary(
          name: pName,
          specialty: (clinic == null || clinic.isEmpty) ? null : clinic,
        );
      }
    }

    final hasAttachment =
        (data['attachment_refs'] is List &&
        (data['attachment_refs'] as List).isNotEmpty);

    final legacyId = data['legacy_id']?.toString().trim();
    final legacySource = data['legacy_source']?.toString().trim();
    final String entryId;
    if (legacyId != null && legacyId.isNotEmpty) {
      if (legacySource == 'vacinas') {
        entryId = 'vacinas:$legacyId';
      } else if (legacySource == 'feedings' ||
          legacySource == 'feeding_events') {
        entryId = 'feeding:$legacyId';
      } else if (legacySource != null && legacySource.isNotEmpty) {
        entryId = '$legacySource:$legacyId';
      } else {
        entryId = globalId(sourceSupplementLogs, docId);
      }
    } else {
      entryId = globalId(sourceSupplementLogs, docId);
    }

    final entry = HealthTimelineEntryView(
      id: entryId,
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.supplement),
      occurredAt: occurredAt,
      recordedAt:
          HealthSummaryDateParse.tryParse(data['created_at']) ??
          HealthSummaryDateParse.tryParse(data['createdAt']) ??
          occurredAt,
      title: name,
      subtitle: subtitle,
      status: HealthTimelineEntryStatus.finalised,
      caseId: data['case_id']?.toString() ?? data['caseId']?.toString(),
      professional: professional,
      hasAttachments: hasAttachment,
      attachmentCount: hasAttachment
          ? (data['attachment_refs'] as List).length
          : null,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceSupplementLogs,
        sourceId: docId,
        caseId: data['case_id']?.toString() ?? data['caseId']?.toString(),
      ),
      traceability: HealthTimelineTraceability(
        sourceCollection: 'dogs/{dogId}/supplement_logs',
        sourceId: docId,
        legacySource: legacySource,
        legacyId: legacyId,
      ),
    );

    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  static TimelineMappingResult mapLegacyVacina({
    required String dogId,
    required String docId,
    required Map<String, dynamic> data,
    required HealthTimelineQuery filters,
  }) {
    // Coleção raiz legada: sem soft-delete canônico.
    if (filters.types.isNotEmpty &&
        !filters.types.contains(HealthTimelineType.vaccination)) {
      return const TimelineIgnored('type_filter');
    }

    final dateRaw = data['dataAplicacao'];
    final occurredAt = HealthSummaryDateParse.tryParse(dateRaw);
    if (occurredAt == null) {
      return TimelineInvalid(_dateReason(dateRaw));
    }
    final nome = data['nome']?.toString().trim();

    final entry = HealthTimelineEntryView(
      id: globalId(sourceVacinas, docId),
      dogId: dogId,
      type: HealthTimelineTypeView.known(HealthTimelineType.vaccination),
      occurredAt: occurredAt,
      recordedAt: occurredAt,
      title: (nome == null || nome.isEmpty) ? 'Vacinação' : nome,
      subtitle: null,
      status: HealthTimelineEntryStatus.finalised,
      detailReference: HealthTimelineDetailReference(
        sourceType: sourceVacinas,
        sourceId: docId,
      ),
      traceability: HealthTimelineTraceability(
        legacySource: sourceVacinas,
        legacyId: docId,
      ),
    );
    if (!matchesFilters(entry, filters)) {
      return const TimelineIgnored('query_filter');
    }
    return TimelineMapped(entry);
  }

  static HealthTimelineTypeView _mapHealthEventType(String raw) {
    final t = raw.toLowerCase().trim();
    final known = switch (t) {
      'vaccination' ||
      'vacina' ||
      'vacinação' => HealthTimelineType.vaccination,
      'consultation' || 'consulta' => HealthTimelineType.consultation,
      'exam' || 'exame' => HealthTimelineType.exam,
      'medication' ||
      'medicação' ||
      'medicacao' ||
      'dose' => HealthTimelineType.dose,
      'antiparasitic' => HealthTimelineType.preventive,
      'symptom' ||
      'incident' ||
      'intercorrencia' ||
      'intercorrência' => HealthTimelineType.incident,
      'surgery' => HealthTimelineType.treatment,
      'weight' || 'pesagem' => HealthTimelineType.weight,
      'observation' ||
      'observacao' ||
      'observação' => HealthTimelineType.observation,
      'document' || 'documento' => HealthTimelineType.document,
      'restriction' ||
      'restricao' ||
      'restrição' => HealthTimelineType.restriction,
      'treatment' || 'tratamento' => HealthTimelineType.treatment,
      'discharge' || 'alta' => HealthTimelineType.discharge,
      'meal' ||
      'feeding' ||
      'alimentacao' ||
      'alimentação' => HealthTimelineType.meal,
      'supplement' || 'suplemento' => HealthTimelineType.supplement,
      'preventive' || 'preventivo' => HealthTimelineType.preventive,
      _ => null,
    };
    if (known != null) return HealthTimelineTypeView.known(known);
    return HealthTimelineTypeView.parse(raw);
  }

  static String _healthEventTitle(
    HealthTimelineTypeView typeView,
    String typeRaw,
    String? subtype,
  ) {
    final base = switch (typeView.known) {
      HealthTimelineType.vaccination => 'Vacinação',
      HealthTimelineType.consultation => 'Consulta veterinária',
      HealthTimelineType.exam => 'Exame',
      HealthTimelineType.dose => 'Medicação',
      HealthTimelineType.preventive => 'Preventivo',
      HealthTimelineType.incident => 'Intercorrência',
      HealthTimelineType.treatment => 'Tratamento',
      HealthTimelineType.weight => 'Pesagem',
      HealthTimelineType.observation => 'Observação',
      HealthTimelineType.document => 'Documento',
      HealthTimelineType.restriction => 'Restrição',
      HealthTimelineType.discharge => 'Alta',
      HealthTimelineType.meal => 'Alimentação',
      HealthTimelineType.supplement => 'Suplemento',
      null => 'Registro de saúde',
    };
    if (subtype != null && subtype.isNotEmpty) {
      return '$base · $subtype';
    }
    return base;
  }
}
