part of 'shift_assumption_screen.dart';

class _ReadinessBar extends StatelessWidget {
  final int value;

  const _ReadinessBar({required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 75
        ? _hudGreen
        : value >= 45
        ? _hudAmber
        : _hudRed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PRONTIDÃO',
              style: GoogleFonts.robotoMono(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              '$value%',
              style: GoogleFonts.oxanium(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: _hudBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white12),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 100) / 100,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(color: color.withAlpha(120), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
