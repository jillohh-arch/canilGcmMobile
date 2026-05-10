import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_flow_primary_control.dart';
part 'occurrence_flow_secondary_controls.dart';

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
        _OccurrenceFlowPrimaryControl(
          isLast: isLast,
          isSaving: isSaving,
          accent: accent,
          foregroundOnAccent: foregroundOnAccent,
          primarySaveButton: primarySaveButton,
          onContinue: onContinue,
        ),
        const SizedBox(height: 10),
        _OccurrenceFlowSecondaryControls(
          currentStep: currentStep,
          isLast: isLast,
          isSaving: isSaving,
          allowProgressSave: allowProgressSave,
          accent: accent,
          onBack: onBack,
          onSaveProgress: onSaveProgress,
        ),
      ],
    );
  }
}
