import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/clinical_event_read_model.dart';
import '../../domain/health_v1_enums.dart';

/// Parser defensivo para documentos persistidos de ClinicalEvent e ClinicalAmendment.
///
/// Invariantes aplicadas:
/// 1. Não lança exceção fatal por documento individual malformado.
/// 2. Não inventa dados clínicos ausentes (Rule 7.1: UNKNOWN não vira false/0/now).
/// 3. Distingue estritamente `occurred_at` de `recorded_at`.
/// 4. Preserva enums desconhecidos e contratos de payload em seu estado bruto.
/// 5. Registra degradações de integridade em `dataQualityIssues`.
abstract final class ClinicalEventDocumentParser {
  ClinicalEventDocumentParser._();

  /// Converte um documento Firestore na representação [ClinicalEventReadModel].
  static ClinicalEventReadModel parseEvent({
    required String dogId,
    required String caseId,
    required String eventId,
    required Map<String, dynamic> data,
  }) {
    final issues = <String>[];

    // Identidades contextuais: autoridade primária é o path do documento,
    // com verificação de coerência se existirem redundâncias no snapshot.
    final resolvedDogId = (data['dog_id'] as String?)?.trim().isNotEmpty == true
        ? (data['dog_id'] as String).trim()
        : dogId;
    final resolvedCaseId =
        (data['case_id'] as String?)?.trim().isNotEmpty == true
        ? (data['case_id'] as String).trim()
        : caseId;
    final resolvedEventId =
        (data['event_id'] as String?)?.trim().isNotEmpty == true
        ? (data['event_id'] as String).trim()
        : eventId;

    if (resolvedDogId != dogId) {
      issues.add('path_document_dog_id_mismatch');
    }
    if (resolvedCaseId != caseId) {
      issues.add('path_document_case_id_mismatch');
    }
    if (resolvedEventId != eventId) {
      issues.add('path_document_event_id_mismatch');
    }

    // Tipo do evento
    final rawType = data['event_type'] ?? data['type'];
    final parsedType = ClinicalEventTypeWire.parse(rawType);
    if (parsedType.isAbsent) {
      issues.add('missing_event_type');
    } else if (parsedType.isUnknown) {
      issues.add('unknown_event_type:${parsedType.raw}');
    }

    // Status do evento
    final rawStatus = data['status'];
    final parsedStatus = ClinicalEventStatusWire.parse(rawStatus);
    if (parsedStatus.isAbsent) {
      issues.add('missing_event_status');
    } else if (parsedStatus.isUnknown) {
      issues.add('unknown_event_status:${parsedStatus.raw}');
    }

    // Instantes temporais (distinção estrita: occurred_at != recorded_at)
    final occurredAtResult = _parseInstant(
      data['occurred_at'] ?? data['occurredAt'],
    );
    if (occurredAtResult.isMalformed) {
      issues.add('malformed_occurred_at');
    } else if (occurredAtResult.value == null) {
      issues.add('missing_occurred_at');
    }
    final occurredAt = occurredAtResult.value;

    final recordedAtResult = _parseInstant(
      data['recorded_at'] ?? data['recordedAt'],
    );
    if (recordedAtResult.isMalformed) {
      issues.add('malformed_recorded_at');
    } else if (recordedAtResult.value == null) {
      issues.add('missing_recorded_at');
    }
    final recordedAt = recordedAtResult.value;

    final updatedAtResult = _parseInstant(
      data['updated_at'] ?? data['updatedAt'],
    );
    if (updatedAtResult.isMalformed) {
      issues.add('malformed_updated_at');
    }
    final updatedAt = updatedAtResult.value;

    // Ator que registrou
    final recordedBy = _parseActor(
      data['recorded_by'] ?? data['recordedBy'],
      issues,
      prefix: 'recorded_by',
    );

    // Payload metadata
    final payloadType = (data['payload_type'] ?? data['payloadType'])
        ?.toString();
    if (payloadType == null || payloadType.trim().isEmpty) {
      issues.add('missing_payload_type');
    }

    final payloadVersion = _parseInt(
      data['payload_version'] ?? data['payloadVersion'],
    );
    if (payloadVersion == null) {
      issues.add('missing_payload_version');
    } else if (payloadVersion <= 0) {
      issues.add('invalid_payload_version:$payloadVersion');
    }

    final schemaVersion = _parseInt(
      data['schema_version'] ?? data['schemaVersion'],
    );
    if (schemaVersion == null) {
      issues.add('missing_schema_version');
    } else if (schemaVersion <= 0) {
      issues.add('invalid_schema_version:$schemaVersion');
    }

    final revision = _parseInt(data['revision']);
    if (revision == null) {
      issues.add('missing_revision');
    } else if (revision <= 0) {
      issues.add('invalid_revision:$revision');
    }

    // Conteúdo clínico (preserva raw Map)
    final rawContent = data['content'];
    final Map<String, dynamic> content;
    if (rawContent is Map) {
      content = Map<String, dynamic>.unmodifiable(
        rawContent.map((k, v) => MapEntry(k.toString(), v)),
      );
    } else {
      if (rawContent != null) {
        issues.add('invalid_content_shape');
      }
      content = const <String, dynamic>{};
    }

    // Anexos
    final rawAttachments = data['attachment_refs'] ?? data['attachmentRefs'];
    final List<String> attachmentRefs;
    if (rawAttachments is List) {
      attachmentRefs = List<String>.unmodifiable(
        rawAttachments.map((e) => e.toString()),
      );
    } else {
      attachmentRefs = const <String>[];
    }

    // Metadados de emendas (Rule 7.1: Preservar null se ausente!)
    final bool? hasAmendments;
    if (data.containsKey('has_amendments')) {
      final val = data['has_amendments'];
      if (val is bool) {
        hasAmendments = val;
      } else {
        issues.add('malformed_has_amendments');
        hasAmendments = null;
      }
    } else {
      hasAmendments = null;
    }

    final int? amendmentCount;
    if (data.containsKey('amendment_count')) {
      final val = data['amendment_count'];
      if (val is num) {
        final count = val.toInt();
        if (count < 0) {
          issues.add('negative_amendment_count:$count');
          amendmentCount = null;
        } else {
          amendmentCount = count;
        }
      } else {
        issues.add('malformed_amendment_count');
        amendmentCount = null;
      }
    } else {
      amendmentCount = null;
    }

    // Consistência interna de emendas quando ambos presentes
    if (hasAmendments != null && amendmentCount != null) {
      if (hasAmendments == true && amendmentCount == 0) {
        issues.add(
          'inconsistent_amendments:has_amendments_true_with_zero_count',
        );
      } else if (hasAmendments == false && amendmentCount > 0) {
        issues.add(
          'inconsistent_amendments:has_amendments_false_with_positive_count',
        );
      }
    }

    final lastAmendedAtResult = _parseInstant(
      data['last_amended_at'] ?? data['lastAmendedAt'],
    );
    if (lastAmendedAtResult.isMalformed) {
      issues.add('malformed_last_amended_at');
    }
    final lastAmendedAt = lastAmendedAtResult.value;

    // Metadados de finalização
    final finalizedAtResult = _parseInstant(
      data['finalized_at'] ?? data['finalizedAt'],
    );
    if (finalizedAtResult.isMalformed) {
      issues.add('malformed_finalized_at');
    }
    final finalizedAt = finalizedAtResult.value;

    // Metadados de cancelamento
    final cancelReasonRaw = data['cancel_reason'] ?? data['cancelReason'];
    final String? cancelReason =
        cancelReasonRaw is String && cancelReasonRaw.trim().isNotEmpty
        ? cancelReasonRaw.trim()
        : null;

    final cancelledAtResult = _parseInstant(
      data['cancelled_at'] ?? data['cancelledAt'],
    );
    if (cancelledAtResult.isMalformed) {
      issues.add('malformed_cancelled_at');
    }
    final cancelledAt = cancelledAtResult.value;

    final cancelledBy = _parseActor(
      data['cancelled_by'] ?? data['cancelledBy'],
      issues,
      prefix: 'cancelled_by',
      isRequired: parsedStatus.value == ClinicalEventStatus.cancelled,
    );

    if (parsedStatus.value == ClinicalEventStatus.cancelled) {
      if (cancelReason == null) issues.add('cancelled_event_missing_reason');
      if (cancelledAt == null) issues.add('cancelled_event_missing_timestamp');
      if (cancelledBy == null) issues.add('cancelled_event_missing_actor');
    }

    // Identidade profissional externa
    final rawProf = data['professional'];
    final ClinicalProfessionalReadModel? professional;
    if (rawProf is Map) {
      professional = ClinicalProfessionalReadModel(
        id: rawProf['id']?.toString().trim(),
        name: rawProf['name']?.toString().trim(),
        council: rawProf['council']?.toString().trim(),
        registrationType:
            (rawProf['registration_type'] ?? rawProf['registrationType'])
                ?.toString()
                .trim(),
        registrationNumber:
            (rawProf['registration_number'] ?? rawProf['registrationNumber'])
                ?.toString()
                .trim(),
        rawMap: Map<String, dynamic>.unmodifiable(
          rawProf.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    } else {
      professional = null;
    }

    // Exam ID (quando presente)
    final examId = (data['exam_id'] ?? data['examId'])?.toString().trim();

    return ClinicalEventReadModel(
      id: resolvedEventId,
      caseId: resolvedCaseId,
      dogId: resolvedDogId,
      type: parsedType,
      status: parsedStatus,
      occurredAt: occurredAt,
      recordedAt: recordedAt,
      updatedAt: updatedAt,
      recordedBy: recordedBy,
      payloadType: payloadType,
      payloadVersion: payloadVersion,
      schemaVersion: schemaVersion,
      revision: revision,
      content: content,
      attachmentRefs: attachmentRefs,
      hasAmendments: hasAmendments,
      amendmentCount: amendmentCount,
      lastAmendedAt: lastAmendedAt,
      finalizedAt: finalizedAt,
      cancelReason: cancelReason,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      professional: professional,
      examId: examId?.isNotEmpty == true ? examId : null,
      dataQualityIssues: List<String>.unmodifiable(issues),
      rawDoc: Map<String, dynamic>.unmodifiable(data),
    );
  }

  /// Converte um documento Firestore de emenda na representação [ClinicalAmendmentReadModel].
  static ClinicalAmendmentReadModel parseAmendment({
    required String dogId,
    required String caseId,
    required String eventId,
    required String amendmentId,
    required Map<String, dynamic> data,
    int? ordinal,
  }) {
    final issues = <String>[];

    // Tipo de emenda
    final rawType = data['type'];
    final parsedType = ClinicalAmendmentType.parse(rawType);
    if (parsedType.isAbsent) {
      issues.add('missing_amendment_type');
    } else if (parsedType.isUnknown) {
      issues.add('unknown_amendment_type:${parsedType.raw}');
    }

    // Motivo / Reason
    final rawReason = data['reason'];
    final String reason;
    if (rawReason is String && rawReason.trim().isNotEmpty) {
      reason = rawReason.trim();
    } else {
      issues.add('missing_amendment_reason');
      reason = rawReason?.toString().trim() ?? '';
    }

    // Instante em que a emenda foi gravada
    final recordedAtResult = _parseInstant(
      data['recorded_at'] ?? data['recordedAt'],
    );
    if (recordedAtResult.isMalformed) {
      issues.add('malformed_amendment_recorded_at');
    } else if (recordedAtResult.value == null) {
      issues.add('missing_amendment_recorded_at');
    }
    final recordedAt = recordedAtResult.value;

    // Ator que registrou
    final recordedBy = _parseActor(
      data['recorded_by'] ?? data['recordedBy'],
      issues,
      prefix: 'amendment_recorded_by',
    );

    // Payload metadata
    final payloadType = (data['payload_type'] ?? data['payloadType'])
        ?.toString();
    final payloadVersion = _parseInt(
      data['payload_version'] ?? data['payloadVersion'],
    );
    final schemaVersion = _parseInt(
      data['schema_version'] ?? data['schemaVersion'],
    );

    // Conteúdo da emenda
    final rawContent = data['content'];
    final Map<String, dynamic> content;
    if (rawContent is Map) {
      content = Map<String, dynamic>.unmodifiable(
        rawContent.map((k, v) => MapEntry(k.toString(), v)),
      );
    } else {
      if (rawContent != null) {
        issues.add('invalid_amendment_content_shape');
      }
      content = const <String, dynamic>{};
    }

    return ClinicalAmendmentReadModel(
      id: amendmentId,
      eventId: eventId,
      caseId: caseId,
      dogId: dogId,
      type: parsedType,
      reason: reason,
      payloadType: payloadType,
      payloadVersion: payloadVersion,
      content: content,
      recordedBy: recordedBy,
      recordedAt: recordedAt,
      schemaVersion: schemaVersion,
      ordinal: ordinal,
      dataQualityIssues: List<String>.unmodifiable(issues),
      rawDoc: Map<String, dynamic>.unmodifiable(data),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Parsing Helpers Internos
  // ───────────────────────────────────────────────────────────────────────────

  static _InstantResult _parseInstant(Object? raw) {
    if (raw == null) return const _InstantResult(null, false);
    if (raw is Timestamp) return _InstantResult(raw.toDate().toUtc(), false);
    if (raw is DateTime) return _InstantResult(raw.toUtc(), false);
    if (raw is int) {
      return _InstantResult(
        DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true),
        false,
      );
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const _InstantResult(null, false);
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return _InstantResult(parsed.toUtc(), false);
      return const _InstantResult(null, true);
    }
    return const _InstantResult(null, true);
  }

  static int? _parseInt(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static ClinicalActorReadModel? _parseActor(
    Object? raw,
    List<String> issues, {
    required String prefix,
    bool isRequired = true,
  }) {
    if (raw == null) {
      if (isRequired) issues.add('missing_$prefix');
      return null;
    }
    if (raw is! Map) {
      issues.add('malformed_$prefix');
      return null;
    }

    final map = Map<String, dynamic>.from(raw);
    final uid = map['uid']?.toString().trim() ?? '';
    final name = map['name']?.toString().trim() ?? '';
    final role =
        (map['internal_role'] ?? map['internalRole'] ?? map['role'])
            ?.toString()
            .trim() ??
        '';

    var degraded = false;
    if (uid.isEmpty) {
      issues.add('${prefix}_missing_uid');
      degraded = true;
    }
    if (name.isEmpty) {
      issues.add('${prefix}_missing_name');
      degraded = true;
    }
    if (role.isEmpty) {
      issues.add('${prefix}_missing_internal_role');
      degraded = true;
    }

    return ClinicalActorReadModel(
      uid: uid,
      name: name,
      internalRole: role,
      rawMap: Map<String, dynamic>.unmodifiable(map),
      isDegraded: degraded,
    );
  }
}

class _InstantResult {
  const _InstantResult(this.value, this.isMalformed);
  final DateTime? value;
  final bool isMalformed;
}
