import 'package:flutter/material.dart';

import 'package:canil_gcm/core/theme/app_theme.dart';

/// Superfície de card do Resumo alinhada ao mockup 01 (painel dark + borda cyan).
class HealthSummaryCardSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double borderWidth;

  const HealthSummaryCardSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = 16,
    this.borderColor,
    this.backgroundColor,
    this.borderWidth = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surfacePanel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppTheme.primary.withValues(alpha: 0.22),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Placeholder discreto para blocos em loading (sem CircularProgressIndicator).
class HealthSummarySkeletonBar extends StatelessWidget {
  final double height;
  final double? width;
  final double borderRadius;

  const HealthSummarySkeletonBar({
    super.key,
    this.height = 12,
    this.width,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.surfaceWhiteOverlay,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}
