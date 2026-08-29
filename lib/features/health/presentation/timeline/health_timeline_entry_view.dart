import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';

/// Status de entrada na timeline principal (ADR-004 §13).
///
/// Apenas `final` e `cancelled`. Draft não entra na timeline.
/// Adendos não são um terceiro status.
enum HealthTimelineEntryStatus {
  finalised,
  cancelled;

  String get wireName => switch (this) {
    HealthTimelineEntryStatus.finalised => 'final',
    HealthTimelineEntryStatus.cancelled => 'cancelled',
  };

  /// Parse defensivo: desconhecido não lança.
  static HealthTimelineEntryStatus? tryParse(Object? input) {
    final raw = input?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    for (final v in HealthTimelineEntryStatus.values) {
      if (v.wireName == raw) return v;
    }
    // Aceita alias legado "finalised" se aparecer em dados de teste/local.
    if (raw == 'finalised') return HealthTimelineEntryStatus.finalised;
    return null;
  }
}

/// Resolução forward-compatible de [HealthTimelineType].
///
/// Reutiliza o enum oficial do domínio para valores conhecidos e preserva
/// [raw] quando a fonte envia tipo futuro/desconhecido — sem derrubar a timeline.
final class HealthTimelineTypeView {
  const HealthTimelineTypeView._({required this.raw, this.known});

  factory HealthTimelineTypeView.known(HealthTimelineType type) {
    return HealthTimelineTypeView._(raw: type.wireName, known: type);
  }

  /// Parse a partir de wire string. Nunca lança por tipo desconhecido.
  factory HealthTimelineTypeView.parse(Object? input) {
    final raw = input?.toString().trim() ?? '';
    if (raw.isEmpty) {
      throw ArgumentError.value(input, 'type', 'tipo não pode ser vazio');
    }
    for (final t in HealthTimelineType.values) {
      if (t.wireName == raw) {
        return HealthTimelineTypeView._(raw: raw, known: t);
      }
    }
    return HealthTimelineTypeView._(raw: raw);
  }

  /// Valor wire preservado (conhecido ou desconhecido).
  final String raw;

  /// Enum oficial quando reconhecido; `null` se desconhecido.
  final HealthTimelineType? known;

  bool get isKnown => known != null;
  bool get isUnknown => known == null;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineTypeView &&
      other.raw == raw &&
      other.known == known;

  @override
  int get hashCode => Object.hash(raw, known);
}

/// Metadados de adendos (não são status).
final class HealthTimelineAmendmentMetadata {
  HealthTimelineAmendmentMetadata({
    this.hasAmendments = false,
    this.amendmentCount = 0,
    this.lastAmendedAt,
  }) {
    if (amendmentCount < 0) {
      throw ArgumentError.value(
        amendmentCount,
        'amendmentCount',
        'não pode ser negativo',
      );
    }
    if (!hasAmendments && amendmentCount > 0) {
      throw ArgumentError('hasAmendments == false exige amendmentCount == 0');
    }
    if (hasAmendments && amendmentCount == 0) {
      throw ArgumentError('hasAmendments == true exige amendmentCount > 0');
    }
  }

  final bool hasAmendments;
  final int amendmentCount;
  final DateTime? lastAmendedAt;

  static final none = HealthTimelineAmendmentMetadata();

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineAmendmentMetadata &&
      other.hasAmendments == hasAmendments &&
      other.amendmentCount == amendmentCount &&
      other.lastAmendedAt == lastAmendedAt;

  @override
  int get hashCode => Object.hash(hasAmendments, amendmentCount, lastAmendedAt);
}

/// Read model de apresentação de uma entrada da timeline Health.
///
/// Não é entidade canônica de domínio. Não aplica regras clínicas,
/// prontidão, tratamento ou agenda. Composição preferida a monólito.
final class HealthTimelineEntryView {
  HealthTimelineEntryView({
    required String id,
    required String dogId,
    required this.type,
    required this.occurredAt,
    required this.recordedAt,
    required String title,
    String? subtitle,
    required this.status,
    String? caseId,
    String? caseTitle,
    this.recordedBy,
    this.professional,
    this.operationalImpact,
    this.hasAttachments = false,
    this.attachmentCount,
    HealthTimelineAmendmentMetadata? amendments,
    this.detailReference,
    this.traceability,
  }) : id = _required(id, 'id'),
       dogId = _required(dogId, 'dogId'),
       title = _required(title, 'title'),
       subtitle = _trimOrNull(subtitle),
       caseId = _trimOrNull(caseId),
       caseTitle = _trimOrNull(caseTitle),
       amendments = amendments ?? HealthTimelineAmendmentMetadata.none {
    if (attachmentCount != null && attachmentCount! < 0) {
      throw ArgumentError.value(
        attachmentCount,
        'attachmentCount',
        'não pode ser negativo',
      );
    }
    if (hasAttachments == false &&
        attachmentCount != null &&
        attachmentCount! > 0) {
      throw ArgumentError(
        'hasAttachments == false é inconsistente com attachmentCount > 0',
      );
    }
  }

