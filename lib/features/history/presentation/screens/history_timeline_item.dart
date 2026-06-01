part of 'history_screen.dart';

class HistoryTimelineItem extends StatelessWidget {
  final HistoryEntry entry;
  final bool isLast;

  const HistoryTimelineItem({
    super.key,
    required this.entry,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(entry.time);
    final style = _categoryStyle(entry.type);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _navigate(context);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    time,
                    style: GoogleFonts.inter(
                      color: _hTextMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.color.withAlpha(36),
                    boxShadow: [
                      BoxShadow(
                        color: style.color.withAlpha(24),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(style.icon, color: style.color, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayTitle(entry),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: _hTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _MetaLine(entry: entry),
                      const SizedBox(height: 7),
                      _StatusBadges(entry: entry),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _hTextMuted,
                  size: 24,
                ),
              ],
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 104),
              child: Divider(
                height: 1,
                thickness: 1,
                color: _hTextPrimary.withAlpha(13),
              ),
            ),
        ],
      ),
    );
  }

  String _displayTitle(HistoryEntry entry) {
    var title = entry.title.trim();
    for (final prefix in const [
      'Ocorrência · ',
      'Ocorrência • ',
      'Treino · ',
      'Treino • ',
    ]) {
      if (title.startsWith(prefix)) {
        title = title.substring(prefix.length).trim();
      }
    }
    return title.isEmpty ? entry.category : title;
  }

  void _navigate(BuildContext context) {
    if (entry.isInProgress && entry.type == HistoryEntryType.occurrence) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActiveOccurrenceScreen(occurrenceId: entry.id),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RegistroDetalhePage(entry: entry),
        ),
      );
    }
  }

  _CategoryStyle _categoryStyle(HistoryEntryType type) {
    switch (type) {
      case HistoryEntryType.nutrition:
        return const _CategoryStyle(
          color: AppTheme.attention,
          icon: Icons.restaurant_rounded,
        );
      case HistoryEntryType.health:
        return const _CategoryStyle(
          color: _hPurple,
          icon: Icons.medical_services_outlined,
        );
      case HistoryEntryType.training:
        return const _CategoryStyle(
          color: _hRed,
          icon: Icons.gps_fixed_rounded,
        );
      case HistoryEntryType.occurrence:
        return const _CategoryStyle(color: _hCyan, icon: Icons.shield_outlined);
    }
  }
}

class _MetaLine extends StatelessWidget {
  final HistoryEntry entry;

  const _MetaLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans()),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  List<InlineSpan> _spans() {
    final spans = <InlineSpan>[];
    final parts = _parts();
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i > 0) spans.add(_plain(' · '));
      spans.add(part);
    }
    return spans;
  }

  List<InlineSpan> _parts() {
    final parts = <InlineSpan>[];

    switch (entry.type) {
      case HistoryEntryType.occurrence:
        final location = _firstNonEmpty([entry.location, entry.subtitle]);
        if (location.isNotEmpty) parts.add(_plain(_shortenLocation(location)));
        break;
      case HistoryEntryType.training:
        parts.add(_plain('Treino'));
        if (entry.subtitle.trim().isNotEmpty) {
          parts.add(_plain(entry.subtitle.trim()));
        }
        break;
      case HistoryEntryType.health:
        parts.add(_plain('Saúde'));
        if (entry.subtitle.trim().isNotEmpty) {
          parts.add(_plain(entry.subtitle.trim()));
        }
        break;
      case HistoryEntryType.nutrition:
        parts.add(_plain('Nutrição'));
        if (entry.subtitle.trim().isNotEmpty) {
          parts.add(_plain(entry.subtitle.trim()));
        }
        break;
    }

    if (_isYou(entry.author)) {
      parts.add(_plain('Você', color: _hCyan, weight: FontWeight.w800));
    } else if (entry.author.trim().isNotEmpty) {
      parts.add(_plain(_shortAuthor(entry.author)));
    }

    if (entry.editedAt != null) {
      parts.add(
        _plain(
          'editado ${DateFormat('HH:mm').format(entry.editedAt!)}',
          style: FontStyle.italic,
        ),
      );
    }

    return parts;
  }

  TextSpan _plain(
    String text, {
    Color color = _hTextDimmed,
    FontWeight weight = FontWeight.w600,
    FontStyle? style,
  }) {
    return TextSpan(
      text: text,
      style: GoogleFonts.inter(
        color: color,
        fontSize: 13,
        fontWeight: weight,
        fontStyle: style,
      ),
    );
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && trimmed != 'Local não informado') {
        return trimmed;
      }
    }
    return '';
  }

  String _shortenLocation(String value) {
    return value.split(',').first.trim();
  }

  String _shortAuthor(String author) {
    final clean = author.trim();
    if (clean.toUpperCase().startsWith('GCM ') && clean.length > 12) {
      return 'GCM';
    }
    return clean;
  }

  bool _isYou(String author) {
    final normalized = author.trim().toLowerCase();
    return normalized == 'você' || normalized == 'voce';
  }
}

class _StatusBadges extends StatelessWidget {
  final HistoryEntry entry;

  const _StatusBadges({required this.entry});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];

    if (!_isYou(entry.author) && entry.author.trim().isNotEmpty) {
      badges.add(_AuthorBadge(label: _badgeAuthor(entry.author)));
    }

    if (entry.isInProgress) {
      badges.add(const _InProgressBadge());
    }

    if (badges.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 6, runSpacing: 4, children: badges);
  }

  String _badgeAuthor(String author) {
    final clean = author.trim();
    if (clean.toUpperCase().startsWith('GCM ') && clean.length > 12) {
      return 'GCM';
    }
    return clean.toUpperCase();
  }

  bool _isYou(String author) {
    final normalized = author.trim().toLowerCase();
    return normalized == 'você' || normalized == 'voce';
  }
}

class _CategoryStyle {
  final Color color;
  final IconData icon;

  const _CategoryStyle({required this.color, required this.icon});
}

class _AuthorBadge extends StatelessWidget {
  final String label;

  const _AuthorBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _hTextPrimary.withAlpha(10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: _hTextSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _InProgressBadge extends StatefulWidget {
  const _InProgressBadge();

  @override
  State<_InProgressBadge> createState() => _InProgressBadgeState();
}

class _InProgressBadgeState extends State<_InProgressBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1, end: 0.4).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _hYellow.withAlpha(31),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _hYellow,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'EM ANDAMENTO',
            style: GoogleFonts.inter(
              color: _hYellow,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
