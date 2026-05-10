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
        color: const Color(0xFF0B1220),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF00E5FF).withAlpha(75)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.flag_rounded,
                color: Color(0xFFFFB84D),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ROTEIRO DE ENCERRAMENTO',
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFFFFB84D),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              Text(
                '${currentStep + 1} / 3',
                style: GoogleFonts.robotoMono(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
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

class _RoadmapStep extends StatelessWidget {
  final int index;
  final String label;
  final int currentStep;

  const _RoadmapStep({
    required this.index,
    required this.label,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    final active = index <= currentStep;
    final done = index < currentStep;

    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFF00E5FF).withAlpha(25)
                        : Colors.transparent,
                    border: Border.all(
                      color: active ? const Color(0xFF00E5FF) : Colors.white24,
                    ),
                    boxShadow: active
                        ? [
                            BoxShadow(
                              color: const Color(0xFF00E5FF).withAlpha(70),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: done
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF00F5A0),
                            size: 20,
                          )
                        : Text(
                            '${index + 1}',
                            style: GoogleFonts.oxanium(
                              color: active
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white38,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.robotoMono(
                    color: active ? const Color(0xFF00E5FF) : Colors.white30,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (index < 2)
            Container(
              width: 34,
              height: 2,
              color: index < currentStep
                  ? const Color(0xFF00F5A0)
                  : Colors.white12,
            ),
        ],
      ),
    );
  }
}
