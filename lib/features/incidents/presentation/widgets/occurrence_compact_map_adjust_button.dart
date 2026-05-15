part of 'occurrence_compact_location_block.dart';

class _OccurrenceMapAdjustButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _OccurrenceMapAdjustButton({
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: accentColor.withAlpha(13),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accentColor.withAlpha(95)),
        ),
        child: Row(
          children: [
            Icon(Icons.map_rounded, color: accentColor, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'AJUSTAR PONTO NO MAPA',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Icon(Icons.open_in_full_rounded, color: accentColor, size: 16),
          ],
        ),
      ),
    );
  }
}
