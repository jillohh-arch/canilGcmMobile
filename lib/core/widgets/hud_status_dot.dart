import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/animation_constants.dart';

/// Indicador de status com pulso de radar.
/// Extraído de BinomioHeader para isolar o AnimationController.
class HudStatusDot extends StatefulWidget {
  /// Cor do dot e do pulso.
  final Color color;

  /// Tamanho do dot central (default: 8).
  final double size;

  /// Tamanho máximo do anel de pulso (default: 20).
  final double ringMaxSize;

  const HudStatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.ringMaxSize = 20,
  });

  @override
  State<HudStatusDot> createState() => _HudStatusDotState();
}

class _HudStatusDotState extends State<HudStatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _ringAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: HudDurations.pulse,
    );

    _ringAnimation = Tween<double>(begin: 1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    // Inicia o loop de pulso
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respeita preferência de movimento reduzido
    final animate = shouldAnimate(context);

    return SizedBox(
      width: widget.ringMaxSize,
      height: widget.ringMaxSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Anel de pulso (só aparece se animação está ativa)
          if (animate)
            AnimatedBuilder(
              animation: _ringAnimation,
              builder: (context, child) {
                final scale = _ringAnimation.value;
                // Opacidade: 0.45 → 0.0 conforme expande
                final opacity = (1.0 - (_ringAnimation.value - 1.0)) * 0.45;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color.withAlpha((opacity * 255).clamp(0, 255).toInt()),
                    ),
                  ),
                );
              },
            ),
          // Dot central fixo
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withAlpha(80),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
