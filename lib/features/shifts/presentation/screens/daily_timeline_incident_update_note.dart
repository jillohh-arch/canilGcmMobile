part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateNote on _DailyTimelineScreenState {
  Widget _buildIncidentUpdateNoteField(TextEditingController controller) {
    return TextField(
      controller: controller,
      maxLines: 3,
      minLines: 2,
      style: GoogleFonts.inter(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: 'Descreva o andamento da ocorrência...',
        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
        filled: true,
        fillColor: const Color(0xFF141C20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF1D2C33)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFF4ECDE4), width: 1.5),
        ),
      ),
    );
  }
}
