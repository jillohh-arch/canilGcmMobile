part of 'occurrence_initial_data_sheet.dart';

class _InitialDataSheetHeader extends StatelessWidget {
  final Color accentColor;

  const _InitialDataSheetHeader({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.edit_note_rounded, color: accentColor, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'EDITAR DADOS ESSENCIAIS',
            style: GoogleFonts.robotoMono(
              color: accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
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
