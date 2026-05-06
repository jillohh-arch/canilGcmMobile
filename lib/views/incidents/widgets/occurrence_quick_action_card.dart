import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceQuickActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? assetPath;
  final double width;
  final bool enabled;
  final VoidCallback onTap;

  const OccurrenceQuickActionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.width,
    required this.enabled,
    required this.onTap,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 126,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(92)),
            boxShadow: [BoxShadow(color: color.withAlpha(16), blurRadius: 12)],
          ),
          child: _CompactActionCard(action: this),
        ),
      ),
    );
  }
}

class _CompactActionCard extends StatelessWidget {
  final OccurrenceQuickActionCard action;

  const _CompactActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    const actionArtSize = 82.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if ((action.assetPath ?? '').isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Opacity(
                opacity: action.enabled ? 0.95 : 0.42,
                child: SizedBox.square(
                  dimension: actionArtSize,
                  child: Image.asset(
                    action.assetPath!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  const Color(0xFF070B12).withAlpha(45),
                  const Color(0xFF070B12).withAlpha(130),
                  const Color(0xFF070B12).withAlpha(235),
                ],
                stops: const [0.0, 0.46, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FallbackIcon(icon: action.icon, color: action.color),
                const Spacer(),
                Text(
                  action.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.robotoMono(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.55,
                    height: 1.08,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _FallbackIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF050914).withAlpha(180),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(145)),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
