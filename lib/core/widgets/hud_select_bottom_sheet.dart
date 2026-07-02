part of 'hud_controls.dart';

class _HudSelectBottomSheet<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final Color accent;

  const _HudSelectBottomSheet({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(155)),
        boxShadow: [BoxShadow(color: accent.withAlpha(45), blurRadius: 26)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withAlpha(18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withAlpha(120)),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: AppTheme.textPrimary.withAlpha(138),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, accent.withAlpha(20), AppTheme.transparent],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = item == value;
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(item);
                  },
                  child: AnimatedContainer(
                    duration: HudDurations.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accent.withAlpha(28)
                          : _hudPanel.withAlpha(210),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected
                            ? accent
                            : AppTheme.textPrimary.withAlpha(18),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: isSelected
                              ? accent
                              : AppTheme.textPrimary.withAlpha(77),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labelBuilder(item),
                            style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
