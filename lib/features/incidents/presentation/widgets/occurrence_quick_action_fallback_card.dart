part of 'occurrence_quick_action_card.dart';

class _QuickActionFallbackCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _QuickActionFallbackCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withAlpha(enabled ? 28 : 14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withAlpha(enabled ? 150 : 70)),
            ),
            child: Icon(
              icon,
              color: enabled ? color : color.withAlpha(120),
              size: 26,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.robotoMono(
              color: enabled ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.55,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}
