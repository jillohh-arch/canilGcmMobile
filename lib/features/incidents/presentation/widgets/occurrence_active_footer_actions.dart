part of 'occurrence_active_footer.dart';

class _OccurrenceFinalizationActionRow extends StatelessWidget {
  final bool isSaving;
  final Widget finalSaveButton;
  final VoidCallback onCancelFinalization;

  const _OccurrenceFinalizationActionRow({
    required this.isSaving,
    required this.finalSaveButton,
    required this.onCancelFinalization,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: isSaving ? null : onCancelFinalization,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0x4400E5FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'VOLTAR',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: SizedBox(height: 52, child: finalSaveButton)),
      ],
    );
  }
}

class _OccurrencePrimaryFooterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isSaving;
  final VoidCallback onPressed;

  const _OccurrencePrimaryFooterButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: isSaving ? null : onPressed,
        icon: Icon(icon),
        label: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
