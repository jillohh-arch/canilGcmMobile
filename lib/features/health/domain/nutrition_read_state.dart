// ─────────────────────────────────────────────────────────────────────────────
// Read states explícitos de Nutrição (D28 / §28–§29).
// ERRO NÃO VIRA EMPTY. degraded = dados parciais + diagnóstico.
// ─────────────────────────────────────────────────────────────────────────────

/// Vocabulário alinhado ao Health v1 + `degraded` para dual-read parcial.
enum NutritionReadStatus {
  loading,
  data,
  empty,
  degraded,
  offline,
  error,
}

/// Envelope de leitura tipado.
///
/// - [data] / [degraded]: podem carregar [value]
/// - [empty] / [error] / [offline] / [loading]: sem value utilizável como sucesso pleno
final class NutritionReadResult<T> {
  const NutritionReadResult._({
    required this.status,
    this.value,
    this.message,
    this.code,
  });

  const NutritionReadResult.loading({String? message})
    : this._(status: NutritionReadStatus.loading, message: message);

  const NutritionReadResult.data(T value)
    : this._(status: NutritionReadStatus.data, value: value);

  /// Dados utilizáveis com falha parcial de outra fonte.
  const NutritionReadResult.degraded(T value, {String? message, String? code})
    : this._(
        status: NutritionReadStatus.degraded,
        value: value,
        message: message,
        code: code,
      );

  const NutritionReadResult.empty({String? message})
    : this._(status: NutritionReadStatus.empty, message: message);

  const NutritionReadResult.offline({String? message, String? code})
    : this._(status: NutritionReadStatus.offline, message: message, code: code);

  const NutritionReadResult.error({String? message, String? code})
    : this._(status: NutritionReadStatus.error, message: message, code: code);

  final NutritionReadStatus status;
  final T? value;
  final String? message;
  final String? code;

  bool get isData => status == NutritionReadStatus.data;
  bool get isDegraded => status == NutritionReadStatus.degraded;
  bool get isEmpty => status == NutritionReadStatus.empty;
  bool get isError => status == NutritionReadStatus.error;
  bool get isOffline => status == NutritionReadStatus.offline;
  bool get isLoading => status == NutritionReadStatus.loading;

  /// Dados utilizáveis (plenos ou degradados).
  bool get hasUsableValue =>
      (isData || isDegraded) && value != null;

  T? get valueOrNull => hasUsableValue ? value : null;

  @override
  bool operator ==(Object other) =>
      other is NutritionReadResult<T> &&
      other.status == status &&
      other.value == value &&
      other.message == message &&
      other.code == code;

  @override
  int get hashCode => Object.hash(status, value, message, code);
}

/// Origem de item mesclado.
enum NutritionDataOrigin {
  canonical,
  legacy,

  /// `feeding_events` (primária operacional legada).
  legacyFeedingEvents,

  /// `feedings` (espelho).
  legacyFeedings,
}

/// Disponibilidade de uma fonte dual-read.
enum NutritionSourceAvailability {
  available,
  empty,
  offline,
  error,
  notConfigured,
}

final class NutritionSourceStatus {
  const NutritionSourceStatus({
    required this.origin,
    required this.availability,
    this.message,
    this.code,
    this.sourceKey,
  });

  final NutritionDataOrigin origin;
  final NutritionSourceAvailability availability;
  final String? message;
  final String? code;

  /// Chave estável da fonte (ex.: `feeding_events`, `meal_logs`).
  final String? sourceKey;

  bool get isUsable =>
      availability == NutritionSourceAvailability.available ||
      availability == NutritionSourceAvailability.empty;

  bool get isFailure =>
      availability == NutritionSourceAvailability.error ||
      availability == NutritionSourceAvailability.offline;

  @override
  bool operator ==(Object other) =>
      other is NutritionSourceStatus &&
      other.origin == origin &&
      other.availability == availability &&
      other.message == message &&
      other.code == code &&
      other.sourceKey == sourceKey;

  @override
  int get hashCode =>
      Object.hash(origin, availability, message, code, sourceKey);
}

/// Diagnóstico de merge/dedupe (warnings determinísticos).
final class NutritionMergeDiagnostic {
  const NutritionMergeDiagnostic({
    required this.code,
    required this.message,
    this.primaryKey,
    this.secondaryKey,
  });

  final String code;
  final String message;
  final String? primaryKey;
  final String? secondaryKey;

  @override
  bool operator ==(Object other) =>
      other is NutritionMergeDiagnostic &&
      other.code == code &&
      other.message == message &&
      other.primaryKey == primaryKey &&
      other.secondaryKey == secondaryKey;

  @override
  int get hashCode => Object.hash(code, message, primaryKey, secondaryKey);
}
