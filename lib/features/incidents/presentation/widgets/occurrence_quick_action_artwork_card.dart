part of 'occurrence_quick_action_card.dart';

class _QuickActionArtworkCard extends StatelessWidget {
  final String assetPath;
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _QuickActionArtworkCard({
    required this.assetPath,
    required this.title,
    required this.icon,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _QuickActionFallbackCard(
          title: title,
          icon: icon,
          color: color,
          enabled: enabled,
        ),
      ),
    );
  }
}
