import 'package:flutter/material.dart';

/// Design tokens de animação para a identidade HUD tática.
/// Movimento rápido, curvas secas — feedback operacional, não decoração.
class HudDurations {
  const HudDurations._();

  /// 80ms — passo de stagger entre elementos.
  static const Duration stagger = Duration(milliseconds: 80);

  /// 120ms — feedback de press/tap em botões e cards.
  static const Duration tap = Duration(milliseconds: 120);

  /// 160ms — chips, seleção de itens em lista.
  static const Duration fast = Duration(milliseconds: 160);

  /// 220ms — switch de conteúdo interno (steps, tabs).
  static const Duration normal = Duration(milliseconds: 220);

  /// 300ms — entrada de elementos na tela.
  static const Duration entry = Duration(milliseconds: 300);

  /// 450ms — transições mais elaboradas.
  static const Duration slow = Duration(milliseconds: 450);

  /// 1600ms — ciclo de pulso de radar/status.
  static const Duration pulse = Duration(milliseconds: 1600);
}

/// Curvas secas sem overshoot — identidade militar.
class HudCurves {
  const HudCurves._();

  /// Entrada de elementos novos na tela.
  static const Curve enter = Curves.easeOutCubic;

  /// Saída de elementos que saem da tela.
  static const Curve exit = Curves.easeInCubic;

  /// Entrada e saída suave (toggle, fade).
  static const Curve move = Curves.easeInOutCubic;

  /// Resposta rápida e seca — preferido para micro-interações.
  static const Curve snappy = Curves.easeOutQuart;

  /// Curva padrão para AnimatedContainer/AnimatedSwitcher.
  static const Curve standard = Curves.easeOutCubic;
}

/// Delay progressivo para animações stagger.
Duration staggerDelay(int index, {int baseMs = 60}) {
  return Duration(milliseconds: baseMs * index);
}

/// Helper de acessibilidade: respeita preferência de movimento reduzido.
bool shouldAnimate(BuildContext context) {
  return MediaQuery.of(context).disableAnimations != true;
}
