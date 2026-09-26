import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_gateway.dart';

abstract final class ClinicalIncidentEventParser {
  ClinicalIncidentEventParser._();

  static ClinicalIncidentRecordView? tryParse({
    required String caseId,
    required String eventId,
    required Map<String, dynamic> data,
  }) {
    final eventType = (data['event_type'] as String?)?.trim();
    if (eventType != 'incident') return null;

    final content = data['content'];
    if (content is! Map<String, dynamic>) return null;

    final categoryRaw = (content['category'] ?? content['nature']) as String?;
    final category = categoryRaw != null
        ? IncidentCategoryWire.fromWire(categoryRaw)
        : IncidentCategory.other;

    final severityRaw = content['severity'] as String?;
    final severity = severityRaw != null
        ? IncidentSeverityWire.fromWire(severityRaw)
        : IncidentSeverity.mild;

    final description = (content['description'] as String?)?.trim() ?? '';
    final initialConduct = (content['initial_conduct'] as String?)?.trim();

    DateTime occurredAt;
    final occurredRaw = data['occurred_at'];
    if (occurredRaw is Timestamp) {
      occurredAt = occurredRaw.toDate();
    } else if (occurredRaw is String) {
      occurredAt = DateTime.tryParse(occurredRaw) ?? DateTime.now();
    } else {
      occurredAt = DateTime.now();
    }

    final status = (data['status'] as String?)?.trim() ?? 'draft';

    return ClinicalIncidentRecordView(
      caseId: caseId,
      eventId: eventId,
      occurredAt: occurredAt,
      category: category,
      severity: severity,
      description: description,
      initialConduct: initialConduct,
      statusWireName: status,
      isFinal: status == 'final',
    );
  }
}
