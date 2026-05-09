part of 'occurrence_command_header.dart';

class _ClipboardIcon extends StatelessWidget {
  final Color accent;

  const _ClipboardIcon({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: accent.withAlpha(16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(135)),
      ),
      child: Icon(Icons.assignment_rounded, color: accent, size: 25),
    );
  }
}

/// Bloco "binômio" — apresenta K9 + condutor como UMA unidade visual:
/// dois avatares circulares com leve sobreposição no centro, nomes
/// lado a lado abaixo, e os labels "K9"/"GCM" como rótulos pequenos
/// na cor do respectivo agente.
///
/// Substitui o pattern anterior (avatares nas pontas + divisor central)
/// que comunicava separação em vez de união.
class _BinomiumBlock extends StatelessWidget {
  final String dogName;
  final String? dogImageUrl;
  final Color dogAccent;
  final String operatorName;
  final String? operatorImageUrl;
  final Color operatorAccent;

  const _BinomiumBlock({
    required this.dogName,
    required this.dogImageUrl,
    required this.dogAccent,
    required this.operatorName,
    required this.operatorImageUrl,
    required this.operatorAccent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AvatarPair(
          dogImageUrl: dogImageUrl,
          dogAccent: dogAccent,
          operatorImageUrl: operatorImageUrl,
          operatorAccent: operatorAccent,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _NameLabel(
                name: dogName.isNotEmpty ? dogName : 'K9',
                label: 'K9',
                accent: dogAccent,
              ),
            ),
            const SizedBox(width: 18),
            Flexible(
              child: _NameLabel(
                name: operatorName.isNotEmpty ? operatorName : 'Condutor',
                label: 'GCM',
                accent: operatorAccent,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Par de avatares circulares com leve sobreposição no centro.
/// O cão à esquerda, o GCM à direita. Sobreposição de ~14px comunica
/// "estes dois estão juntos" sem virar uma única blob.
class _AvatarPair extends StatelessWidget {
  final String? dogImageUrl;
  final Color dogAccent;
  final String? operatorImageUrl;
  final Color operatorAccent;

  const _AvatarPair({
    required this.dogImageUrl,
    required this.dogAccent,
    required this.operatorImageUrl,
    required this.operatorAccent,
  });

  @override
  Widget build(BuildContext context) {
    const avatarSize = 60.0;
    const overlap = 14.0;
    return SizedBox(
      width: avatarSize * 2 - overlap,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            child: _Avatar(
              imageUrl: dogImageUrl,
              fallbackIcon: Icons.pets_rounded,
              accent: dogAccent,
              size: avatarSize,
            ),
          ),
          Positioned(
            right: 0,
            child: _Avatar(
              imageUrl: operatorImageUrl,
              fallbackIcon: Icons.badge_rounded,
              accent: operatorAccent,
              size: avatarSize,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nome do agente (K9 ou GCM) com label pequeno embaixo na cor de accent.
class _NameLabel extends StatelessWidget {
  final String name;
  final String label;
  final Color accent;

  const _NameLabel({
    required this.name,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.oxanium(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.robotoMono(
            color: accent,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color accent;
  final double size;

  const _Avatar({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.accent,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF07101C),
        border: Border.all(color: accent.withAlpha(180), width: 2),
        boxShadow: [BoxShadow(color: accent.withAlpha(40), blurRadius: 14)],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF0B1220),
          child: imageUrl != null && imageUrl!.trim().isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(fallbackIcon, color: accent, size: size * 0.45),
                )
              : Icon(fallbackIcon, color: accent, size: size * 0.45),
        ),
      ),
    );
  }
}

class _WideMetric extends StatelessWidget {
  final IconData icon;
  final String title;
  final String label;
  final Color accent;

  const _WideMetric({
    required this.icon,
    required this.title,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(150),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(95)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 16),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: GoogleFonts.robotoMono(
              color: Colors.white.withAlpha(115),
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  final Color color;

  const _HeaderChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(150)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.robotoMono(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
