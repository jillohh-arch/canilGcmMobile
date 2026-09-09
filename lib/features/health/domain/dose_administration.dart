import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'health_v1_enums_ext.dart';
import 'health_v1_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DoseAdministration — Domain Model §2.5.
//
// Identidade documental (Domain Model §2.5 / §8.19; Schema §2.6; Foundation H10):
//   doseId = hash(protocolId + planned_dose_id)
//
// A documentação fixa a **identidade lógica composta** (dois valores, sem
// data/relógio) e a função hash. Não fixa formato textual de concatenação.
// Serialização pré-hash é interna, privada e inequívoca (length-prefix UTF-8)
// para evitar colisões (`"ab"+"c"` vs `"a"+"bc"`). SHA-256 via package:crypto.
// ─────────────────────────────────────────────────────────────────────────────

/// Identidade determinística de uma dose (Domain Model §2.5).
///
/// `protocolId` e `plannedDoseId` são componentes lógicos obrigatórios da
/// identidade composta (`doseId = hash(protocolId + planned_dose_id)`).
/// Strings vazias/whitespace são rejeitadas.
final class DoseIdentity {
  DoseIdentity({required String protocolId, required String plannedDoseId})
    : protocolId = protocolId.trim(),
      plannedDoseId = plannedDoseId.trim() {
    if (this.protocolId.isEmpty) {
      throw const HealthDomainException(
        'missing_protocol_id',
        'protocolId é obrigatório na identidade da dose',
      );
    }
    if (this.plannedDoseId.isEmpty) {
      throw const HealthDomainException(
        'missing_planned_dose_id',
        'plannedDoseId é obrigatório na identidade da dose',
      );
    }
  }

  final String protocolId;
  final String plannedDoseId;

  /// Deriva o `doseId` canônico: SHA-256 da serialização interna dos dois
  /// componentes da identidade composta.
  String deriveDoseId() {
    final digest = sha256.convert(_encodeCompositeIdentity());
    return digest.toString();
  }

  static String deriveFor(String protocolId, String plannedDoseId) =>
      DoseIdentity(
        protocolId: protocolId,
        plannedDoseId: plannedDoseId,
      ).deriveDoseId();

  /// Codificação **privada** length-prefixed (UTF-8) — não é contrato público.
  /// u32be(len(A)) || utf8(A) || u32be(len(B)) || utf8(B)
  Uint8List _encodeCompositeIdentity() {
    final protocolBytes = utf8.encode(protocolId);
    final plannedBytes = utf8.encode(plannedDoseId);
    final out = BytesBuilder(copy: false);
    out.add(_u32be(protocolBytes.length));
    out.add(protocolBytes);
    out.add(_u32be(plannedBytes.length));
    out.add(plannedBytes);
    return out.toBytes();
  }

  static Uint8List _u32be(int value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      throw const HealthDomainException(
        'invalid_dose_identity_component',
        'Componente da identidade de dose excede tamanho suportado',
      );
    }
    final bytes = Uint8List(4);
    bytes[0] = (value >> 24) & 0xFF;
    bytes[1] = (value >> 16) & 0xFF;
    bytes[2] = (value >> 8) & 0xFF;
    bytes[3] = value & 0xFF;
    return bytes;
  }

  @override
  bool operator ==(Object other) =>
      other is DoseIdentity &&
      other.protocolId == protocolId &&
      other.plannedDoseId == plannedDoseId;

  @override
  int get hashCode => Object.hash(protocolId, plannedDoseId);
}

final class DoseAdministration {
  DoseAdministration({
    required this.identity,
    required this.protocolId,
    required this.dogId,
    required this.scheduledFor,
    required this.status,
    required this.recordedBy,
    required this.recordedAt,
    required this.schemaVersion,
    this.administeredAt,
    this.administeredBy,
    String? skipReason,
    String? observations,
    List<String>? attachmentRefs,
    this.scheduleItemId,
  }) : skipReason = skipReason?.trim(),
       observations = observations?.trim(),
       attachmentRefs = List.unmodifiable(
         List<String>.of(attachmentRefs ?? const []),
       ) {
    if (schemaVersion <= 0) {
      throw const HealthDomainException(
        'invalid_schema_version',
        'schema_version deve ser positivo',
      );
    }
    if (protocolId != identity.protocolId) {
      throw const HealthDomainException(
        'inconsistent_protocol_id',
        'identity.protocolId deve coincidir com protocolId',
      );
    }
    if (scheduledFor.isAfter(recordedAt)) {
      throw const HealthDomainException(
        'inconsistent_schedule',
        'recorded_at não pode ser anterior a scheduled_for',
      );
    }
    if (status == DoseStatus.administered && administeredAt == null) {
      throw const HealthDomainException(
        'missing_administration',
        'administered exige administered_at',
      );
    }
    if (status == DoseStatus.skipped &&
        (this.skipReason == null || this.skipReason!.isEmpty)) {
      throw const HealthDomainException(
        'missing_skip_reason',
        'skipped exige skip_reason',
      );
    }
    if (status == DoseStatus.administered &&
        administeredAt != null &&
        administeredAt!.isAfter(recordedAt)) {
      throw const HealthDomainException(
        'inconsistent_administration_time',
        'administered_at não pode ser posterior a recorded_at',
      );
    }
  }

