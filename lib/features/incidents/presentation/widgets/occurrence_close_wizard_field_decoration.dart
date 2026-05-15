part of 'occurrence_close_wizard.dart';

extension _OccurrenceCloseWizardFieldDecoration on _OccurrenceCloseWizardState {
  InputDecoration _fieldDecoration({
    required String hint,
    IconData? icon,
    String? suffixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: Colors.white38),
      counterStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 9),
      prefixIcon: icon == null
          ? null
          : Icon(icon, color: _OccurrenceCloseWizardState._cyan, size: 18),
      suffixText: suffixText,
      suffixStyle: GoogleFonts.inter(
        color: _OccurrenceCloseWizardState._cyan,
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
      filled: true,
      fillColor: const Color(0xFF0A1322),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: _OccurrenceCloseWizardState._cyan.withAlpha(55),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: _OccurrenceCloseWizardState._cyan,
          width: 1.4,
        ),
      ),
    );
  }
}
