import '../../domain/health_document_gateway.dart';
import '../../domain/health_restriction_flow_errors.dart';
import '../../domain/health_restriction_issue_gateway.dart';
import '../../domain/health_v1_value_objects.dart';

/// Codec dos payloads do fluxo de restrição.
///
/// Duas responsabilidades: montar o request exato que cada callable espera e
/// parsear a resposta fail-closed. Campos server-owned não têm como ser
/// enviados — os comandos de domínio não os possuem.
abstract final class HealthRestrictionFlowPayloadCodec {
  HealthRestrictionFlowPayloadCodec._();

  // ── PREPARE ───────────────────────────────────────────────────────────────

  /// PREPARE não carrega metadata clínica: o B0 só deriva identidade e staging.
  static Map<String, dynamic> encodePrepare(
    PrepareHealthDocumentCommand command,
  ) {
    return <String, dynamic>{
      'dogId': command.dogId,
      'operationId': command.operationId,
    };
  }

  static PreparedHealthDocumentUpload parsePrepared(Object? raw) {
    const step = HealthRestrictionFlowStep.documentPrepare;
    final map = _requireMap(raw, step);
    final documentId = _requireString(map, const [
      'documentId',
      'document_id',
    ], step);
    final uploadPath = _requireString(map, const [
      'uploadPath',
      'upload_path',
    ], step);
    final dogId = _requireString(map, const ['dogId', 'dog_id'], step);
    final maxBytes = _requirePositiveInt(
      map['maxBytes'] ?? map['max_bytes'],
      step,
    );
    return PreparedHealthDocumentUpload(
      dogId: dogId,
      documentId: documentId,
      uploadPath: uploadPath,
      maxBytes: maxBytes,
    );
  }

  // ── FINALIZE ──────────────────────────────────────────────────────────────

  /// Mínimo do contrato B0. Sem `storagePath`/`uploadPath`/`mimeType`: o
  /// FINALIZE consulta o Storage real e é a autoridade sobre esses valores.
  static Map<String, dynamic> encodeFinalize(
    FinalizeHealthDocumentCommand command,
  ) {
    return <String, dynamic>{
      'dogId': command.dogId,
      'operationId': command.operationId,
      'documentType': command.nature.wireName,
      'title': command.title,
    };
  }

  static FinalizedHealthDocument parseFinalized(Object? raw) {
    const step = HealthRestrictionFlowStep.documentFinalize;
    final map = _requireMap(raw, step);
    final dogId = _requireString(map, const ['dogId', 'dog_id'], step);
    final documentId = _requireString(map, const [
      'documentId',
      'document_id',
    ], step);

    // `reference` é a superfície oficial: não reconstruímos o ref a partir de
    // document_id/storage_path quando o backend já o devolve.
    final referenceRaw = map['reference'];
    if (referenceRaw is! Map) {
      throw const HealthRestrictionFlowIntegrity(step);
    }
    final reference = Map<String, dynamic>.from(referenceRaw);
    final healthDocumentId = _requireString(reference, const [
      'health_document_id',
      'healthDocumentId',
    ], step);

    final description = reference['description'];
    return FinalizedHealthDocument(
      dogId: dogId,
      documentId: documentId,
      reference: HealthDocumentRef(
        healthDocumentId: healthDocumentId,
        description: description is String && description.trim().isNotEmpty
            ? description.trim()
            : null,
      ),
      wasNoOp: _requireBool(map['wasNoOp'] ?? map['was_no_op'], step),
    );
  }

  // ── ISSUE ─────────────────────────────────────────────────────────────────

  static Map<String, dynamic> encodeIssue(
    IssueOperationalRestrictionCommand command,
  ) {
    final professional = <String, dynamic>{
      // Chaves internas em snake_case: é o shape canônico de
      // ProfessionalIdentity no backend.
      'name': command.professional.name,
      'registration_type': command.professional.registrationType.wireName,
      'registration_number': command.professional.registrationNumber,
      'clinic': command.professional.clinic,
    };
    final specialty = command.professional.specialty?.trim();
    if (specialty != null && specialty.isNotEmpty) {
      professional['specialty'] = specialty;
    }

    final data = <String, dynamic>{
      'dogId': command.dogId,
      'operationId': command.operationId,
      'level': command.level.wireName,
      'category': command.category.wireName,
      'description': command.description,
      'professional': professional,
      'sourceDocument': <String, dynamic>{
        'health_document_id': command.sourceDocument.healthDocumentId,
      },
    };

    if (command.activitiesRestricted.isNotEmpty) {
      data['activitiesRestricted'] = List<String>.from(
        command.activitiesRestricted,
      );
    }
    if (command.expectedEnd != null) {
      data['expectedEnd'] = command.expectedEnd!.toUtc().toIso8601String();
    }
    return data;
  }

  static IssuedOperationalRestriction parseIssued(Object? raw) {
    const step = HealthRestrictionFlowStep.restrictionIssue;
    final map = _requireMap(raw, step);
    return IssuedOperationalRestriction(
      dogId: _requireString(map, const ['dogId', 'dog_id'], step),
      restrictionId: _requireString(map, const [
        'restrictionId',
        'restriction_id',
      ], step),
      wasNoOp: _requireBool(map['wasNoOp'] ?? map['was_no_op'], step),
    );
  }

  // ── Helpers fail-closed ───────────────────────────────────────────────────

  static Map<String, dynamic> _requireMap(
    Object? raw,
    HealthRestrictionFlowStep step,
  ) {
    if (raw is! Map) throw HealthRestrictionFlowIntegrity(step);
    return Map<String, dynamic>.from(raw);
  }

  static String _requireString(
    Map<String, dynamic> map,
    List<String> keys,
    HealthRestrictionFlowStep step,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    throw HealthRestrictionFlowIntegrity(step);
  }

  static bool _requireBool(Object? raw, HealthRestrictionFlowStep step) {
    if (raw is bool) return raw;
    throw HealthRestrictionFlowIntegrity(step);
  }

  static int _requirePositiveInt(
    Object? raw,
    HealthRestrictionFlowStep step,
  ) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0 && raw == raw.roundToDouble()) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    throw HealthRestrictionFlowIntegrity(step);
  }
}
