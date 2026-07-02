import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/animation_constants.dart';

/// Contador animado com contagem progressiva (count-up).
///
/// Na primeira exibição (primeira construção): conta de 0 → valor final,
/// sincronizado com a animação de entrada da seção.
/// Em atualizações: anima do valor anterior → novo (sem reset para 0).
class HudAnimatedCount extends StatefulWidget {
  /// Valor a ser exibido.
  final int value;

  /// Sufixo opcional após o número (ex: 'd' para dias, 'h' para horas).
  final String? suffix;

  /// Estilo do texto. Se null, usa padrão HUD.
  final TextStyle? style;

  /// Controlador opcional para sincronizar com animação da seção pai.
  /// Quando fornecido, a contagem inicia conforme o progress do controller.
  /// Se null, usa TweenAnimationBuilder standalone com delay.
  final Animation<double>? sectionAnimation;

  /// Intervalo do controller onde o contador deve iniciar (default: 0.0).
  final double intervalStart;

  /// Intervalo do controller onde o contador deve completar (default: 1.0).
  final double intervalEnd;

  const HudAnimatedCount({
    super.key,
    required this.value,
    this.suffix,
    this.style,
    this.sectionAnimation,
    this.intervalStart = 0.0,
    this.intervalEnd = 1.0,
  });

  @override
  State<HudAnimatedCount> createState() => _HudAnimatedCountState();
}

class _HudAnimatedCountState extends State<HudAnimatedCount> {
  int _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = 0;
  }

  @override
  void didUpdateWidget(HudAnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = !shouldAnimate(context);

    if (reduceMotion) {
      return Text(
        '${widget.value}${widget.suffix ?? ''}',
        style: widget.style,
      );
    }

    // Se tem controller de seção, anima sincronizado
    if (widget.sectionAnimation != null) {
      return AnimatedBuilder(
        animation: widget.sectionAnimation!,
        builder: (context, _) {
          final interval = Interval(
            widget.intervalStart,
            widget.intervalEnd,
            curve: HudCurves.enter,
          );
          final progress = interval.transform(
            widget.sectionAnimation!.value.clamp(widget.intervalStart, widget.intervalEnd),
          );

          // Calcula valor interpolado
          final current = (_previousValue + (widget.value - _previousValue) * progress).round();

          return Text(
            '$current${widget.suffix ?? ''}',
            style: widget.style,
          );
        },
      );
    }

    // Sem controller: usa TweenAnimationBuilder standalone com delay
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: _previousValue, end: widget.value),
      duration: HudDurations.entry,
      curve: HudCurves.enter,
      builder: (context, value, child) {
        return Text(
          '$value${widget.suffix ?? ''}',
          style: widget.style,
        );
      },
    );
  }
}
