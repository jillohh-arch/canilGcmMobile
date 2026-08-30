import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';

/// Natureza da recusa do parser canônico.
enum CanonicalRestrictionParseErrorCode {
  /// Contrato violado: campo obrigatório ausente, tipo errado ou valor fora do
  /// vocabulário canônico.
  malformed,

  /// `schema_version` que este Mobile não sabe interpretar. Distinto de
  /// malformado: o documento pode estar íntegro numa versão futura.
  unsupportedSchemaVersion,

  /// Documento pertence a outro K9, ou a identidade persistida divergiu do
  /// document id. Nunca é interpretado.
  identityMismatch,
}

final class CanonicalRestrictionParseException implements Exception {
  const CanonicalRestrictionParseException(
    this.code,
    this.field, [
    this.detail,
  ]);

  final CanonicalRestrictionParseErrorCode code;

  /// Campo canônico que causou a recusa, em vocabulário wire.
  final String field;
  final String? detail;

  @override
  String toString() =>
      'CanonicalRestrictionParseException(${code.name}, $field'
      '${detail == null ? '' : ', $detail'})';
}

/// Parser fail-closed do documento canônico de OperationalRestriction.
///
/// Refere-se a `dogs/{dogId}/operational_restrictions/{restrictionId}` — a
/// autoridade de detalhe. NÃO lê `health_summary/current`: aquela projeção é
/// deliberadamente um resumo de restrições ativas e não carrega metadata
/// terminal, profissional nem evidência.
///
/// Duas identidades NÃO são persistidas pelo backend e portanto vêm do path:
/// `dog_id` e `id`. Se qualquer uma aparecer no documento divergindo do path,
/// isso é corrupção e falha fechado — o path é a autoridade.
abstract final class CanonicalOperationalRestrictionParser {
  CanonicalOperationalRestrictionParser._();

  /// Maior `schema_version` que este Mobile entende.
  ///
  /// Espelha `OPERATIONAL_RESTRICTION_SCHEMA_VERSION` do backend
  /// (`functions/src/health_restriction_logic.ts`).
  static const supportedSchemaVersion = 1;

  // Mapas reversos derivados do `wireName` canônico: nenhum literal de wire é
  // reescrito aqui, então o parser não pode divergir do enum.
  static final Map<String, RestrictionLevel> _levels = {
    for (final v in RestrictionLevel.values) v.wireName: v,
  };
  static final Map<String, RestrictionCategory> _categories = {
    for (final v in RestrictionCategory.values) v.wireName: v,
  };
  static final Map<String, RestrictionStatus> _statuses = {
    for (final v in RestrictionStatus.values) v.wireName: v,
  };

