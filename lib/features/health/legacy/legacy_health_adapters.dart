import '../domain/health_v1_enums.dart';
import '../domain/health_v1_models.dart';

enum LegacyIssueSeverity { warning, error }

enum LegacyParseState { success, partial, failure, absent }

final class LegacyParseIssue {
  const LegacyParseIssue({
    required this.code,
    required this.severity,
    required this.message,
    this.field,
  });

  final String code;
  final String? field;
  final LegacyIssueSeverity severity;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is LegacyParseIssue &&
      other.code == code &&
      other.field == field &&
      other.severity == severity &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, field, severity, message);
}

final class LegacyParseResult<T> {
  LegacyParseResult._(this.state, this.value, List<LegacyParseIssue> issues)
    : issues = List.unmodifiable(issues);

  factory LegacyParseResult.success(T value) =>
      LegacyParseResult._(LegacyParseState.success, value, const []);

  factory LegacyParseResult.partial(T value, List<LegacyParseIssue> issues) {
    if (issues.isEmpty ||
        issues.any((issue) => issue.severity == LegacyIssueSeverity.error)) {
      throw ArgumentError('partial exige ao menos um warning e nenhum erro');
    }
    return LegacyParseResult._(LegacyParseState.partial, value, issues);
  }

  factory LegacyParseResult.failure(List<LegacyParseIssue> issues) {
    if (issues.isEmpty ||
        !issues.any((issue) => issue.severity == LegacyIssueSeverity.error)) {
      throw ArgumentError('failure exige ao menos um erro');
    }
    return LegacyParseResult._(LegacyParseState.failure, null, issues);
  }

  factory LegacyParseResult.absent({String? field}) =>
      LegacyParseResult._(LegacyParseState.absent, null, [
        LegacyParseIssue(
          code: 'absent',
          field: field,
          severity: LegacyIssueSeverity.warning,
          message: 'Valor ausente',
        ),
      ]);

  final LegacyParseState state;
  final T? value;
  final List<LegacyParseIssue> issues;

  bool get isSuccess => state == LegacyParseState.success;
  bool get hasValue => value != null;
}

LegacyParseIssue _error(String code, String field, String message) =>
    LegacyParseIssue(
      code: code,
      field: field,
      severity: LegacyIssueSeverity.error,
      message: message,
    );

abstract final class LegacyDateParser {
  static LegacyParseResult<DateTime> parse(Object? value) {
    if (value == null) return LegacyParseResult.absent(field: 'date');
    if (value is DateTime) return LegacyParseResult.success(value);
    if (value is String) {
      if (value.trim().isEmpty) return LegacyParseResult.absent(field: 'date');
      final parsed = DateTime.tryParse(value);
      return parsed == null
          ? LegacyParseResult.failure([
              _error('invalid_iso', 'date', 'String ISO-8601 inválida'),
            ])
          : LegacyParseResult.success(parsed);
    }
    if (value is Map) return _parseTimestampMap(value);
    try {
      final converted = (value as dynamic).toDate();
      if (converted is! DateTime) {
        return LegacyParseResult.failure([
          _error(
            'timestamp_like_invalid_return',
            'date',
            'toDate() não retornou DateTime',
          ),
        ]);
      }
      return LegacyParseResult.success(converted);
    } on NoSuchMethodError {
      return LegacyParseResult.failure([
        _error(
          'timestamp_like_missing_method',
          'date',
          'Objeto não possui toDate() acessível',
        ),
      ]);
    } on Object {
      return LegacyParseResult.failure([
        _error(
          'timestamp_like_exception',
          'date',
          'toDate() lançou uma exceção',
        ),
      ]);
    }
  }

