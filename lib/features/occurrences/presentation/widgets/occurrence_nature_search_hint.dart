part of 'occurrence_nature_search.dart';

class _OccurrenceNatureSearchHint extends StatelessWidget {
  const _OccurrenceNatureSearchHint();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Digite parte da natureza ou do código. A busca ignora acentos.',
      style: GoogleFonts.inter(
        color: AppTheme.textPrimary.withAlpha(115),
        fontSize: 11,
        height: 1.35,
      ),
    );
  }
}