  final DoseIdentity identity;
  final String protocolId;
  final String dogId;
  final DateTime scheduledFor;
  final DoseStatus status;
  final RecordedBy recordedBy;
  final DateTime recordedAt;
  final int schemaVersion;

  final DateTime? administeredAt;
  final RecordedBy? administeredBy;
  final String? skipReason;
  final String? observations;
  final List<String> attachmentRefs;
  final String? scheduleItemId;

  String get doseId => identity.deriveDoseId();
  String get idempotencyKey => identity.deriveDoseId();

  Map<String, dynamic> toMap() {
    return {
      'dose_id': doseId,
      'protocol_id': protocolId,
      'dog_id': dogId,
      'planned_dose_id': identity.plannedDoseId,
      if (scheduleItemId != null) 'schedule_item_id': scheduleItemId,
      'idempotency_key': idempotencyKey,
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'status': status.wireName,
      'recorded_by': {
        'uid': recordedBy.uid,
        'name': recordedBy.name,
        'internal_role': recordedBy.internalRole,
      },
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'schema_version': schemaVersion,
      if (administeredAt != null)
        'administered_at': administeredAt!.toUtc().toIso8601String(),
      if (administeredBy != null)
        'administered_by': {
          'uid': administeredBy!.uid,
          'name': administeredBy!.name,
          'internal_role': administeredBy!.internalRole,
        },
      if (skipReason != null) 'skip_reason': skipReason,
      if (observations != null) 'observations': observations,
      if (attachmentRefs.isNotEmpty) 'attachment_refs': attachmentRefs,
    };
  }

  factory DoseAdministration.fromMap(
    Map<String, dynamic> map, {
    String? documentId,
  }) {
    final protocolId =
        map['protocol_id'] as String? ?? map['protocolId'] as String? ?? '';
    final plannedDoseId = map['planned_dose_id'] as String? ??
        map['plannedDoseId'] as String? ??
        '';
    final identity =
        DoseIdentity(protocolId: protocolId, plannedDoseId: plannedDoseId);
    final dogId = map['dog_id'] as String? ?? map['dogId'] as String? ?? '';
    final scheduledFor =
        _parseDateTime(map['scheduled_for'] ?? map['scheduledFor']) ??
            DateTime.now();
    final recordedAt =
        _parseDateTime(map['recorded_at'] ?? map['recordedAt']) ??
            DateTime.now();

    final statusStr = map['status'] as String? ?? 'administered';
    final status = DoseStatus.values.firstWhere(
      (s) => s.wireName == statusStr,
      orElse: () => DoseStatus.administered,
    );
    final schemaVersion = (map['schema_version'] as num?)?.toInt() ??
        (map['schemaVersion'] as num?)?.toInt() ??
        1;

    final recordedByMap =
        (map['recorded_by'] as Map?)?.cast<String, dynamic>() ?? const {};
    final recordedBy = RecordedBy(
      uid: recordedByMap['uid'] as String? ?? '',
      name: recordedByMap['name'] as String? ?? '',
      internalRole: recordedByMap['internal_role'] as String? ??
          recordedByMap['internalRole'] as String? ??
          'condutor',
    );

    final administeredByMap =
        (map['administered_by'] as Map?)?.cast<String, dynamic>();
    final administeredBy = administeredByMap != null
        ? RecordedBy(
            uid: administeredByMap['uid'] as String? ?? '',
            name: administeredByMap['name'] as String? ?? '',
            internalRole: administeredByMap['internal_role'] as String? ??
                administeredByMap['internalRole'] as String? ??
                'condutor',
          )
        : null;

    final rawAttachments = map['attachment_refs'] ?? map['attachmentRefs'];
    final attachmentRefs = rawAttachments is List
        ? rawAttachments.map((e) => e.toString()).toList()
        : <String>[];

    return DoseAdministration(
      identity: identity,
      protocolId: protocolId,
      dogId: dogId,
      scheduledFor: scheduledFor,
      status: status,
      recordedBy: recordedBy,
      recordedAt: recordedAt,
      schemaVersion: schemaVersion,
      administeredAt:
          _parseDateTime(map['administered_at'] ?? map['administeredAt']),
      administeredBy: administeredBy,
      skipReason: map['skip_reason'] as String? ?? map['skipReason'] as String?,
      observations: map['observations'] as String?,
      attachmentRefs: attachmentRefs,
      scheduleItemId: map['schedule_item_id'] as String? ??
          map['scheduleItemId'] as String?,
    );
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    try {
      final dynamic dyn = raw;
      final toDate = dyn.toDate;
      if (toDate is Function) return toDate() as DateTime;
    } catch (_) {}
    return null;
  }
}