  static LegacyParseResult<DateTime> _parseTimestampMap(Map value) {
    final seconds = value.containsKey('seconds')
        ? value['seconds']
        : value['_seconds'];
    final nanos = value.containsKey('nanoseconds')
        ? value['nanoseconds']
        : value['_nanoseconds'] ?? 0;
    if (!_isInteger(seconds) || !_isInteger(nanos)) {
      return LegacyParseResult.failure([
        _error(
          'invalid_timestamp_number',
          'date',
          'seconds e nanoseconds devem ser inteiros finitos',
        ),
      ]);
    }
    final secondsInt = (seconds as num).toInt();
    final nanosInt = (nanos as num).toInt();
    if (nanosInt < 0 || nanosInt > 999999999) {
      return LegacyParseResult.failure([
        _error(
          'invalid_nanoseconds',
          'date',
          'nanoseconds fora do intervalo permitido',
        ),
      ]);
    }
    try {
      final micros =
          BigInt.from(secondsInt) * BigInt.from(1000000) +
          BigInt.from(nanosInt ~/ 1000);
      if (!micros.isValidInt) {
        return LegacyParseResult.failure([
          _error('timestamp_out_of_range', 'date', 'Timestamp fora do alcance'),
        ]);
      }
      return LegacyParseResult.success(
        DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true),
      );
    } on Object {
      return LegacyParseResult.failure([
        _error('timestamp_out_of_range', 'date', 'Timestamp fora do alcance'),
      ]);
    }
  }

  static bool _isInteger(Object? value) =>
      value is num && value.isFinite && value == value.truncateToDouble();
}

abstract final class _LegacyFields {
  static String? nonEmptyString(Map<String, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static num? number(Map<String, Object?> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is num) return value;
      if (value is String) {
        final parsed = num.tryParse(value.replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static RecordedBy? recordedBy(Map<String, Object?> data) {
    final raw = data['recorded_by'];
    if (raw is! Map) return null;
    final uid = raw['uid'];
    final name = raw['name'];
    final role = raw['internal_role'];
    if (uid is! String || name is! String || role is! String) return null;
    try {
      return RecordedBy(uid: uid, name: name, internalRole: role);
    } on HealthDomainException {
      return null;
    }
  }
}

Map<String, Object?> _withCanonicalDate(
  Map<String, Object?> data,
  Iterable<String> candidateFields,
  DateTime parsed,
) {
  final copy = Map<String, Object?>.from(data);
  for (final field in candidateFields) {
    if (copy.containsKey(field)) {
      copy[field] = parsed;
      break;
    }
  }
  return copy;
}

/// Adapter pré-backfill de `health_events`; nunca produz ClinicalEvent.
final class RawHealthEventsAdapter {
  const RawHealthEventsAdapter();

  LegacyParseResult<LegacyHealthRecordView> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final issues = <LegacyParseIssue>[];
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }
    final date = LegacyDateParser.parse(data['date'] ?? data['created_at']);
    if (!date.hasValue) {
      issues.add(_error(date.issues.first.code, 'date', 'Data inválida'));
    }
    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);

    final rawType = _LegacyFields.nonEmptyString(data, ['type', 'logType']);
    final description = _LegacyFields.nonEmptyString(data, [
      'healthObservations',
    ]);
    final warnings = <LegacyParseIssue>[];
    if (rawType == null) {
      warnings.add(
        const LegacyParseIssue(
          code: 'missing_type',
          field: 'type',
          severity: LegacyIssueSeverity.warning,
          message: 'Tipo legado ausente; nenhum default foi aplicado',
        ),
      );
    }
    try {
      final view = LegacyHealthRecordView(
        sourceId: sourceId,
        dogId: dogId,
        occurredAt: date.value!,
        typeRaw: rawType ?? '',
        description: description ?? '',
        originalPayload: _withCanonicalDate(data, const [
          'date',
          'created_at',
        ], date.value!),
      );
      return warnings.isEmpty
          ? LegacyParseResult.success(view)
          : LegacyParseResult.partial(view, warnings);
    } on HealthDomainException {
      return LegacyParseResult.failure([
        _error('invalid_payload', 'original_payload', 'Payload incompatível'),
      ]);
    }
  }
}

final class LegacyWeightAdapter {
  const LegacyWeightAdapter();

