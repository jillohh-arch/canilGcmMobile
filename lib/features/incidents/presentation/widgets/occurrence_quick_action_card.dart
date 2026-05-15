import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_quick_action_artwork_card.dart';
part 'occurrence_quick_action_fallback_card.dart';

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
    final hasAsset = (assetPath ?? '').isNotEmpty;

    return SizedBox(
      width: width,
      height: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1A1F),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withAlpha(enabled ? 110 : 50),
                width: 1.2,
              ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withAlpha(22),
                        blurRadius: 14,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: hasAsset
                  ? _QuickActionArtworkCard(
                      assetPath: assetPath!,
                      title: title,
                      icon: icon,
                      color: color,
                      enabled: enabled,
                    )
                  : _QuickActionFallbackCard(
                      title: title,
                      icon: icon,
                      color: color,
                      enabled: enabled,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
