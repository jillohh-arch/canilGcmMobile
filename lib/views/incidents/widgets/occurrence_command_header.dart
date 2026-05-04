import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OccurrenceCommandHeader extends StatelessWidget {
  final String nature;
  final String status;
  final String dogName;
  final String operatorName;
  final String elapsedLabel;
  final int? eventCount;
  final bool showOperationalMetrics;
  final String? dogImageUrl;
  final String? operatorImageUrl;
  final Color accent;
  final Color statusColor;
  final VoidCallback? onBack;

  const OccurrenceCommandHeader({
    super.key,
    required this.nature,
    required this.status,
    required this.dogName,
    this.operatorName = 'Condutor',
    required this.elapsedLabel,
    this.eventCount,
    this.showOperationalMetrics = false,
    this.dogImageUrl,
    this.operatorImageUrl,
    required this.accent,
    required this.statusColor,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF07101C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(150), width: 1.2),
        boxShadow: [
          BoxShadow(color: accent.withAlpha(34), blurRadius: 26),
          const BoxShadow(
            color: Color(0xAA000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: RadialGradient(
                  center: const Alignment(0.55, -0.55),
                  radius: 1.2,
                  colors: [
                    accent.withAlpha(32),
                    const Color(0xFF07101C).withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 22,
            top: 34,
            child: Icon(
              Icons.shield_rounded,
              size: 126,
              color: accent.withAlpha(18),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final centerMaxWidth = (constraints.maxWidth - 144)
                      .clamp(120.0, 210.0)
                      .toDouble();

                  return SizedBox(
                    height: 42,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (onBack != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: IconButton(
                                onPressed: onBack,
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: centerMaxWidth,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _AppMark(accent: accent),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'K9 COMANDO',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.robotoMono(
                                      color: Colors.white70,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _HeaderChip(
                            label: _displayStatus(status),
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ClipboardIcon(accent: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeNature(nature).toUpperCase(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.oxanium(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 44,
                          height: 2,
                          decoration: BoxDecoration(
                            color: accent,
                            boxShadow: [
                              BoxShadow(color: accent, blurRadius: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: Colors.white.withAlpha(22)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _CrewMeta(
                      title: 'K9',
                      name: dogName.isNotEmpty ? dogName : 'K9',
                      subtitle: 'Em serviÃ§o',
                      imageUrl: dogImageUrl,
                      fallbackIcon: Icons.pets_rounded,
                      accent: accent,
                      alignEnd: false,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white.withAlpha(35),
                  ),
                  Expanded(
                    child: _CrewMeta(
                      title: 'GCM',
                      name: operatorName.isNotEmpty ? operatorName : 'Condutor',
                      subtitle: 'Condutor',
                      imageUrl: operatorImageUrl,
                      fallbackIcon: Icons.badge_rounded,
                      accent: const Color(0xFF00F5A0),
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
              if (showOperationalMetrics) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _WideMetric(
                        icon: Icons.timer_outlined,
                        title: 'Tempo',
                        label: elapsedLabel,
                        accent: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _WideMetric(
                        icon: Icons.bolt_rounded,
                        title: 'Ações',
                        label: '${eventCount ?? 0}',
                        accent: const Color(0xFFFFB84D),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _displayStatus(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('andamento')) return 'EM ANDAMENTO';
    if (normalized.contains('conclu')) return 'FINALIZAÃ‡ÃƒO';
    if (normalized.contains('cancel')) return 'CANCELADA';
    return value.toUpperCase();
  }

  String _safeNature(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'AveriguaÃ§Ã£o' : trimmed;
  }
}

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
        errorBuilder: (_, __, ___) =>
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
              height: 1.0,
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
                  errorBuilder: (_, __, ___) =>
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
              letterSpacing: 1.0,
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

class _CompactMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _CompactMetric({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 86),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(150),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(95)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.robotoMono(
              color: Colors.white70,
              fontSize: 8.5,
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
