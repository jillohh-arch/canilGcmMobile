part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentCloseControls on _DailyTimelineScreenState {
  Widget _buildIncidentCloseNoteField(TextEditingController controller) {
    return TextField(
      controller: controller,
      maxLines: 3,
      minLines: 2,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Atualização final',
        labelStyle: GoogleFonts.inter(color: Colors.white54),
        filled: true,
        fillColor: Colors.white.withAlpha(6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFFBBF24)),
        ),
      ),
    );
  }

  Widget _buildIncidentCloseActions({
    required BuildContext sheetContext,
    required Future<void> Function() onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext),
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
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFBBF24),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Encerrar',
              style: GoogleFonts.inter(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}
