part of 'occurrence_active_context_summary.dart';

class _OccurrenceActiveContextHeader extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onEdit;

  const _OccurrenceActiveContextHeader({
    required this.accentColor,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.fact_check_rounded, color: accentColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'CONTEXTO DA OCORRÊNCIA',
            style: GoogleFonts.robotoMono(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_rounded, size: 15),
          label: Text(
            'EDITAR',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: accentColor,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
