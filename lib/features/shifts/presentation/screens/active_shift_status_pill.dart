part of 'active_shift_dashboard_screen.dart';

class _ActiveShiftPill extends StatelessWidget {
  const _ActiveShiftPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(220),
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: _hudGreen, width: 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _hudGreen,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'TURNO ATIVO',
            style: GoogleFonts.robotoMono(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _hudGreen,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}
