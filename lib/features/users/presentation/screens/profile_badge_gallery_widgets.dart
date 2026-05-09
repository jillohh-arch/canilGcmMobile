part of 'profile_screen.dart';

class _BadgeGalleryTile extends StatelessWidget {
  final BadgeData badge;
  final bool isUnlocked;

  const _BadgeGalleryTile({required this.badge, required this.isUnlocked});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isUnlocked
          ? badge.description
          : 'Bloqueado: ${badge.description}',
      textStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(6),
      ),
      child: isUnlocked
          ? _UnlockedBadgeTile(badge: badge)
          : _LockedBadgeTile(badge: badge),
    );
  }
}

class _UnlockedBadgeTile extends StatelessWidget {
  final BadgeData badge;

  const _UnlockedBadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    return _BadgeTileFrame(
      badge: badge,
      backgroundAlpha: 8,
      borderAlpha: 140,
      shadow: BoxShadow(
        color: badge.color.withValues(alpha: 0.16),
        blurRadius: 10,
        spreadRadius: 1,
      ),
    );
  }
}

class _LockedBadgeTile extends StatelessWidget {
  final BadgeData badge;

  const _LockedBadgeTile({required this.badge});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        0.4,
        0,
      ]),
      child: _BadgeTileFrame(
        badge: badge,
        backgroundAlpha: 5,
        borderAlpha: 120,
      ),
    );
  }
}

class _BadgeTileFrame extends StatelessWidget {
  final BadgeData badge;
  final int backgroundAlpha;
  final int borderAlpha;
  final BoxShadow? shadow;

  const _BadgeTileFrame({
    required this.badge,
    required this.backgroundAlpha,
    required this.borderAlpha,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(backgroundAlpha),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badge.color.withAlpha(borderAlpha)),
        boxShadow: shadow == null ? null : [shadow!],
      ),
      child: Column(
        children: [
          Icon(badge.icon, size: 32, color: badge.color),
          const SizedBox(height: 6),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
