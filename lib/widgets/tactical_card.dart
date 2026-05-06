import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A premium agent-profile card inspired by Revolut/Nubank.
/// Displays a dog (or any entity) as an operational agent with:
/// - Status pill (colored, with icon + text)
/// - Sex icon (♂/♀)
/// - Semantic alert icons
/// - Stats row at the bottom
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
      upperBound: 1.0,
    )..value = 1.0;
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
      builder: (context, child) =>
          Transform.scale(scale: _scaleAnimation.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _controller.reverse(),
        onTapUp: (_) {
          _controller.forward();
          widget.onTap?.call();
        },
        onTapCancel: () => _controller.forward(),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: widget.height,
          constraints: widget.height == null
              ? const BoxConstraints(minHeight: 148)
              : null,
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: (widget.gradient.colors.first).withAlpha(90),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // ── Background decorative circle ──────────────────────────────
              Positioned(
                right: -50,
                bottom: -30,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(18),
                  ),
                ),
              ),
              Positioned(
                right: 20,
                top: -60,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withAlpha(10),
                  ),
                ),
              ),

              // ── Card content ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row: avatar + info + right badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.avatar != null) ...[
                          widget.avatar!,
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title.toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.8,
                                  height: 1.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                              if (widget.alerts.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(children: widget.alerts),
                              ],
                            ],
                          ),
                        ),
                        if (widget.rightBadge != null) ...[
                          const SizedBox(width: 8),
                          widget.rightBadge!,
                        ],
                      ],
                    ),

                    // Stats row
                    if (widget.stats.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            for (int i = 0; i < widget.stats.length; i++) ...[
                              if (i > 0)
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: Colors.white24,
                                ),
                              Expanded(child: widget.stats[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TacticalCardStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const TacticalCardStat({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Colors.white54),
          const SizedBox(height: 2),
        ],
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Colors.white54,
            letterSpacing: 0.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Compact status pill — "● ATIVO" style (Revolut-inspired)
class StatusPill extends StatelessWidget {
  final String status;
  final Color color;
  final IconData icon;

  const StatusPill({
    super.key,
    required this.status,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(50),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            status,
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
