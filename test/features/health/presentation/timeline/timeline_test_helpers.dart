import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';

HealthTimelineEntryView entry({
  required String id,
  String dogId = 'dog-a',
  HealthTimelineType type = HealthTimelineType.consultation,
  String? typeRaw,
  DateTime? occurredAt,
  DateTime? recordedAt,
  String title = 'Entrada',
  String? subtitle,
  HealthTimelineEntryStatus status = HealthTimelineEntryStatus.finalised,
  String? caseId,
  String? caseTitle,
  RecordedBy? recordedBy,
  ProfessionalIdentitySummary? professional,
  OperationalImpact? operationalImpact,
  bool hasAttachments = false,
  int? attachmentCount,
  HealthTimelineAmendmentMetadata? amendments,
  HealthTimelineDetailReference? detailReference,
  HealthTimelineTraceability? traceability,
}) {
  final at = occurredAt ?? DateTime(2026, 7, 10, 12);
  return HealthTimelineEntryView(
    id: id,
    dogId: dogId,
    type: typeRaw != null
        ? HealthTimelineTypeView.parse(typeRaw)
        : HealthTimelineTypeView.known(type),
    occurredAt: at,
    recordedAt: recordedAt ?? at,
    title: title,
    subtitle: subtitle,
    status: status,
    caseId: caseId,
    caseTitle: caseTitle,
    recordedBy: recordedBy,
    professional: professional,
    operationalImpact: operationalImpact,
    hasAttachments: hasAttachments,
    attachmentCount: attachmentCount,
    amendments: amendments,
    detailReference: detailReference,
    traceability: traceability,
  );
}

HealthTimelinePage pageOf(
  List<HealthTimelineEntryView> items, {
  String? nextCursorToken,
  bool? hasMore,
}) {
  final more = hasMore ?? nextCursorToken != null;
  return HealthTimelinePage(
    items: items,
    nextCursor: more
        ? HealthTimelineCursor(nextCursorToken ?? 'cursor-next')
        : null,
    hasMore: more,
  );
}

RecordedBy sampleRecorder() =>
    RecordedBy(uid: 'u1', name: 'Condutor Silva', internalRole: 'condutor');

ProfessionalIdentitySummary sampleProfessional() =>
    const ProfessionalIdentitySummary(name: 'Dra. Ana', specialty: 'Clínica');

OperationalImpact sampleImpact() => OperationalImpact(
  level: OperationalImpactLevel.low,
  description: 'Repouso leve',
);
