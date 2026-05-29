part of 'active_shift_dashboard_screen.dart';

/// Seção "Resumo do Cão" — card com avatar, info, badges e seta de navegação.
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
      ?weightStr,
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(8),
              border: Border.all(color: _kBorderSubtle),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + Nome + meta + seta
                Row(
                  children: [
                    // Avatar do cão
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF1A2A30),
                        border: Border.all(
                          color: AppTheme.primary.withAlpha(51),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: dog.profileImageUrl != null &&
                                dog.profileImageUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: dog.profileImageUrl!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                placeholder: (_, _) => _dogFallback(),
                                errorWidget: (_, _, _) => _dogFallback(),
                              )
                            : _dogFallback(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dog.name,
                            style: GoogleFonts.inter(
                              color: _kTextPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            metaParts.join(' · '),
                            style: GoogleFonts.inter(
                              color: _kTextSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Status operacional
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.success,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Operacional',
                                style: GoogleFonts.inter(
                                  color: AppTheme.success,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Seta de navegação
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _kTextMuted,
                      size: 20,
                    ),
                  ],
                ),
                // Specialty badges
                if (dog.specialties != null && dog.specialties!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
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

  Widget _dogFallback() {
    return Container(
      color: const Color(0xFF1A2A30),
      alignment: Alignment.center,
      child: Icon(
        Icons.pets_rounded,
        color: AppTheme.primary.withAlpha(128),
        size: 22,
      ),
    );
  }
}

class _SpecialtyBadge extends StatelessWidget {
  final String label;

  const _SpecialtyBadge({required this.label});

  @override
  Widget build(BuildContext context) {
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
