import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
          Row(
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
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 52, child: finalSaveButton)),
            ],
          )
        else if (!hasActiveOccurrenceRecord)
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: isSaving ? null : onStartOccurrence,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                'INICIAR OCORRÊNCIA',
                style: GoogleFonts.robotoMono(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              onPressed: isSaving ? null : onRequestFinalization,
              icon: const Icon(Icons.flag_rounded),
              label: Text(
                'FINALIZAR OCORRÊNCIA',
                style: GoogleFonts.robotoMono(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: dangerColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
