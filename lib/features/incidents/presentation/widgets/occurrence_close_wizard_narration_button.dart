part of 'occurrence_close_wizard.dart';

class _NarrationButton extends StatelessWidget {
  final bool listening;
  final VoidCallback onPressed;

  const _NarrationButton({required this.listening, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
        size: 17,
      ),
      label: Text(listening ? 'PARAR NARRAÇÃO' : 'NARRAÇÃO'),
      style: OutlinedButton.styleFrom(
        foregroundColor: listening
            ? AppTheme.error
            : AppTheme.primary,
        side: BorderSide(
          color: listening
              ? AppTheme.error.withAlpha(145)
              : AppTheme.primary.withAlpha(145),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
