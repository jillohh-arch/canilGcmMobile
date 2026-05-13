import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'tactical_card_content.dart';
part 'tactical_card_stat.dart';
part 'tactical_card_status_pill.dart';
part 'tactical_card_surface.dart';

class TacticalCard extends StatefulWidget {
  final LinearGradient gradient;
  final VoidCallback? onTap;
  final Widget? avatar;
  final String title;
  final String? subtitle;
  final Widget? rightBadge;
  final List<TacticalCardStat> stats;
  final List<Widget> alerts;
  final double? height;

  const TacticalCard({
    super.key,
    required this.gradient,
    this.onTap,
    this.avatar,
    required this.title,
    this.subtitle,
    this.rightBadge,
    this.stats = const [],
    this.alerts = const [],
    this.height,
  });

  @override
  State<TacticalCard> createState() => _TacticalCardState();
}

class _TacticalCardState extends State<TacticalCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.97,
      upperBound: 1,
    )..value = 1;
    _scaleAnimation = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(scale: _scaleAnimation.value, child: child);
      },
      child: GestureDetector(
        onTapDown: (_) => _controller.reverse(),
        onTapUp: (_) {
          _controller.forward();
          widget.onTap?.call();
        },
        onTapCancel: () => _controller.forward(),
        child: _TacticalCardSurface(
          gradient: widget.gradient,
          height: widget.height,
          child: _TacticalCardContent(
            avatar: widget.avatar,
            title: widget.title,
            subtitle: widget.subtitle,
            rightBadge: widget.rightBadge,
            alerts: widget.alerts,
            stats: widget.stats,
          ),
        ),
      ),
    );
  }
}
