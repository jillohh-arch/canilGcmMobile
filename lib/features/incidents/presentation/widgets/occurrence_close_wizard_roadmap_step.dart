part of 'occurrence_close_wizard.dart';

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
                _RoadmapStepBadge(index: index, active: active, done: done),
                const SizedBox(height: 8),
                _RoadmapStepLabel(label: label, active: active),
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

class _RoadmapStepBadge extends StatelessWidget {
  final int index;
  final bool active;
  final bool done;

  const _RoadmapStepBadge({
    required this.index,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
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
                  color: active ? const Color(0xFF00E5FF) : Colors.white38,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }
}

class _RoadmapStepLabel extends StatelessWidget {
  final String label;
  final bool active;

  const _RoadmapStepLabel({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      style: GoogleFonts.robotoMono(
        color: active ? const Color(0xFF00E5FF) : Colors.white30,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    );
  }
}
