part of 'occurrence_close_wizard.dart';

class _ClosingRoadmap extends StatelessWidget {
  final int currentStep;

  const _ClosingRoadmap({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['RELATO', 'RESULTADO', 'DETALHES'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withAlpha(75)),
      ),
      child: Column(
        children: [
          _ClosingRoadmapHeader(currentStep: currentStep),
          const SizedBox(height: 14),
          Row(
            children: List.generate(
              3,
              (index) => _RoadmapStep(
                index: index,
                label: labels[index],
                currentStep: currentStep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