  /// Converte o documento canônico no agregado tipado.
  ///
  /// [queryDogId] é o K9 da consulta ativa e [documentId] é o id do
  /// `DocumentSnapshot`: ambos vêm do path, nunca do payload.
  static OperationalRestriction parseDocument({
    required String documentId,
    required String queryDogId,
    required Map<String, dynamic> data,
  }) {
    final restrictionId = documentId.trim();
    if (restrictionId.isEmpty) {
      throw const CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.identityMismatch,
        'id',
        'document id vazio',
      );
    }
    final dogId = queryDogId.trim();
    if (dogId.isEmpty) {
      throw const CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.identityMismatch,
        'dog_id',
        'dogId da consulta vazio',
      );
    }

    // O backend não persiste `id` nem `dog_id`. Presentes e divergentes =>
    // corrupção; presentes e iguais => redundância tolerada.
    _assertIdentityIfPresent(data['id'], restrictionId, 'id');
    _assertIdentityIfPresent(data['dog_id'], dogId, 'dog_id');

    final schemaVersion = _requireInt(data['schema_version'], 'schema_version');
    if (schemaVersion != supportedSchemaVersion) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.unsupportedSchemaVersion,
        'schema_version',
        '$schemaVersion',
      );
    }

    final status = _requireEnum(data['status'], _statuses, 'status');
    final level = _requireEnum(data['level'], _levels, 'level');
    final category = _requireEnum(data['category'], _categories, 'category');
    final description = _requireString(data['description'], 'description');

    // `issued_at` é o canônico do Schema §2.12; `since` é o alias que o reader
    // aceita historicamente. Ausência dos dois é contrato violado, não default.
    final issuedAt =
        _optionalTimestamp(data['issued_at'], 'issued_at') ??
        _optionalTimestamp(data['since'], 'since');
    if (issuedAt == null) {
      throw const CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        'issued_at',
        'ausente',
      );
    }

    final activities = _requireStringList(
      data['activities_restricted'],
      'activities_restricted',
    );
    final expectedEnd = _optionalTimestamp(data['expected_end'], 'expected_end');
    final recordedBy = _requireActor(data['recorded_by'], 'recorded_by');
    final professional = _requireProfessional(
      data['professional'],
      'professional',
    );
    final sourceDocument = _requireDocumentRef(
      data['source_document'],
      'source_document',
    );

    // Metadata terminal: cada campo é parseado estritamente quando presente. A
    // completude e a exclusividade END/CANCEL são invariantes do agregado, que
    // as recusa como HealthDomainException — traduzida abaixo.
    final actualEnd = _optionalTimestamp(data['actual_end'], 'actual_end');
    final endedBy = _optionalActor(data['ended_by'], 'ended_by');
    final endReason = _optionalString(data['end_reason'], 'end_reason');
    final endProfessional = _optionalProfessional(
      data['end_professional'],
      'end_professional',
    );
    final endSourceDocument = _optionalDocumentRef(
      data['end_source_document'],
      'end_source_document',
    );
    final cancelledAt = _optionalTimestamp(data['cancelled_at'], 'cancelled_at');
    final cancelledBy = _optionalActor(data['cancelled_by'], 'cancelled_by');
    final cancelReason = _optionalString(data['cancel_reason'], 'cancel_reason');

    try {
      return OperationalRestriction(
        id: restrictionId,
        dogId: dogId,
        level: level,
        category: category,
        description: description,
        issuedAt: issuedAt,
        recordedBy: recordedBy,
        professional: professional,
        sourceDocument: sourceDocument,
        status: status,
        schemaVersion: schemaVersion,
        activitiesRestricted: activities,
        expectedEnd: expectedEnd,
        actualEnd: actualEnd,
        endedBy: endedBy,
        endProfessional: endProfessional,
        endSourceDocument: endSourceDocument,
        endReason: endReason,
        cancelledAt: cancelledAt,
        cancelledBy: cancelledBy,
        cancelReason: cancelReason,
      );
    } on HealthDomainException catch (e) {
      // Invariante de domínio violada pelo documento persistido: recusa, nunca
      // agregado parcial ou terminal híbrido.
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        e.code,
        e.message,
      );
    }
  }

  // ── Identidade ────────────────────────────────────────────────────────────

  static void _assertIdentityIfPresent(
    Object? raw,
    String expected,
    String field,
  ) {
    if (raw == null) return;
    final value = raw is String ? raw.trim() : null;
    if (value == null || value.isEmpty || value != expected) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.identityMismatch,
        field,
        'documento divergente do path',
      );
    }
  }

  // ── Helpers fail-closed ───────────────────────────────────────────────────

  static String _requireString(Object? raw, String field) {
    final value = _optionalString(raw, field);
    if (value == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'ausente',
      );
    }
    return value;
  }

  /// Ausente => `null`. Presente mas não-textual ou vazio => recusa.
  static String? _optionalString(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is! String) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'tipo inválido',
      );
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'vazio',
      );
    }
    return trimmed;
  }

  static int _requireInt(Object? raw, String field) {
    if (raw is int) return raw;
    throw CanonicalRestrictionParseException(
      CanonicalRestrictionParseErrorCode.malformed,
      field,
      raw == null ? 'ausente' : 'tipo inválido',
    );
  }

  static T _requireEnum<T>(Object? raw, Map<String, T> byWire, String field) {
    final wire = _requireString(raw, field);
    final value = byWire[wire];
    if (value == null) {
      // Desconhecido NUNCA cai em `other`: `other` só é válido se o wire for
      // literalmente `other`.
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'valor fora do vocabulário canônico',
      );
    }
    return value;
  }

  /// Ausente/null => `null`. Presente mas malformado => recusa. Nunca `now()`,
  /// nunca epoch.
  ///
  /// Normalizado em UTC: o agregado é read model canônico e não deve depender do
  /// fuso do dispositivo. A conversão para hora local é responsabilidade
  /// explícita da formatação na UI (mesma convenção de
  /// `health_schedule_date_parse`).
  static DateTime? _optionalTimestamp(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate().toUtc();
    if (raw is DateTime) return raw.toUtc();
    throw CanonicalRestrictionParseException(
      CanonicalRestrictionParseErrorCode.malformed,
      field,
      'timestamp inválido',
    );
  }

  /// `activities_restricted` é campo canônico obrigatório: o writer sempre o
  /// persiste, mesmo quando vazio (Schema §2.11/§6). Ausência ou `null` é
  /// corrupção do documento, nunca vira lista vazia fabricada — "presente e
  /// vazio" é distinto de "inexistente". Uma vez presente, `[]` é válida para
  /// `absolute`/`attention`; o invariante que exige atividade em `partial` é
  /// do agregado, não deste parser.
  static List<String> _requireStringList(Object? raw, String field) {
    if (raw == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'ausente',
      );
    }
    if (raw is! List) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'tipo inválido',
      );
    }
    final out = <String>[];
    for (final item in raw) {
      if (item is! String) {
        throw CanonicalRestrictionParseException(
          CanonicalRestrictionParseErrorCode.malformed,
          field,
          'item não textual',
        );
      }
      final trimmed = item.trim();
      if (trimmed.isEmpty) {
        throw CanonicalRestrictionParseException(
          CanonicalRestrictionParseErrorCode.malformed,
          field,
          'item vazio',
        );
      }
      out.add(trimmed);
    }
    return out;
  }

  static Map<String, dynamic> _requireMap(Object? raw, String field) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw CanonicalRestrictionParseException(
      CanonicalRestrictionParseErrorCode.malformed,
      field,
      raw == null ? 'ausente' : 'tipo inválido',
    );
  }

  static RecordedBy _requireActor(Object? raw, String field) {
    final actor = _optionalActor(raw, field);
    if (actor == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'ausente',
      );
    }
    return actor;
  }

  /// Shape canônico de ator (`recordedByPayload` no backend): uid + name +
  /// internal_role, todos obrigatórios. Não é reduzido a String: `internal_role`
  /// é contrato necessário.
  static RecordedBy? _optionalActor(Object? raw, String field) {
    if (raw == null) return null;
    final map = _requireMap(raw, field);
    try {
      return RecordedBy(
        uid: _requireString(map['uid'], '$field.uid'),
        name: _requireString(map['name'], '$field.name'),
        internalRole: _requireString(
          map['internal_role'],
          '$field.internal_role',
        ),
      );
    } on HealthDomainException catch (e) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        e.message,
      );
    }
  }

  static ProfessionalIdentity _requireProfessional(Object? raw, String field) {
    final value = _optionalProfessional(raw, field);
    if (value == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'ausente',
      );
    }
    return value;
  }

  /// Shape canônico: `name`, `registration_type`, `registration_number`,
  /// `clinic` obrigatórios e `specialty` opcional. Vocabulário legado
  /// (`vetName`, `professionalCrmv`, `professionalClinic`, `register_number`)
  /// não é promovido — o writer o rejeita, o reader não o inventa.
  static ProfessionalIdentity? _optionalProfessional(
    Object? raw,
    String field,
  ) {
    if (raw == null) return null;
    final map = _requireMap(raw, field);
    final registrationTypeRaw = _requireString(
      map['registration_type'],
      '$field.registration_type',
    );
    final registrationType = ProfessionalRegistrationType.fromWire(
      registrationTypeRaw,
    );
    if (registrationType == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        '$field.registration_type',
        'valor fora do vocabulário canônico',
      );
    }
    try {
      return ProfessionalIdentity(
        name: _requireString(map['name'], '$field.name'),
        registrationType: registrationType,
        registrationNumber: _requireString(
          map['registration_number'],
          '$field.registration_number',
        ),
        clinic: _requireString(map['clinic'], '$field.clinic'),
        specialty: _optionalString(map['specialty'], '$field.specialty'),
      );
    } on HealthDomainException catch (e) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        e.message,
      );
    }
  }

  static HealthDocumentRef _requireDocumentRef(Object? raw, String field) {
    final value = _optionalDocumentRef(raw, field);
    if (value == null) {
      throw CanonicalRestrictionParseException(
        CanonicalRestrictionParseErrorCode.malformed,
        field,
        'ausente',
      );
    }
    return value;
  }

  /// Só identidade: `health_document_id` (+ `description` opcional). Storage
  /// path, URL e generation NÃO são resolvidos aqui — B4-B2 é read de detalhe,
  /// não visualização de documento.
  static HealthDocumentRef? _optionalDocumentRef(Object? raw, String field) {
    if (raw == null) return null;
    final map = _requireMap(raw, field);
    return HealthDocumentRef(
      healthDocumentId: _requireString(
        map['health_document_id'],
        '$field.health_document_id',
      ),
      description: _optionalString(map['description'], '$field.description'),
    );
  }
}