  final String id;
  final String dogId;
  final HealthTimelineTypeView type;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final String title;
  final String? subtitle;
  final HealthTimelineEntryStatus status;
  final String? caseId;
  final String? caseTitle;

  /// Quem registrou no sistema (usuário interno).
  final RecordedBy? recordedBy;

  /// Quem prestou o atendimento clínico (pode ser externo).
  ///
  /// Usa resumo leve de apresentação — não colapsa com [recordedBy].
  final ProfessionalIdentitySummary? professional;

  /// Impacto operacional documentado na entrada (metadata; não calcula prontidão).
  final OperationalImpact? operationalImpact;

  final bool hasAttachments;
  final int? attachmentCount;
  final HealthTimelineAmendmentMetadata amendments;
  final HealthTimelineDetailReference? detailReference;
  final HealthTimelineTraceability? traceability;

  bool get isCancelled => status == HealthTimelineEntryStatus.cancelled;
  bool get isFinal => status == HealthTimelineEntryStatus.finalised;

  HealthTimelineEntryView copyWith({
    String? id,
    String? dogId,
    HealthTimelineTypeView? type,
    DateTime? occurredAt,
    DateTime? recordedAt,
    String? title,
    String? subtitle,
    bool clearSubtitle = false,
    HealthTimelineEntryStatus? status,
    String? caseId,
    bool clearCaseId = false,
    String? caseTitle,
    bool clearCaseTitle = false,
    RecordedBy? recordedBy,
    bool clearRecordedBy = false,
    ProfessionalIdentitySummary? professional,
    bool clearProfessional = false,
    OperationalImpact? operationalImpact,
    bool clearOperationalImpact = false,
    bool? hasAttachments,
    int? attachmentCount,
    bool clearAttachmentCount = false,
    HealthTimelineAmendmentMetadata? amendments,
    HealthTimelineDetailReference? detailReference,
    bool clearDetailReference = false,
    HealthTimelineTraceability? traceability,
    bool clearTraceability = false,
  }) {
    return HealthTimelineEntryView(
      id: id ?? this.id,
      dogId: dogId ?? this.dogId,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
      recordedAt: recordedAt ?? this.recordedAt,
      title: title ?? this.title,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      status: status ?? this.status,
      caseId: clearCaseId ? null : (caseId ?? this.caseId),
      caseTitle: clearCaseTitle ? null : (caseTitle ?? this.caseTitle),
      recordedBy: clearRecordedBy ? null : (recordedBy ?? this.recordedBy),
      professional: clearProfessional
          ? null
          : (professional ?? this.professional),
      operationalImpact: clearOperationalImpact
          ? null
          : (operationalImpact ?? this.operationalImpact),
      hasAttachments: hasAttachments ?? this.hasAttachments,
      attachmentCount: clearAttachmentCount
          ? null
          : (attachmentCount ?? this.attachmentCount),
      amendments: amendments ?? this.amendments,
      detailReference: clearDetailReference
          ? null
          : (detailReference ?? this.detailReference),
      traceability: clearTraceability
          ? null
          : (traceability ?? this.traceability),
    );
  }

  static String _required(String value, String field) {
    final t = value.trim();
    if (t.isEmpty) {
      throw ArgumentError.value(value, field, '$field é obrigatório');
    }
    return t;
  }

  static String? _trimOrNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineEntryView &&
      other.id == id &&
      other.dogId == dogId &&
      other.type == type &&
      other.occurredAt == occurredAt &&
      other.recordedAt == recordedAt &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.status == status &&
      other.caseId == caseId &&
      other.caseTitle == caseTitle &&
      other.recordedBy == recordedBy &&
      other.professional == professional &&
      other.operationalImpact == operationalImpact &&
      other.hasAttachments == hasAttachments &&
      other.attachmentCount == attachmentCount &&
      other.amendments == amendments &&
      other.detailReference == detailReference &&
      other.traceability == traceability;

  @override
  int get hashCode => Object.hash(
    id,
    dogId,
    type,
    occurredAt,
    recordedAt,
    title,
    subtitle,
    status,
    caseId,
    caseTitle,
    recordedBy,
    professional,
    operationalImpact,
    hasAttachments,
    attachmentCount,
    amendments,
    detailReference,
    traceability,
  );
}
