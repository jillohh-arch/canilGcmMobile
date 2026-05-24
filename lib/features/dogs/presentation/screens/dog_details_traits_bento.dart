part of 'dog_details_screen.dart';

class _DogTraitsBentoRow extends StatelessWidget {
  final Dog dog;

  const _DogTraitsBentoRow({required this.dog});

  @override
  Widget build(BuildContext context) {
    final sexAccent = dog.sex == 'F' ? _femaleAccent : _maleAccent;

    return Row(
      children: [
        Expanded(
          child: _DogTraitBentoBlock(
            icon: dog.sex == 'F' ? Icons.female_rounded : Icons.male_rounded,
            accent: sexAccent,
            value: dog.sex == 'F' ? 'Fêmea' : 'Macho',
            label: 'SEXO',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DogTraitBentoBlock(
            icon: Icons.cake_outlined,
            accent: _ageAccent,
            value: '${dog.age} anos',
            label: 'IDADE',
          ),
        ),
        if (dog.conductorRa != null) ...[
          const SizedBox(width: 10),
          Expanded(child: _ConductorBentoBlock(conductorRa: dog.conductorRa!)),
        ],
      ],
    );
  }
}

class _DogTraitBentoBlock extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String value;
  final String label;

  const _DogTraitBentoBlock({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return _BentoBlock(
      height: 80,
      accent: accent,
      child: Row(
        children: [
          Icon(icon, size: 28, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConductorBentoBlock extends StatelessWidget {
  final String conductorRa;

  const _ConductorBentoBlock({required this.conductorRa});

  @override
  Widget build(BuildContext context) {
    return _BentoBlock(
      height: 80,
      accent: _trainingAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.badge_outlined, size: 18, color: _trainingAccent),
          const SizedBox(height: 4),
          Text(
            'RA $conductorRa',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'CONDUTOR',
            style: GoogleFonts.inter(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}
