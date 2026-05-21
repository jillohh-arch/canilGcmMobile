part of 'occurrence_nature_search.dart';

class _OccurrenceNatureCodeBadge extends StatelessWidget {
  final OccurrenceNature option;
  final Color accent;

  const _OccurrenceNatureCodeBadge({
    required this.option,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(100)),
      ),
      child: Text(
        option.code.isEmpty ? 'MAN' : option.code,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: accent,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
