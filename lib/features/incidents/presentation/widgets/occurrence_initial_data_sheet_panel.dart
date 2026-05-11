part of 'occurrence_initial_data_sheet.dart';

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
