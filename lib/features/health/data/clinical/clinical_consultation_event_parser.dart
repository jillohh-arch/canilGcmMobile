import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';

/// Converte um documento persistido de `clinical_events` na projeção de
/// leitura de domínio.
///
/// **Somente consultas CONCLUÍDAS.** Devolve `null` para qualquer documento que
/// não seja exatamente `consultation` / `consultation_v1` / `final` — inclusive
/// um `draft` deixado por falha parcial de finalização, que não é uma consulta
/// concluída e não pode ser exibido como tal.
abstract final class ClinicalConsultationEventParser {
  ClinicalConsultationEventParser._();

  static ClinicalConsultationRecordView? tryParse({
    required String caseId,
    required String eventId,
    required Map<String, dynamic> data,
  }) {
    final status = ClinicalEventStatusWire.parse(data['status']);
    if (status.value != ClinicalEventStatus.finalised) return null;

    final eventType = ClinicalEventTypeWire.parse(data['event_type']);
    if (eventType.value != ClinicalEventType.consultation) return null;

    if (_text(data['payload_type']) != 'consultation_v1') return null;

    final occurredAt = _instant(data['occurred_at']);
    if (occurredAt == null) return null;

    final content = _map(data['content']);
    final professional = _map(data['professional']);
    final recordedBy = _map(data['recorded_by']);

    return ClinicalConsultationRecordView(
      caseId: caseId,
      eventId: eventId,
      occurredAt: occurredAt,
      reasonLabel: _reasonLabel(content['reason']),
      veterinarianName: _text(content['veterinarian_name']),
      clinicOrLocation: _text(content['clinic_or_location']),
      findings: _text(content['findings']),
      diagnosis: _text(content['diagnosis']),
      operationalStatusLabel: _operationalLabel(content['operational_status']),
      professionalName: _text(professional['name']),
      professionalRegistration: _registration(professional),
      recordedByName: _text(recordedBy['name']),
    );
  }

  static Map<String, dynamic> _map(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  static String? _text(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static DateTime? _instant(Object? raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim());
    }
    return null;
  }

  static String? _registration(Map<String, dynamic> professional) {
    final type = _text(professional['registration_type']);
    final number = _text(professional['registration_number']);
    if (type == null && number == null) return null;
    if (type == null) return number;
    if (number == null) return type;
    return '$type $number';
  }

  static String _reasonLabel(Object? raw) {
    final wire = _text(raw);
    if (wire == null) return 'Consulta';
    for (final reason in ConsultationReason.values) {
      if (reason.wireValue == wire) return reason.label;
    }
    return 'Consulta';
  }

  static String? _operationalLabel(Object? raw) {
    final wire = _text(raw);
    if (wire == null) return null;
    for (final status in ConsultationOperationalStatus.values) {
      if (status.wireValue == wire) return status.label;
    }
    return null;
  }
}
