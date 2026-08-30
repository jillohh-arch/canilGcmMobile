/// Metadados de origem e freshness para o Resumo.
///
/// A 2B **transporta** a informação; não aplica thresholds operacionais
/// (ex.: 5 min / 12 h) como decisão de prontidão ou aptidão.
final class HealthSummarySourceMetadata {
  const HealthSummarySourceMetadata({
    this.updatedAt,
    this.isFromCache = false,
    this.isOffline = false,
    this.isStale = false,
  });

  /// Última atualização conhecida do conjunto de leitura.
  final DateTime? updatedAt;

  /// Indica origem em cache local/projeção, se a fonte informar.
  final bool isFromCache;

  /// Dispositivo ou fonte reportou condição offline.
  final bool isOffline;

  /// Freshness degradada conforme a fonte (não recalculada clinicamente).
  final bool isStale;

  @override
  bool operator ==(Object other) =>
      other is HealthSummarySourceMetadata &&
      other.updatedAt == updatedAt &&
      other.isFromCache == isFromCache &&
      other.isOffline == isOffline &&
      other.isStale == isStale;

  @override
  int get hashCode => Object.hash(updatedAt, isFromCache, isOffline, isStale);
}
