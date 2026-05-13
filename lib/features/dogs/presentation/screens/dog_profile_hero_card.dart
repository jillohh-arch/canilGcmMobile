part of 'dog_profile_screen.dart';

/// Card principal do cão com foto, nome, raça, idade, peso, status, condutor.
class _HeroCard extends StatelessWidget {
  final Dog dog;
  final String? handlerName;

  const _HeroCard({required this.dog, this.handlerName});

  @override
  Widget build(BuildContext context) {
    final infoLine = StringBuffer(dog.breed);
    infoLine.write(' • ${dog.age} anos');
    if (dog.weight != null) {
      infoLine.write(' • ${dog.weight!.toStringAsFixed(0)} kg');
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _panelColor.withAlpha(220),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cyan.withAlpha(60)),
        boxShadow: [
          BoxShadow(color: _cyan.withAlpha(15), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          // Foto circular
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _cyan, width: 2.5),
              boxShadow: [
                BoxShadow(color: _cyan.withAlpha(30), blurRadius: 16),
              ],
            ),
            child: ClipOval(
              child: dog.profileImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: dog.profileImageUrl!,
                      fit: BoxFit.cover,
                      width: 90,
                      height: 90,
                      placeholder: (context, url) => const Icon(
                        Icons.pets_rounded,
                        color: _cyan,
                        size: 36,
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.pets_rounded,
                        color: _cyan,
                        size: 36,
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.pets_rounded, color: _cyan, size: 36),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          // Nome
          Text(
            dog.name,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          // Raça • Idade • Peso
          Text(
            infoLine.toString(),
            style: GoogleFonts.inter(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          // Status operacional
          _StatusChip(label: dog.operationalStatus),
          const SizedBox(height: 10),
          // Condutor
          if (handlerName != null && handlerName!.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_outline, color: Colors.white38, size: 14),
                const SizedBox(width: 4),
                Text(
                  handlerName!,
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          // Chips de modalidades
          if (dog.specialties != null && dog.specialties!.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: dog.specialties!
                  .map((s) => _ModalityChip(label: s))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ativo':
      case 'operacional':
        return _green;
      case 'em treino':
        return _amber;
      case 'inativo':
      case 'afastado':
        return _danger;
      default:
        return _cyan;
    }
  }
}

class _ModalityChip extends StatelessWidget {
  final String label;
  const _ModalityChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = _modalityColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _modalityColor(String mod) {
    switch (mod.toLowerCase()) {
      case 'guarda':
        return _green;
      case 'busca':
        return _purple;
      case 'detecção':
      case 'faro':
        return _amber;
      default:
        return _cyan;
    }
  }
}
