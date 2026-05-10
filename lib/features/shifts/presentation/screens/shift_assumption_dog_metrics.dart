part of 'shift_assumption_screen.dart';

class _DogMetricRow extends StatelessWidget {
  final Dog dog;

  const _DogMetricRow({required this.dog});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DogMetric(
            icon: Icons.monitor_weight_outlined,
            label: 'PESO',
            value: dog.weight != null
                ? '${dog.weight!.toStringAsFixed(1)} KG'
                : '-- KG',
            color: _hudCyan,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DogMetric(
            icon: Icons.schedule_rounded,
            label: 'IDADE',
            value: '${dog.age} ANOS',
            color: _hudAmber,
          ),
        ),
      ],
    );
  }
}

class _DogMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DogMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudPanel.withAlpha(226),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            softWrap: true,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WideMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hudBackground.withAlpha(205),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hudCyan.withAlpha(70)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _hudCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
