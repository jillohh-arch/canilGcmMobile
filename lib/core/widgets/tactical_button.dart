import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:canil_gcm/core/theme/animation_constants.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';

/// Variantes visuais do TacticalButton.
enum TacticalButtonVariant {
  /// Cyan — ações primárias.
  primary,
  /// Verde — confirmação, iniciar.
  success,
  /// Vermelho — ação destrutiva/crítica.
  danger,
  /// Borda — ação secundária.
  outline,
}

/// Botão com press feedback tático (scale 1.0 → 0.97).
///
/// Baseado no estilo visual dos ElevatedButton existentes no codebase.
class TacticalButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TacticalButtonVariant variant;
  final bool loading;

  const TacticalButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.variant = TacticalButtonVariant.primary,
    this.loading = false,
  });

  @override
  State<TacticalButton> createState() => _TacticalButtonState();
}

class _TacticalButtonState extends State<TacticalButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: HudDurations.tap,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: HudCurves.enter,
        reverseCurve: HudCurves.exit,
      ),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.loading) {
      _scaleController.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _onTapCancel() {
    _scaleController.reverse();
  }

  // ── Cores por variante ────────────────────────────────────────

  Color get _bgColor {
    switch (widget.variant) {
      case TacticalButtonVariant.primary:
        return AppTheme.primary;
      case TacticalButtonVariant.success:
        return AppTheme.success;
      case TacticalButtonVariant.danger:
        return AppTheme.error;
      case TacticalButtonVariant.outline:
        return Colors.transparent;
    }
  }

  Color get _fgColor {
    switch (widget.variant) {
      case TacticalButtonVariant.primary:
      case TacticalButtonVariant.success:
      case TacticalButtonVariant.danger:
        return AppTheme.background;
      case TacticalButtonVariant.outline:
        return AppTheme.primary;
    }
  }

  Color get _borderColor {
    switch (widget.variant) {
      case TacticalButtonVariant.primary:
        return AppTheme.primary;
      case TacticalButtonVariant.success:
        return AppTheme.success;
      case TacticalButtonVariant.danger:
        return AppTheme.error;
      case TacticalButtonVariant.outline:
        return AppTheme.primary.withAlpha(130);
    }
  }

  BoxBorder? get _border {
    if (widget.variant == TacticalButtonVariant.outline) {
      return Border.all(color: _borderColor, width: 1.5);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null || widget.loading;
    final reduceMotion = !shouldAnimate(context);

    Widget content() {
      return AnimatedSwitcher(
        duration: HudDurations.fast,
        child: widget.loading
            ? SizedBox(
                key: const ValueKey('loading'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _fgColor,
                ),
              )
            : Row(
                key: const ValueKey('label'),
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: _fgColor),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDisabled ? _fgColor.withAlpha(150) : _fgColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
      );
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: isDisabled
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onPressed?.call();
            },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          final scale = reduceMotion ? 1.0 : _scaleAnimation.value;
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: HudDurations.fast,
          height: 56,
          decoration: BoxDecoration(
            color: isDisabled
                ? _bgColor.withAlpha(80)
                : _bgColor,
            borderRadius: BorderRadius.circular(14),
            border: _border,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(child: content()),
          ),
        ),
      ),
    );
  }
}
