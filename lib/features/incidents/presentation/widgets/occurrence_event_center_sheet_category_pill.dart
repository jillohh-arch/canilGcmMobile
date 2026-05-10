part of 'occurrence_event_center_sheet.dart';

class _EventCategoryPill extends StatelessWidget {
  final OccurrenceEventCategory category;
  final Color panelColor;
  final bool selected;
  final VoidCallback onTap;

  const _EventCategoryPill({
    required this.category,
    required this.panelColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? category.color.withAlpha(35) : panelColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? category.color : category.color.withAlpha(70),
          ),
        ),
        child: Row(
          children: [
            Icon(category.icon, color: category.color, size: 17),
            const SizedBox(width: 7),
            Text(
              category.title.toUpperCase(),
              style: GoogleFonts.robotoMono(
                color: selected ? category.color : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
