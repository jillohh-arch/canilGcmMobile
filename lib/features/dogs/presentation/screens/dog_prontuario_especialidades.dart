part of 'dog_prontuario_tab_screen.dart';

extension _DogProntuarioEspecialidades on _DogProntuarioTabScreenState {
  Widget _buildEspecialidades(Dog dog) {
    final specialties = dog.specialties ?? [];
    final aptitudes = _aptitudes;

    // Se não tem especialidades nem aptidões, não mostra
    if (specialties.isEmpty && aptitudes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('ESPECIALIDADES OPERACIONAIS'),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: aptitudes.isNotEmpty ? aptitudes.length : specialties.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (aptitudes.isNotEmpty) {
                return _buildAptitudeChip(aptitudes[index]);
              }
              return _buildSpecialtyChip(specialties[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAptitudeChip(DogAptitude apt) {
    final isActive = apt.status.toLowerCase() == 'ativo' ||
        apt.status.toLowerCase() == 'operacional';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _greenAccent.withAlpha(20),
        border: Border.all(color: _greenAccent.withAlpha(64)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _aptitudeIcon(apt.icone),
            color: _greenAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                apt.nome,
                style: GoogleFonts.inter(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                isActive ? '● OPERACIONAL' : '○ ${apt.status.toUpperCase()}',
                style: GoogleFonts.inter(
                  color: isActive ? _greenAccent : _textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialtyChip(String specialty) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _greenAccent.withAlpha(20),
        border: Border.all(color: _greenAccent.withAlpha(64)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _specialtyIcon(specialty),
            color: _greenAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                specialty,
                style: GoogleFonts.inter(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '● OPERACIONAL',
                style: GoogleFonts.inter(
                  color: _greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _aptitudeIcon(String icone) {
    switch (icone.toLowerCase()) {
      case 'shield': return Icons.shield_rounded;
      case 'search': return Icons.search;
      case 'nose': return Icons.air;
      case 'guard': return Icons.security;
      case 'track': return Icons.track_changes;
      default: return Icons.pets;
    }
  }

  IconData _specialtyIcon(String specialty) {
    final lower = specialty.toLowerCase();
    if (lower.contains('faro') || lower.contains('detec')) return Icons.air;
    if (lower.contains('guard') || lower.contains('prote')) return Icons.shield_rounded;
    if (lower.contains('busca') || lower.contains('rast')) return Icons.track_changes;
    if (lower.contains('obedi')) return Icons.school;
    return Icons.pets;
  }
}
