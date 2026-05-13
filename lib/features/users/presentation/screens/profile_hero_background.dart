part of 'profile_screen.dart';

class _ProfileHeroBackground extends StatelessWidget {
  final String? photoStr;

  const _ProfileHeroBackground({required this.photoStr});

  @override
  Widget build(BuildContext context) {
    if (photoStr == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A2A1A), Color(0xFF0C1A2E)],
          ),
        ),
      );
    }

    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: CachedNetworkImage(
          imageUrl: photoStr!,
          fit: BoxFit.cover,
          color: Colors.black.withValues(alpha: 0.31),
        ),
      ),
    );
  }
}

class _ProfileHeroOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black45, _hudBackground.withAlpha(220)],
        ),
      ),
    );
  }
}
