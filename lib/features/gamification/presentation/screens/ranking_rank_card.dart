part of 'ranking_screen.dart';

class _RankingEntryCard extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final String? photoUrl;
  final String callsign;
  final bool isXp;

  const _RankingEntryCard({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.photoUrl,
    required this.callsign,
    required this.isXp,
  });

  @override
  Widget build(BuildContext context) {
    final rankColor = _rankColor(index);
    final rankIcon = _rankIcon(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: index == 0
            ? _hudPanelAlt.withAlpha(245)
            : _hudPanel.withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: index == 0 ? rankColor.withAlpha(190) : _hudCyan.withAlpha(55),
          width: index == 0 ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (index == 0 ? rankColor : _hudCyan).withAlpha(
              index == 0 ? 45 : 18,
            ),
            blurRadius: index == 0 ? 24 : 14,
            spreadRadius: index == 0 ? 1 : 0,
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: _hudBackground,
              backgroundImage: photoUrl != null
                  ? CachedNetworkImageProvider(photoUrl!)
                  : null,
              child: photoUrl == null
                  ? Text(
                      callsign.isNotEmpty ? callsign[0].toUpperCase() : 'O',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            if (index < 3)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hudBackground,
                  border: Border.all(color: rankColor.withAlpha(160)),
                ),
                padding: const EdgeInsets.all(2),
                child: Icon(rankIcon, size: 16, color: rankColor),
              ),
          ],
        ),
        title: Text(
          '${index + 1}º  $title',
          style: GoogleFonts.oxanium(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: index == 0 ? 18 : 16,
            letterSpacing: 0.8,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: GoogleFonts.robotoMono(
              color: index == 0 ? rankColor.withAlpha(215) : Colors.white60,
              fontWeight: index == 0 ? FontWeight.w700 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        trailing: index == 0
            ? Icon(
                isXp ? Icons.star_rounded : Icons.local_fire_department_rounded,
                color: isXp ? rankColor : _hudAmber,
                size: 32,
              )
            : null,
      ),
    );
  }

  Color _rankColor(int index) {
    if (index == 0) return const Color(0xFFFFD700);
    if (index == 1) return const Color(0xFFC0C0C0);
    if (index == 2) return const Color(0xFFCD7F32);
    return Colors.white24;
  }

  IconData _rankIcon(int index) {
    if (index == 0) return Icons.emoji_events_rounded;
    if (index == 1 || index == 2) return Icons.military_tech_rounded;
    return Icons.star_border_rounded;
  }
}
