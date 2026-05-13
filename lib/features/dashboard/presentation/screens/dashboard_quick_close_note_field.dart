part of 'dashboard_screen.dart';

extension _QuickCloseIncidentNoteField on _QuickCloseIncidentSheetState {
  Widget _buildNoteField() {
    return TextField(
      controller: _noteController,
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
          borderSide: const BorderSide(color: _hudAmber),
        ),
      ),
    );
  }
}
