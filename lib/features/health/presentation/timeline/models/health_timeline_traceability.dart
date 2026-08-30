/// Metadados de rastreabilidade canônico/legado para uma entrada de timeline.
///
/// Todos os campos são opcionais: legados e canônicos compartilham o mesmo
/// contrato visual. Nada é exibido nesta fase.
final class HealthTimelineTraceability {
  const HealthTimelineTraceability({
    this.sourceCollection,
    this.sourceId,
    this.legacySource,
    this.legacyId,
  });

  final String? sourceCollection;
  final String? sourceId;
  final String? legacySource;
  final String? legacyId;

  bool get hasCanonicalSource =>
      (sourceCollection != null && sourceCollection!.isNotEmpty) ||
      (sourceId != null && sourceId!.isNotEmpty);

  bool get hasLegacySource =>
      (legacySource != null && legacySource!.isNotEmpty) ||
      (legacyId != null && legacyId!.isNotEmpty);

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineTraceability &&
      other.sourceCollection == sourceCollection &&
      other.sourceId == sourceId &&
      other.legacySource == legacySource &&
      other.legacyId == legacyId;

  @override
  int get hashCode =>
      Object.hash(sourceCollection, sourceId, legacySource, legacyId);
}
