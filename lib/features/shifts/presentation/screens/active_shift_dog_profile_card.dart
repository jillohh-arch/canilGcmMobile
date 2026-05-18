part of 'active_shift_dashboard_screen.dart';

/// Seção "Resumo do Cão" fiel ao mockup — card compacto com specialty badges.
class _DogSummarySection extends StatelessWidget {
  final Dog dog;

  const _DogSummarySection({required this.dog});

  @override
  Widget build(BuildContext context) {
    final weightStr = dog.weight != null
        ? '${dog.weight!.toStringAsFixed(0)}kg'
        : null;
    final metaParts = <String>[
      if (dog.breed.isNotEmpty) dog.breed,
      '${dog.age} anos',
      if (weightStr != null) weightStr,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(emoji: '🐕', text: dog.name.toUpperCase()),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DogProfileScreen(dog: dog)),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(5),
              border: Border.all(color: _kBorderSubtle),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nome + meta
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dog.name,
                            style: GoogleFonts.inter(
                              color: _kTextPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            metaParts.join(' · '),
                            style: GoogleFonts.inter(
                              color: _kTextMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Specialty badges
                if (dog.specialties != null && dog.specialties!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: dog.specialties!.map((s) {
                      return _SpecialtyBadge(label: s);
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SpecialtyBadge extends StatelessWidget {
  final String label;

  const _SpecialtyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    // Cor baseada no tipo de especialidade
    final isFormacao = label.toLowerCase().contains('form');
    final color = isFormacao ? AppTheme.warning : AppTheme.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        border: Border.all(color: color.withAlpha(64)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
