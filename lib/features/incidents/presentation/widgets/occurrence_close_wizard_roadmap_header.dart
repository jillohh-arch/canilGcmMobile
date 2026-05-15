part of 'occurrence_close_wizard.dart';

class _ClosingRoadmapHeader extends StatelessWidget {
  final int currentStep;

  const _ClosingRoadmapHeader({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.flag_rounded, color: AppTheme.warning, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'ROTEIRO DE ENCERRAMENTO',
            style: GoogleFonts.inter(
              color: AppTheme.warning,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        ),
        Text(
          '${currentStep + 1} / 3',
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
