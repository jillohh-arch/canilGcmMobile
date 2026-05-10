import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'occurrence_active_footer_actions.dart';

class OccurrenceActiveFooter extends StatelessWidget {
  final bool showFinalization;
  final bool hasActiveOccurrenceRecord;
  final bool isSaving;
  final Color accentColor;
  final Color backgroundColor;
  final Color dangerColor;
  final Widget saveStatusPanel;
  final Widget finalSaveButton;
  final VoidCallback onCancelFinalization;
  final VoidCallback onStartOccurrence;
  final VoidCallback onRequestFinalization;

  const OccurrenceActiveFooter({
    super.key,
    required this.showFinalization,
    required this.hasActiveOccurrenceRecord,
    required this.isSaving,
    required this.accentColor,
    required this.backgroundColor,
    required this.dangerColor,
    required this.saveStatusPanel,
    required this.finalSaveButton,
    required this.onCancelFinalization,
    required this.onStartOccurrence,
    required this.onRequestFinalization,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        saveStatusPanel,
        if (showFinalization)
          _OccurrenceFinalizationActionRow(
            isSaving: isSaving,
            finalSaveButton: finalSaveButton,
            onCancelFinalization: onCancelFinalization,
          )
        else if (!hasActiveOccurrenceRecord)
          _OccurrencePrimaryFooterButton(
            label: 'INICIAR OCORRÊNCIA',
            icon: Icons.play_arrow_rounded,
            backgroundColor: accentColor,
            foregroundColor: backgroundColor,
            isSaving: isSaving,
            onPressed: onStartOccurrence,
          )
        else
          _OccurrencePrimaryFooterButton(
            label: 'FINALIZAR OCORRÊNCIA',
            icon: Icons.flag_rounded,
            backgroundColor: dangerColor,
            foregroundColor: Colors.white,
            isSaving: isSaving,
            onPressed: onRequestFinalization,
          ),
      ],
    );
  }
}
