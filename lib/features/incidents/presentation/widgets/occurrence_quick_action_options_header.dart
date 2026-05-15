part of 'occurrence_quick_action_options_sheet.dart';

class _QuickActionOptionsHeader extends StatelessWidget {
  final OccurrenceQuickAction action;
  final VoidCallback onClose;

  const _QuickActionOptionsHeader({
    required this.action,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: action.color.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: action.color.withAlpha(120)),
          ),
          child: Icon(action.icon, color: action.color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.title.toUpperCase(),
                style: GoogleFonts.inter(
                  color: action.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Selecione o tipo de evento.',
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
          color: Colors.white54,
        ),
      ],
    );
  }
}
