part of 'dog_profile_screen.dart';

/// Seção "APTIDÃO OPERACIONAL" com lista de modalidades e status.
class _AptitudeSection extends StatelessWidget {
  final List<DogAptitude> aptitudes;
  final List<String>? specialties;
  final bool loading;

  const _AptitudeSection({
    required this.aptitudes,
    this.specialties,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'APTIDÃO OPERACIONAL'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _panelColor.withAlpha(200),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _cyan.withAlpha(30)),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _cyan,
                    ),
                  ),
                )
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // Se tem aptidões do Firestore, usa elas
    if (aptitudes.isNotEmpty) {
      return Column(
        children: [
          for (int i = 0; i < aptitudes.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withAlpha(10)),
            _AptitudeRow(aptitude: aptitudes[i]),
          ],
        ],
      );
    }

    // Fallback: usa specialties do Dog model
    if (specialties != null && specialties!.isNotEmpty) {
      return Column(
        children: [
          for (int i = 0; i < specialties!.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withAlpha(10)),
            _FallbackAptitudeRow(name: specialties![i]),
          ],
        ],
      );
    }

    return Text(
      'Nenhuma aptidão registrada.',
      style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
    );
  }
}

class _AptitudeRow extends StatelessWidget {
  final DogAptitude aptitude;
  const _AptitudeRow({required this.aptitude});

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor(aptitude.cor);
    final icon = _resolveIcon(aptitude.icone);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              aptitude.nome,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Text(
              aptitude.status,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _resolveColor(String cor) {
    switch (cor) {
      case 'verde':
        return _green;
      case 'roxo':
        return _purple;
      case 'laranja':
      case 'amber':
        return _amber;
      case 'vermelho':
        return _danger;
      case 'ciano':
      default:
        return _cyan;
    }
  }

  IconData _resolveIcon(String icone) {
    switch (icone) {
      case 'shield':
      case 'guarda':
        return Icons.shield_outlined;
      case 'search':
      case 'busca':
        return Icons.search_rounded;
      case 'detection':
      case 'deteccao':
        return Icons.track_changes_rounded;
      case 'patrol':
      case 'patrulha':
        return Icons.directions_walk_rounded;
      default:
        return Icons.pets_rounded;
    }
  }
}

class _FallbackAptitudeRow extends StatelessWidget {
  final String name;
  const _FallbackAptitudeRow({required this.name});

  @override
  Widget build(BuildContext context) {
    final color = _colorForName(name);
    final icon = _iconForName(name);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withAlpha(60)),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _green.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _green.withAlpha(80)),
            ),
            child: Text(
              'ativo',
              style: GoogleFonts.inter(
                color: _green,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForName(String name) {
    switch (name.toLowerCase()) {
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

  IconData _iconForName(String name) {
    switch (name.toLowerCase()) {
      case 'guarda':
        return Icons.shield_outlined;
      case 'busca':
        return Icons.search_rounded;
      case 'detecção':
      case 'faro':
        return Icons.track_changes_rounded;
      default:
        return Icons.pets_rounded;
    }
  }
}
