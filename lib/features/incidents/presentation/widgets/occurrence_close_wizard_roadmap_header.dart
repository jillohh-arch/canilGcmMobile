part of 'occurrence_close_wizard.dart';

class _ClosingRoadmapHeader extends StatelessWidget {
  final int currentStep;

  const _ClosingRoadmapHeader({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.flag_rounded, color: Color(0xFFFFB84D), size: 16),
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
    );
  }
}
