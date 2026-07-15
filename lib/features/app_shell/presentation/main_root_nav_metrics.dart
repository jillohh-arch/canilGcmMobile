/// Métricas compartilhadas da bottom navigation do [MainRootScreen].
///
/// Fonte única para altura da barra e folga de scroll (Health e demais
/// superfícies com `extendBody: true`).
abstract final class MainRootNavMetrics {
  MainRootNavMetrics._();

  /// Altura do conteúdo da barra (sem safe area do sistema).
  /// Espelha o `SizedBox(height: 76 + padding.bottom)` em main_root_actions.
  static const double barContentHeight = 76;

  /// Elevação do FAB “Nova” acima do topo da barra.
  static const double fabElevation = 22;

  /// Folga extra no scroll para o último conteúdo ficar legível sob o FAB.
  static const double scrollFabBreathing = 28;

  /// Clearance total do scroll = bar + system bottom inset + folga FAB.
  static double scrollBottomClearance({required double systemBottomInset}) {
    return barContentHeight + systemBottomInset + scrollFabBreathing;
  }
}
