part of 'hud_controls.dart';

class HudSelectField<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final T? value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;
  final Color accent;
  final String placeholder;

  const HudSelectField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
    this.accent = AppTheme.primary,
    this.placeholder = 'Selecione',
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = value == null
        ? placeholder
        : labelBuilder(value as T);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openSelector(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _hudPanelDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(95), width: 1),
          boxShadow: [BoxShadow(color: accent.withAlpha(18), blurRadius: 14)],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withAlpha(18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withAlpha(90)),
              ),
              child: Icon(icon, color: accent, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: accent.withAlpha(190),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    selectedLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: value == null
                          ? Colors.white.withAlpha(115)
                          : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openSelector(BuildContext context) async {
    HapticFeedback.selectionClick();
    final selected = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _HudSelectBottomSheet<T>(
        label: label,
        icon: icon,
        value: value,
        items: items,
        labelBuilder: labelBuilder,
        accent: accent,
      ),
    );

    if (selected != null) {
      onChanged(selected);
    }
  }
}