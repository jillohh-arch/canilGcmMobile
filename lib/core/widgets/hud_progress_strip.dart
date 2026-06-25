part of 'hud_controls.dart';

class HudStepItem {
  final IconData icon;
  final String label;
  final String helper;

  const HudStepItem({
    required this.icon,
    required this.label,
    required this.helper,
  });
}

class HudProgressStrip extends StatelessWidget {
  final List<HudStepItem> steps;
  final int currentIndex;
  final Color accent;
  final ValueChanged<int> onSelected;

  const HudProgressStrip({
    super.key,
    required this.steps,
    required this.currentIndex,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isActive = index == currentIndex;
          final isDone = index < currentIndex;
          final color = isActive || isDone
              ? accent
              : AppTheme.textPrimary.withAlpha(61);

          return Padding(
            padding: EdgeInsets.only(right: index == steps.length - 1 ? 0 : 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isActive ? 164 : 122,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withAlpha(18)
                      : _hudPanel.withAlpha(170),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive
                        ? accent
                        : AppTheme.textPrimary.withAlpha(31),
                    width: isActive ? 1.2 : 0.6,
                  ),
                  boxShadow: isActive
                      ? [BoxShadow(color: accent.withAlpha(45), blurRadius: 16)]
                      : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: color.withAlpha(130),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : step.icon,
                        color: color,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            step.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: isActive
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimary.withAlpha(179),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(height: 2),
                            Text(
                              step.helper,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppTheme.textPrimary.withAlpha(138),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
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
        }),
      ),
    );
  }
}
