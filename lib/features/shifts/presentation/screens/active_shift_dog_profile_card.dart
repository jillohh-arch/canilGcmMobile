part of 'active_shift_dashboard_screen.dart';

/// Card do cão clicável — navega para tela de perfil do cão.
class _DogProfileCard extends StatelessWidget {
  final Dog dog;
  const _DogProfileCard({required this.dog});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(dog.operationalStatus);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.pets_rounded, color: _hudCyan, size: 13),
            const SizedBox(width: 6),
            Text(
              dog.name.toUpperCase(),
              style: GoogleFonts.robotoMono(
                color: _hudCyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => DogProfileScreen(dog: dog),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _hudPanel.withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _hudCyan.withAlpha(40)),
              boxShadow: [
                BoxShadow(color: _hudCyan.withAlpha(10), blurRadius: 16),
              ],
            ),
            child: Row(
              children: [
                _buildDogPhoto(),
                const SizedBox(width: 14),
                Expanded(child: _buildDogInfo(statusColor)),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _hudCyan,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDogPhoto() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _hudCyan, width: 2),
      ),
      child: ClipOval(
        child: dog.profileImageUrl != null
            ? CachedNetworkImage(
                imageUrl: dog.profileImageUrl!,
                fit: BoxFit.cover,
                width: 64,
                height: 64,
                placeholder: (context, url) => const Icon(
                  Icons.pets_rounded,
                  color: _hudCyan,
                  size: 28,
                ),
                errorWidget: (context, url, error) => const Icon(
                  Icons.pets_rounded,
                  color: _hudCyan,
                  size: 28,
                ),
              )
            : const Center(
                child: Icon(
                  Icons.pets_rounded,
                  color: _hudCyan,
                  size: 28,
                ),
              ),
      ),
    );
  }

  Widget _buildDogInfo(Color statusColor) {
    final infoLine = StringBuffer(dog.breed);
    infoLine.write(' • ${dog.age} anos');
    if (dog.weight != null) {
      infoLine.write(' • ${dog.weight}kg');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dog.name,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          infoLine.toString(),
          style: GoogleFonts.inter(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        // Chips de especialidade vindos do Firestore
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: _buildSpecialtyChips(),
        ),
        const SizedBox(height: 8),
        // Condição operacional
        Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: statusColor,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              'Condição: ',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              dog.operationalStatus,
              style: GoogleFonts.inter(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildSpecialtyChips() {
    final specialties = dog.specialties ?? [];
    if (specialties.isEmpty) {
      return [
        _SpecialtyChip(label: 'K9', icon: Icons.pets_rounded, color: _hudCyan),
      ];
    }

    return specialties.map((spec) {
      final data = _chipData(spec);
      return _SpecialtyChip(label: spec, icon: data.$1, color: data.$2);
    }).toList();
  }

  (IconData, Color) _chipData(String spec) {
    switch (spec.toLowerCase()) {
      case 'guarda':
        return (Icons.shield_outlined, _hudGreen);
      case 'busca':
        return (Icons.pets_rounded, const Color(0xFFAB47BC));
      case 'detecção':
      case 'faro':
        return (Icons.track_changes_rounded, _hudAmber);
      default:
        return (Icons.pets_rounded, _hudCyan);
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativo':
      case 'operacional':
        return _hudGreen;
      case 'atenção':
      case 'atencao':
        return _hudAmber;
      case 'inativo':
      case 'afastado':
        return _hudDanger;
      default:
        return Colors.white54;
    }
  }
}

class _SpecialtyChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _SpecialtyChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
