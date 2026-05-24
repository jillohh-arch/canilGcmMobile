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
    final categoryStyle = _categoryStyle(entry.type);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _navigate(context);
      },
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Stack(
          children: [
            // Linha conectora vertical
            if (!isLast)
              Positioned(
                left: 32 + 16 - 0.5, // time width + gap + half icon
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: Colors.white.withAlpha(15)),
              ),
            Row(
              children: [
                // Horário
                SizedBox(
                  width: 36,
                  child: Text(
                    time,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.inter(
                      color: _hTextMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Ícone circular
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: categoryStyle.color.withAlpha(46),
                    border: Border.all(color: _hBg, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      categoryStyle.emoji,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: _hTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (entry.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: _hTextDimmed,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      _buildMeta(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Chevron
                Text(
                  '›',
                  style: GoogleFonts.inter(
                    color: _hTextMuted,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeta() {
    final children = <Widget>[];

    // Badge de autoria
    final isYou = entry.tag == 'VOCÊ';
    children.add(
      _AuthorBadge(
        label: isYou ? 'VOCÊ' : entry.author.toUpperCase(),
        isYou: isYou,
      ),
    );

    // Badge "EM ANDAMENTO" pulsante
    if (entry.isInProgress) {
      children.add(const _InProgressBadge());
    }

    // Badge "editado"
    if (entry.editedAt != null) {
      final editTime = DateFormat('HH:mm').format(entry.editedAt!);
      children.add(
        Text(
          'editado $editTime',
          style: GoogleFonts.inter(
            color: _hTextDimmed,
            fontSize: 9,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
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
        return const _CategoryStyle(color: _hPurple, emoji: '🍖');
      case HistoryEntryType.health:
        return const _CategoryStyle(color: _hRed, emoji: '⚕');
      case HistoryEntryType.training:
        return const _CategoryStyle(color: _hYellow, emoji: '🎯');
      case HistoryEntryType.occurrence:
        return const _CategoryStyle(color: _hCyan, emoji: '🛡️');
    }
  }
}

class _CategoryStyle {
  final Color color;
  final String emoji;

  const _CategoryStyle({required this.color, required this.emoji});
}

class _AuthorBadge extends StatelessWidget {
  final String label;
  final bool isYou;

  const _AuthorBadge({required this.label, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final color = isYou ? _hCyan : const Color(0xFF95A5A6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
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
    _opacity = Tween<double>(begin: 1.0, end: 0.4).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          const SizedBox(width: 4),
          Text(
            'EM ANDAMENTO',
            style: GoogleFonts.inter(
              color: _hYellow,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