  LegacyParseResult<Object> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final issues = <LegacyParseIssue>[];
    final weight = _LegacyFields.number(data, ['weight_kg']);
    final measuredAt = LegacyDateParser.parse(
      data['measured_at'] ?? data['created_at'],
    );
    final actor = _LegacyFields.recordedBy(data);
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }
    if (weight == null || !weight.toDouble().isFinite || weight <= 0) {
      issues.add(_error('invalid_number', 'weight_kg', 'Peso inválido'));
    }
    if (!measuredAt.hasValue) {
      issues.add(
        _error(measuredAt.issues.first.code, 'measured_at', 'Data inválida'),
      );
    }
    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);
    if (actor == null) {
      final legacyAuthor = _LegacyFields.nonEmptyString(data, ['measured_by']);
      return LegacyParseResult.partial(
        LegacyHealthRecordView(
          sourceId: sourceId,
          dogId: dogId,
          occurredAt: measuredAt.value!,
          typeRaw: 'weight',
          description: '',
          originalPayload: _withCanonicalDate(data, const [
            'measured_at',
            'created_at',
          ], measuredAt.value!),
        ),
        [
          LegacyParseIssue(
            code: 'incomplete_legacy_author',
            field: legacyAuthor == null ? 'recorded_by' : 'measured_by',
            severity: LegacyIssueSeverity.warning,
            message: 'Autoria legada insuficiente para RecordedBy canônico',
          ),
        ],
      );
    }
    return LegacyParseResult.success(
      WeightAssessment(
        id: sourceId,
        dogId: dogId,
        weight: WeightKg(weight!),
        measuredAt: measuredAt.value!,
        recordedBy: actor,
        schemaVersion: 1,
      ),
    );
  }
}

final class LegacyNutritionAdapter {
  const LegacyNutritionAdapter();

  LegacyParseResult<Object> parse({
    required String sourceId,
    required String dogId,
    required Map<String, Object?> data,
  }) {
    final issues = <LegacyParseIssue>[];
    final amount = _LegacyFields.number(data, ['amount_grams']);
    final fedAt = LegacyDateParser.parse(data['fed_at'] ?? data['created_at']);
    final period = MealPeriodWire.parseLegacy(data['period']);
    final actor = _LegacyFields.recordedBy(data);
    if (sourceId.trim().isEmpty) {
      issues.add(_error('missing', 'source_id', 'Identificador ausente'));
    }
    if (dogId.trim().isEmpty) {
      issues.add(_error('missing', 'dog_id', 'K9 ausente'));
    }
    if (period.isAbsent) {
      issues.add(_error('missing', 'period', 'Período ausente'));
    }
    if (amount == null || !amount.toDouble().isFinite || amount <= 0) {
      issues.add(
        _error('invalid_number', 'amount_grams', 'Quantidade inválida'),
      );
    }
    if (!fedAt.hasValue) {
      issues.add(_error(fedAt.issues.first.code, 'fed_at', 'Data inválida'));
    }
    if (issues.isNotEmpty) return LegacyParseResult.failure(issues);
    if (actor == null) {
      final legacyAuthor = _LegacyFields.nonEmptyString(data, ['fed_by']);
      final warnings = <LegacyParseIssue>[
        LegacyParseIssue(
          code: 'incomplete_legacy_author',
          field: legacyAuthor == null ? 'recorded_by' : 'fed_by',
          severity: LegacyIssueSeverity.warning,
          message: 'Autoria legada insuficiente para RecordedBy canônico',
        ),
      ];
      if (period.isUnknown) {
        warnings.add(
          const LegacyParseIssue(
            code: 'unknown_period',
            field: 'period',
            severity: LegacyIssueSeverity.warning,
            message: 'Período legado desconhecido preservado',
          ),
        );
      }
      return LegacyParseResult.partial(
        LegacyHealthRecordView(
          sourceId: sourceId,
          dogId: dogId,
          occurredAt: fedAt.value!,
          typeRaw: 'meal',
          description: '',
          originalPayload: _withCanonicalDate(data, const [
            'fed_at',
            'created_at',
          ], fedAt.value!),
        ),
        warnings,
      );
    }
    final meal = MealLog(
      id: sourceId,
      dogId: dogId,
      period: period,
      amountGrams: amount!,
      fedAt: fedAt.value!,
      recordedBy: actor,
      schemaVersion: 1,
    );
    if (period.isUnknown) {
      return LegacyParseResult.partial(meal, [
        const LegacyParseIssue(
          code: 'unknown_period',
          field: 'period',
          severity: LegacyIssueSeverity.warning,
          message: 'Período legado desconhecido preservado',
        ),
      ]);
    }
    return LegacyParseResult.success(meal);
  }
}
