part of 'training_log_screen.dart';

class _SessionCardHeader extends StatelessWidget {
  final TrainingSessionModel session;
  final IconData icon;
  final Color color;
  final String dateText;
  final bool expanded;

  const _SessionCardHeader({
    required this.session,
    required this.icon,
    required this.color,
    required this.dateText,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 11),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        border: Border(bottom: BorderSide(color: color.withAlpha(120))),
      ),
      child: Row(
        children: [
          _SessionTypeIcon(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: _SessionTitleBlock(session: session, color: color),
          ),
          const SizedBox(width: 8),
          _SessionDateBlock(session: session, color: color, dateText: dateText),
          const SizedBox(width: 6),
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: color.withAlpha(180),
          ),
        ],
      ),
    );
  }
}

class _SessionTypeIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SessionTypeIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(210), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(65),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }
}

class _SessionTitleBlock extends StatelessWidget {
  final TrainingSessionModel session;
  final Color color;

  const _SessionTitleBlock({required this.session, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _SessionTag(
              label: session.trainingType.toUpperCase(),
              color: color,
              labelColor: color,
              fontSize: 11,
              letterSpacing: 1.4,
              fontFamily: _SessionTagFont.oxanium,
            ),
            if (session.substanceUsed != null)
              _SessionTag(
                label: session.substanceUsed!.toUpperCase(),
                color: AppTheme.textPrimary,
                labelColor: AppTheme.textSecondary,
                fontSize: 9,
                letterSpacing: 0.8,
                fontFamily: _SessionTagFont.robotoMono,
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          session.location,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
