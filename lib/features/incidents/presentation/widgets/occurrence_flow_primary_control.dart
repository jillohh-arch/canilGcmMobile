part of 'occurrence_flow_controls.dart';

class _OccurrenceFlowPrimaryControl extends StatelessWidget {
  final bool isLast;
  final bool isSaving;
  final Color accent;
  final Color foregroundOnAccent;
  final Widget primarySaveButton;
  final VoidCallback onContinue;

  const _OccurrenceFlowPrimaryControl({
    required this.isLast,
    required this.isSaving,
    required this.accent,
    required this.foregroundOnAccent,
    required this.primarySaveButton,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    if (isLast) {
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: primarySaveButton,
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: isSaving ? null : onContinue,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: foregroundOnAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
        ),
        child: Text(
          'CONTINUAR',
          style: GoogleFonts.robotoMono(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
      ),
    );
  }
}
