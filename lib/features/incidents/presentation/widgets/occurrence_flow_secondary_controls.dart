part of 'occurrence_flow_controls.dart';

class _OccurrenceFlowSecondaryControls extends StatelessWidget {
  final int currentStep;
  final bool isLast;
  final bool isSaving;
  final bool allowProgressSave;
  final Color accent;
  final VoidCallback onBack;
  final VoidCallback onSaveProgress;

  const _OccurrenceFlowSecondaryControls({
    required this.currentStep,
    required this.isLast,
    required this.isSaving,
    required this.allowProgressSave,
    required this.accent,
    required this.onBack,
    required this.onSaveProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (currentStep > 0)
          Expanded(
            child: _OccurrenceBackButton(isSaving: isSaving, onPressed: onBack),
          ),
        if (currentStep > 0 && !isLast && allowProgressSave)
          const SizedBox(width: 10),
        if (!isLast && allowProgressSave)
          Expanded(
            child: _OccurrenceSaveProgressButton(
              isSaving: isSaving,
              accent: accent,
              onPressed: onSaveProgress,
            ),
          ),
      ],
    );
  }
}

class _OccurrenceBackButton extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onPressed;

  const _OccurrenceBackButton({
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isSaving ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Color(0x4400E5FF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        'VOLTAR',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _OccurrenceSaveProgressButton extends StatelessWidget {
  final bool isSaving;
  final Color accent;
  final VoidCallback onPressed;

  const _OccurrenceSaveProgressButton({
    required this.isSaving,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isSaving ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        'SALVAR ANDAMENTO',
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
