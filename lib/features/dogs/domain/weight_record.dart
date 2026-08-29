import 'package:cloud_firestore/cloud_firestore.dart';

final class WeightRecordedBy {
  const WeightRecordedBy({
    required this.uid,
    required this.name,
    required this.internalRole,
  });

  final String uid;
  final String name;
  final String internalRole;

  factory WeightRecordedBy.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('recorded_by ausente ou inválido.');
    }
    final raw = Map<String, dynamic>.from(value);
    final uid = raw['uid'];
    final name = raw['name'];
    final role = raw['internal_role'];
    if (uid is! String ||
        uid.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        role is! String ||
        !const {'condutor', 'admin'}.contains(role.trim())) {
      throw const FormatException('recorded_by incompleto ou não canônico.');
    }
    return WeightRecordedBy(
      uid: uid.trim(),
      name: name.trim(),
      internalRole: role.trim(),
    );
  }
}

/// Leitura canônica de `dogs/{dogId}/weight_records/{entityId}`.
final class WeightRecord {
  const WeightRecord({
    required this.id,
    required this.weightKg,
    required this.measuredAt,
    required this.recordedBy,
    this.schemaVersion = 1,
    this.context = '',
    this.notes,
    this.recordedAt,
  });

  final String id;
  final double weightKg;
  final DateTime measuredAt;

  /// Instante em que a pesagem foi REGISTRADA, distinto de [measuredAt] (o
  /// instante medido). Participa do desempate canônico quando duas pesagens
  /// compartilham `measuredAt`.
  ///
  /// `null` em registros v1/legados que não persistem `recorded_at`; ausência é
  /// factual e não é substituída por `measuredAt` nem por `created_at`.
  final DateTime? recordedAt;

  /// Autoria canônica. Ausente (`null`) em pesagens legadas reconhecidas que
  /// não possuem `recorder`: a leitura é permitida, mas a autoria não é
  /// inventada nem derivada de `legacyActorReference` / RA.
  final WeightRecordedBy? recordedBy;
  final int schemaVersion;
  final String context;
  final String? notes;

  String? get contextLabel => switch (context) {
    'routine' => 'Rotina',
    'clinical' => 'Clínica',
    'pre_op' => 'Pré-operacional',
    'post_op' => 'Pós-operacional',
    _ => null,
  };

  /// Compatibilidade somente de apresentação para consumidores existentes.
  /// String vazia quando não há autoria factual (legado sem `recorder`).
  String get measuredBy => recordedBy?.name ?? '';

  /// O contrato canônico de Pesagem desta fase não possui foto.
  String? get photoUrl => null;

  factory WeightRecord.fromJson(Map<String, dynamic> json, {String? docId}) {
    final id = (docId ?? json['id'])?.toString().trim() ?? '';
    final weight = json['weight_kg'];
    final measuredAt = _toDateTime(json['measured_at']);
    final schemaVersion = json['schema_version'];
    if (id.isEmpty ||
        weight is! num ||
        !weight.toDouble().isFinite ||
        weight <= 0 ||
        weight > 100 ||
        measuredAt == null ||
        schemaVersion is! int ||
        schemaVersion != 1) {
      throw const FormatException('WeightRecord canônico inválido.');
    }
    final context = _optionalString(json['context']);
    if (context != null &&
        !const {'routine', 'clinical', 'pre_op', 'post_op'}.contains(context)) {
      throw const FormatException('context de WeightRecord não canônico.');
    }
    return WeightRecord(
      id: id,
      weightKg: weight.toDouble(),
      measuredAt: measuredAt,
      recordedBy: WeightRecordedBy.fromJson(json['recorded_by']),
      schemaVersion: schemaVersion,
      context: context ?? '',
      notes: _optionalString(json['notes']),
      // `recordedAt` NÃO é lido aqui de propósito: esta rota exige
      // `schema_version == 1`, e o parser canônico classifica
      // `schema_version: 1` + `recorded_at` como `hybridV1V2` → malformed
      // (`recorded_at` pertence a `_targetFields`). Parsear o campo aqui
      // ensinaria a façade a aceitar como V1 válido um documento que a
      // autoridade rejeita. O campo é preenchido pela rota de runtime real:
      // `WeightAssessmentReadAdapter._toRecord`.
    );
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Campo textual inválido.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
