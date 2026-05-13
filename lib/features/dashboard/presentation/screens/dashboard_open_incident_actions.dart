part of 'dashboard_screen.dart';

class _OpenIncidentActions extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback onQuickClose;

  const _OpenIncidentActions({
    required this.onContinue,
    required this.onQuickClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onContinue,
            icon: const Icon(Icons.playlist_add_check_rounded, size: 16),
            label: Text(
              'Continuar ocorrência',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onQuickClose,
            icon: const Icon(Icons.task_alt_rounded, size: 16),
            label: Text(
              'Encerrar agora',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
