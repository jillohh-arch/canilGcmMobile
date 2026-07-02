part of 'hud_controls.dart';

class HudStagePanel extends StatelessWidget {
  final List<String> titles;
  final List<String> subtitles;
  final List<IconData> icons;
  final int currentIndex;
  final Color accent;
  final Widget child;

  const HudStagePanel({
    super.key,
    required this.titles,
    required this.subtitles,
    required this.icons,
    required this.currentIndex,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    assert(titles.length == subtitles.length);
    assert(titles.length == icons.length);

    return HudPanel(
      accent: accent,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(160)),
                ),
                child: Icon(icons[currentIndex], color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titles[currentIndex].toUpperCase(),
                  softWrap: true,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                'STEP ${currentIndex + 1}/${titles.length}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textPrimary.withAlpha(138),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withAlpha(20), AppTheme.transparent],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitles[currentIndex],
            style: GoogleFonts.inter(
              color: AppTheme.textPrimary.withAlpha(153),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: HudDurations.normal,
            switchInCurve: HudCurves.enter,
            switchOutCurve: HudCurves.exit,
            child: KeyedSubtree(key: ValueKey(currentIndex), child: child),
          ),
        ],
      ),
    );
  }
}
