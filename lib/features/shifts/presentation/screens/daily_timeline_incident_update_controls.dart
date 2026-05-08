part of 'daily_timeline_screen.dart';

extension _DailyTimelineIncidentUpdateControls on _DailyTimelineScreenState {
  Widget _buildIncidentUpdateHeader(Incident incident) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF4ECDE4).withAlpha(25),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF4ECDE4).withAlpha(80)),
          ),
          child: const Icon(
            Icons.edit_rounded,
            color: Color(0xFF4ECDE4),
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ATUALIZAR OCORRÊNCIA',
                style: GoogleFonts.oxanium(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                incident.location,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

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

  Widget _buildIncidentUpdateActions({
    required BuildContext sheetContext,
    required Future<void> Function() onSave,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(sheetContext),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white54,
              side: const BorderSide(color: Colors.white10),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'Cancelar',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: onSave,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF004E5B),
              foregroundColor: const Color(0xFF4ECDE4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFF4ECDE4), width: 1),
              ),
            ),
            child: Text(
              'Salvar atualização',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
