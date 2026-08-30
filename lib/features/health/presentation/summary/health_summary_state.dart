import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

/// Estados do ciclo de vida do Resumo.
///
/// Distinções:
/// - [HealthSummaryEmpty]: a fonte não produziu read model utilizável.
/// - `ReadinessStatus.notEvaluated` **não** implica empty do Dashboard
///   (pode haver outros blocos com dados).
/// - [HealthSummaryOffline] ≠ [HealthSummaryError].
sealed class HealthSummaryState {
  const HealthSummaryState();

  /// dogId ao qual o estado se refere, quando aplicável.
  String? get dogId;
}

/// Nenhum K9 selecionado ainda.
final class HealthSummaryInitial extends HealthSummaryState {
  const HealthSummaryInitial();

  @override
  String? get dogId => null;

  @override
  bool operator ==(Object other) => other is HealthSummaryInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Carregando o Resumo do [dogId].
final class HealthSummaryLoading extends HealthSummaryState {
  const HealthSummaryLoading({required this.dogId});

  @override
  final String dogId;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryLoading && other.dogId == dogId;

  @override
  int get hashCode => Object.hash(runtimeType, dogId);
}

/// Read model utilizável (pode conter blocos parciais).
final class HealthSummaryData extends HealthSummaryState {
  const HealthSummaryData({required this.data});

  final HealthSummaryViewData data;

  @override
  String get dogId => data.dogId;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryData && other.data == data;

  @override
  int get hashCode => Object.hash(runtimeType, data);
}

/// Fonte respondeu sem read model utilizável para o [dogId].
///
/// Não confundir com prontidão `not_evaluated`.
final class HealthSummaryEmpty extends HealthSummaryState {
  const HealthSummaryEmpty({required this.dogId});

  @override
  final String dogId;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryEmpty && other.dogId == dogId;

  @override
  int get hashCode => Object.hash(runtimeType, dogId);
}

/// Falha de leitura no canal do [dogId].
///
/// [lastKnownData], se presente, é sempre do **mesmo** [dogId] e não altera
/// a prontidão embutida — a UI pode exibir último conhecido + erro.
final class HealthSummaryError extends HealthSummaryState {
  const HealthSummaryError({
    required this.dogId,
    required this.message,
    this.lastKnownData,
  });

  @override
  final String dogId;
  final String message;

  /// Snapshot prévio do mesmo dogId, se houver.
  final HealthSummaryViewData? lastKnownData;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryError &&
      other.dogId == dogId &&
      other.message == message &&
      other.lastKnownData == lastKnownData;

  @override
  int get hashCode => Object.hash(runtimeType, dogId, message, lastKnownData);
}

/// Offline; pode carregar [cachedData] do mesmo [dogId] se existir.
///
/// Não altera a prontidão recebida nos dados em cache.
final class HealthSummaryOffline extends HealthSummaryState {
  const HealthSummaryOffline({required this.dogId, this.cachedData});

  @override
  final String dogId;

  /// Dados prévios do mesmo dogId, se disponíveis.
  final HealthSummaryViewData? cachedData;

  @override
  bool operator ==(Object other) =>
      other is HealthSummaryOffline &&
      other.dogId == dogId &&
      other.cachedData == cachedData;

  @override
  int get hashCode => Object.hash(runtimeType, dogId, cachedData);
}
