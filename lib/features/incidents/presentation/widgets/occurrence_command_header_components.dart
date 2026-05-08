part of 'occurrence_command_header.dart';

class _AppMark extends StatelessWidget {
  final Color accent;

  const _AppMark({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF07101C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(145)),
        boxShadow: [BoxShadow(color: accent.withAlpha(28), blurRadius: 12)],
      ),
      child: Image.asset(
        'assets/app_icon.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            Icon(Icons.shield_rounded, color: accent, size: 22),
      ),
    );
  }
}

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

class _CrewMeta extends StatelessWidget {
  final String title;
  final String name;
  final String subtitle;
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color accent;
  final bool alignEnd;

  const _CrewMeta({
    required this.title,
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.fallbackIcon,
    required this.accent,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(
      imageUrl: imageUrl,
      fallbackIcon: fallbackIcon,
      accent: accent,
    );
    final texts = Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            style: GoogleFonts.robotoMono(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.oxanium(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return Row(
      children: alignEnd
          ? [texts, const SizedBox(width: 8), avatar]
          : [avatar, const SizedBox(width: 8), texts],
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? imageUrl;
  final IconData fallbackIcon;
  final Color accent;

  const _Avatar({
    required this.imageUrl,
    required this.fallbackIcon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withAlpha(180)),
        boxShadow: [BoxShadow(color: accent.withAlpha(35), blurRadius: 12)],
      ),
      child: ClipOval(
        child: Container(
          color: const Color(0xFF0B1220),
          child: imageUrl != null && imageUrl!.trim().isNotEmpty
              ? Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(fallbackIcon, color: accent, size: 24),
                )
              : Icon(fallbackIcon, color: accent, size: 24),
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
