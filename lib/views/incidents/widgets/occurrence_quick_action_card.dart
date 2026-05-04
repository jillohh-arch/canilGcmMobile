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
    final height = width.clamp(132.0, 164.0).toDouble();
    final hasFullAsset = (assetPath ?? '').isNotEmpty;

    return SizedBox(
      width: width,
      height: height,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: hasFullAsset
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(9, 10, 9, 10),
          decoration: BoxDecoration(
            color: hasFullAsset ? Colors.transparent : const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(6),
            border: hasFullAsset
                ? null
                : Border.all(color: color.withAlpha(85)),
            boxShadow: [
              BoxShadow(
                color: color.withAlpha(hasFullAsset ? 28 : 14),
                blurRadius: hasFullAsset ? 18 : 12,
              ),
            ],
          ),
          child: hasFullAsset
              ? _FullImageCard(action: this)
              : _IconCard(action: this),
        ),
      ),
    );
  }
}

class _FullImageCard extends StatelessWidget {
  final OccurrenceQuickActionCard action;

  const _FullImageCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        action.assetPath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: _FallbackIcon(icon: action.icon, color: action.color),
        ),
      ),
    );
  }
}

class _IconCard extends StatelessWidget {
  final OccurrenceQuickActionCard action;

  const _IconCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _FallbackIcon(icon: action.icon, color: action.color),
        const SizedBox(height: 10),
        Text(
          action.title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.robotoMono(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.7,
            height: 1.12,
          ),
        ),
      ],
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
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
