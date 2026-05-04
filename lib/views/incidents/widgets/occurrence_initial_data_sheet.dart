import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceInitialDataSheet extends StatelessWidget {
  final Color accentColor;
  final Color backgroundColor;
  final Widget child;
  final VoidCallback onDone;

  const OccurrenceInitialDataSheet({
    super.key,
    required this.accentColor,
    required this.backgroundColor,
    required this.child,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.all(14),
      padding: EdgeInsets.fromLTRB(0, 0, 0, bottomInset),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withAlpha(125)),
        boxShadow: [
          BoxShadow(color: accentColor.withAlpha(35), blurRadius: 24),
        ],
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: accentColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'EDITAR DADOS ESSENCIAIS',
                    style: GoogleFonts.robotoMono(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: Colors.white54,
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: backgroundColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  'CONCLUIR EDIÇÃO',
                  style: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OccurrenceInitialDataPanel extends StatelessWidget {
  final Color accentColor;
  final Color panelColor;
  final Widget natureStep;
  final Widget locationBlock;

  const OccurrenceInitialDataPanel({
    super.key,
    required this.accentColor,
    required this.panelColor,
    required this.natureStep,
    required this.locationBlock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor.withAlpha(190),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DADOS ESSENCIAIS',
            style: GoogleFonts.robotoMono(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          natureStep,
          const SizedBox(height: 12),
          locationBlock,
        ],
      ),
    );
  }
}
