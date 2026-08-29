/// Situação de um bloco individual do Resumo Health v1.
///
/// Distinções obrigatórias:
/// - [notRecorded]: a fonte respondeu e não há registro (ex.: nenhuma vacina).
/// - [unavailable]: a fonte falhou ou o bloco não pôde ser consultado.
///
/// É proibido tratar [unavailable] como lista vazia ou "nenhuma pendência".
enum HealthSummarySectionStatus {
  /// Bloco ainda sendo resolvido (pode coexistir com outros available).
  loading,

  /// Valor de apresentação disponível.
  available,

  /// Ausência legítima de registro (não é falha).
  notRecorded,

  /// Falha ou impossibilidade de obter o bloco.
  unavailable,
}

/// Envelope tipado para um bloco do Resumo.
///
/// Construção **somente** via factories. [value] só existe em [available].
/// Estados impossíveis (available sem value; loading/notRecorded/unavailable
/// com value) não são expressáveis pela API pública.
final class HealthSummarySectionData<T> {
  const HealthSummarySectionData._({
    required this.status,
    this.value,
    this.message,
    this.isDegraded = false,
  });

  const HealthSummarySectionData.loading({String? message})
    : this._(status: HealthSummarySectionStatus.loading, message: message);

  /// Requer [value] presente (para `T` não-nulo, o compilador já impede null).
  const HealthSummarySectionData.available(T value)
    : this._(status: HealthSummarySectionStatus.available, value: value);

  /// Valor seguro preservado com diagnóstico de falha parcial.
  ///
  /// O status continua [HealthSummarySectionStatus.available] porque o bloco
  /// possui valor apresentável, mas [isDegraded] impede que ele seja tratado
  /// como uma leitura completamente saudável.
  const HealthSummarySectionData.degraded(T value, {required String message})
    : this._(
        status: HealthSummarySectionStatus.available,
        value: value,
        message: message,
        isDegraded: true,
      );

  const HealthSummarySectionData.notRecorded({String? message})
    : this._(status: HealthSummarySectionStatus.notRecorded, message: message);

  const HealthSummarySectionData.unavailable({String? message})
    : this._(status: HealthSummarySectionStatus.unavailable, message: message);

  final HealthSummarySectionStatus status;
  final T? value;
  final String? message;
  final bool isDegraded;

  bool get isAvailable => status == HealthSummarySectionStatus.available;
  bool get isLoading => status == HealthSummarySectionStatus.loading;
  bool get isNotRecorded => status == HealthSummarySectionStatus.notRecorded;
  bool get isUnavailable => status == HealthSummarySectionStatus.unavailable;

  /// Valor quando [isAvailable]; caso contrário `null`.
  T? get valueOrNull => isAvailable ? value : null;

  @override
  bool operator ==(Object other) =>
      other is HealthSummarySectionData<T> &&
      other.status == status &&
      other.value == value &&
      other.message == message &&
      other.isDegraded == isDegraded;

  @override
  int get hashCode => Object.hash(status, value, message, isDegraded);
}
