part of 'history_screen.dart';

class HistoryTimelineItem extends StatelessWidget {
  final HistoryEntry entry;
  final Color railColor;

  const HistoryTimelineItem({
    super.key,
    required this.entry,
    required this.railColor,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(entry.time);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            PageRouteBuilder<void>(
              transitionDuration: const Duration(milliseconds: 260),
              reverseTransitionDuration: const Duration(milliseconds: 220),
              pageBuilder: (context, animation, secondaryAnimation) {
                return RegistroDetalhePage(entry: entry);
              },
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Center(
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: railColor,
                      border: Border.all(color: _historyBackground, width: 1.5),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  time,
                  style: GoogleFonts.inter(
                    color: _historyTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Hero(
                tag: '${entry.heroTag}_icon',
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: entry.color.withAlpha(13),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _historyBorder),
                  ),
                  child: Icon(entry.icon, color: entry.color, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: entry.heroTag,
                      flightShuttleBuilder:
                          (
                            flightContext,
                            animation,
                            flightDirection,
                            fromHeroContext,
                            toHeroContext,
                          ) {
                            return Material(
                              color: Colors.transparent,
                              child: toHeroContext.widget,
                            );
                          },
                      child: Material(
                        color: Colors.transparent,
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: _historyTextPrimary,
                            fontSize: 14,
                            height: 1.08,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (entry.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: _historyTextSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          color: _historyTextMuted,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            entry.author.isEmpty ? 'Ragonha' : entry.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: _historyTextSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HistoryCategoryTag(entry: entry),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: _historyTextSecondary,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCategoryTag extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryCategoryTag({required this.entry});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 92),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: entry.color.withAlpha(8),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: entry.color.withAlpha(170)),
        ),
        child: _HistoryAutoFitText(
          entry.tag,
          style: GoogleFonts.inter(
            color: entry.color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
