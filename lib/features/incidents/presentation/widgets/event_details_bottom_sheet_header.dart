part of 'event_details_bottom_sheet.dart';

class _Header extends StatelessWidget {
  final Color accentColor;

  const _Header({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accentColor.withAlpha(120)),
          ),
          child: Icon(Icons.timeline_rounded, color: accentColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'DETALHES DO EVENTO',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: Colors.white54,
        ),
      ],
    );
  }
}
