part of 'occurrence_event_center_sheet.dart';

class _EventCenterHeader extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onClose;

  const _EventCenterHeader({required this.accentColor, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.playlist_add_rounded, color: accentColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'ADICIONAR EVENTO',
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
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
