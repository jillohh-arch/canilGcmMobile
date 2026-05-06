import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceFlowControls extends StatelessWidget {
  final int currentStep;
  final int lastStep;
  final bool isSaving;
  final bool allowProgressSave;
  final Color accent;
  final Color foregroundOnAccent;
  final Widget saveStatusPanel;
  final Widget primarySaveButton;
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final VoidCallback onSaveProgress;

  const OccurrenceFlowControls({
    super.key,
    required this.currentStep,
    this.lastStep = 3,
    required this.isSaving,
    required this.allowProgressSave,
    required this.accent,
    required this.foregroundOnAccent,
    required this.saveStatusPanel,
    required this.primarySaveButton,
    required this.onContinue,
    required this.onBack,
    required this.onSaveProgress,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = currentStep == lastStep;

    return Column(
      children: [
        saveStatusPanel,
        if (isLast)
          SizedBox(width: double.infinity, height: 56, child: primarySaveButton)
        else
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: isSaving ? null : onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: foregroundOnAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
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
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving ? null : onBack,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0x4400E5FF)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'VOLTAR',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            if (currentStep > 0 && !isLast && allowProgressSave)
              const SizedBox(width: 10),
            if (!isLast && allowProgressSave)
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving ? null : onSaveProgress,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'SALVAR ANDAMENTO',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
