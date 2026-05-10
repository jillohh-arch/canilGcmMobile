part of 'occurrence_quick_action_options_sheet.dart';

class _QuickActionOptionTile extends StatelessWidget {
  final OccurrenceQuickAction option;
  final Color panelColor;

  const _QuickActionOptionTile({
    required this.option,
    required this.panelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(option);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panelColor.withAlpha(210),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: option.color.withAlpha(80)),
          ),
          child: Row(
            children: [
              Icon(option.icon, color: option.color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: _QuickActionOptionTexts(option: option)),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionOptionTexts extends StatelessWidget {
  final OccurrenceQuickAction option;

  const _QuickActionOptionTexts({required this.option});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          option.title,
          style: GoogleFonts.oxanium(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          option.description,
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
