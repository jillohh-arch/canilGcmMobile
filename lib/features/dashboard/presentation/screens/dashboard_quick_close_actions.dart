part of 'dashboard_screen.dart';

extension _QuickCloseIncidentActions on _QuickCloseIncidentSheetState {
  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _closeIncident,
            style: FilledButton.styleFrom(
              backgroundColor: _hudAmber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Encerrar agora',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}
