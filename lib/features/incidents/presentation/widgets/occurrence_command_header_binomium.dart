part of 'occurrence_command_header.dart';

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
