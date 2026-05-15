part of 'history_screen.dart';

/// Widget de cada item da timeline com linha conectora e Hero
extension _HistoryTimelineItem on _HistoryScreenState {
  Widget _buildTimelineItem(
    HistoryEntry entry, {
    required bool isLast,
    required String dogId,
  }) {
    final authVM = Provider.of<AuthViewModel>(context, listen: false);
    final currentUserId = authVM.user?.uid ?? '';
    final isYou = entry.authorId == currentUserId ||
        entry.authorId == (authVM.user?.email?.split('@').first ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                PageRouteBuilder<void>(
                  transitionDuration: const Duration(milliseconds: 400),
                  reverseTransitionDuration: const Duration(milliseconds: 350),
                  pageBuilder: (context, animation, secondaryAnimation) {
                    return HistoryDetailScreen(entry: entry);
                  },
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(8),
                border: Border.all(color: Colors.white.withAlpha(18)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hora
                  SizedBox(
                    width: 38,
                    child: Text(
                      _formatTime(entry.time),
                      textAlign: TextAlign.right,
                      style: GoogleFonts.inter(
                        color: _textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Ícone
                  Hero(
                    tag: '${entry.heroTag}_icon',
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.categoryColor.withAlpha(46),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        entry.categoryIcon,
                        color: entry.categoryColor,
                        size: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Conteúdo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título com Hero
                        Hero(
                          tag: entry.heroTag,
                          flightShuttleBuilder: (
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
                              style: GoogleFonts.inter(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Meta row
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (entry.subtitle.isNotEmpty)
                              Text(
                                entry.subtitle,
                                style: GoogleFonts.inter(
                                  color: _textTertiary,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            // Badge de autoria
                            _buildAuthorBadge(isYou, entry.authorName),
                            // Status em andamento
                            if (entry.isInProgress)
                              _buildInProgressBadge(),
                            // Editado
                            if (entry.editedAt != null)
                              Text(
                                'editado ${_formatTime(entry.editedAt!)}',
                                style: GoogleFonts.inter(
                                  color: _textTertiary,
                                  fontSize: 9,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Chevron
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.chevron_right,
                      color: _textMuted,
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Linha conectora entre cards
          if (!isLast)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1,
                height: 8,
                margin: const EdgeInsets.only(left: 76),
                color: const Color(0xFF1A3A4A),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuthorBadge(bool isYou, String authorName) {
    if (authorName.isEmpty && !isYou) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isYou
            ? _cyanAccent.withAlpha(26)
            : const Color(0xFF95A5A6).withAlpha(26),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isYou ? 'VOCÊ' : authorName.toUpperCase(),
        style: GoogleFonts.inter(
          color: isYou ? _cyanAccent : const Color(0xFF95A5A6),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildInProgressBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _yellowAccent.withAlpha(31),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(color: _yellowAccent),
          const SizedBox(width: 4),
          Text(
            'EM ANDAMENTO',
            style: GoogleFonts.inter(
              color: _yellowAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Dot pulsante para status "em andamento"
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.4, end: 1.0)),
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}
