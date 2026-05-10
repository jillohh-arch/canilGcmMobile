part of 'occurrence_start_screen.dart';

class _OccurrenceStartNatureSection extends StatelessWidget {
  final Color accentColor;
  final Color panelColor;
  final String natureText;
  final bool showNatureEditor;
  final Widget natureEditor;
  final VoidCallback onToggleNatureEditor;

  const _OccurrenceStartNatureSection({
    required this.accentColor,
    required this.panelColor,
    required this.natureText,
    required this.showNatureEditor,
    required this.natureEditor,
    required this.onToggleNatureEditor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showNatureEditor) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor.withAlpha(185),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accentColor.withAlpha(90)),
            ),
            child: natureEditor,
          ),
          const SizedBox(height: 14),
        ],
        TextButton.icon(
          onPressed: onToggleNatureEditor,
          icon: Icon(
            showNatureEditor
                ? Icons.keyboard_arrow_up_rounded
                : Icons.add_rounded,
            color: accentColor,
          ),
          label: Text(
            natureText.isEmpty
                ? 'Ajustar natureza (opcional)'
                : 'Natureza: $natureText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: accentColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Local e horário são preenchidos automaticamente. Toque nos cards para atualizar antes de iniciar.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white.withAlpha(105),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
