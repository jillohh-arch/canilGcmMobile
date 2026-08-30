/// Modo de operação da timeline Health v1.0.
enum HealthTimelineMode {
  legacyOnly,
  shadowCompare,
  canonicalPrimary;

  /// Retorna a representação textual oficial (wire value).
  String get wireValue => name;
}

/// Natureza do resultado da resolução do modo da timeline.
enum HealthTimelineModeResolutionKind {
  configured,
  missingDefault,
  invalidDefault,
}

/// Objeto de valor imutável representando o resultado da resolução da flag.
final class HealthTimelineModeResolution {
  const HealthTimelineModeResolution({required this.mode, required this.kind});

  final HealthTimelineMode mode;
  final HealthTimelineModeResolutionKind kind;

  /// Indica se a resolução precisou recorrer ao valor padrão seguro (legacyOnly).
  bool get wasDefaulted => kind != HealthTimelineModeResolutionKind.configured;

  /// Analisa uma string bruta e resolve o modo de forma defensiva e fail-closed.
  static HealthTimelineModeResolution parse(String? rawInput) {
    if (rawInput == null) {
      return const HealthTimelineModeResolution(
        mode: HealthTimelineMode.legacyOnly,
        kind: HealthTimelineModeResolutionKind.missingDefault,
      );
    }

    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return const HealthTimelineModeResolution(
        mode: HealthTimelineMode.legacyOnly,
        kind: HealthTimelineModeResolutionKind.missingDefault,
      );
    }

    switch (trimmed) {
      case 'legacyOnly':
        return const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.configured,
        );
      case 'shadowCompare':
        return const HealthTimelineModeResolution(
          mode: HealthTimelineMode.shadowCompare,
          kind: HealthTimelineModeResolutionKind.configured,
        );
      case 'canonicalPrimary':
        return const HealthTimelineModeResolution(
          mode: HealthTimelineMode.canonicalPrimary,
          kind: HealthTimelineModeResolutionKind.configured,
        );
      default:
        return const HealthTimelineModeResolution(
          mode: HealthTimelineMode.legacyOnly,
          kind: HealthTimelineModeResolutionKind.invalidDefault,
        );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HealthTimelineModeResolution &&
        other.mode == mode &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(mode, kind);

  @override
  String toString() => 'HealthTimelineModeResolution(mode: $mode, kind: $kind)';
}
