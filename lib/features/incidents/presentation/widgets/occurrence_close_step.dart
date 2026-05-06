import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceCloseStep extends StatelessWidget {
  final bool canShowFinalResults;
  final Widget statusSelector;
  final Widget descriptionField;
  final Widget? outcomeSelector;
  final Widget? successSelector;
  final List<Widget> outcomeDetailFields;
  final Widget boField;
  final Widget imageGallery;

  const OccurrenceCloseStep({
    super.key,
    required this.canShowFinalResults,
    required this.statusSelector,
    required this.descriptionField,
    this.outcomeSelector,
    this.successSelector,
    required this.outcomeDetailFields,
    required this.boField,
    required this.imageGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statusSelector,
        const SizedBox(height: 16),
        descriptionField,
        if (!canShowFinalResults) ...[
          const SizedBox(height: 12),
          Text(
            'Ao preencher a descrição final, os resultados da ocorrência serão liberados aqui.',
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
        if (canShowFinalResults) ...[
          const SizedBox(height: 18),
          ?successSelector,
          const SizedBox(height: 12),
          ?outcomeSelector,
          const SizedBox(height: 16),
          ...outcomeDetailFields,
          const SizedBox(height: 16),
          boField,
          const SizedBox(height: 18),
          imageGallery,
        ],
      ],
    );
  }
}
