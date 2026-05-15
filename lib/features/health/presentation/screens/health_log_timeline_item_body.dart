part of 'health_log_screen.dart';

class _HealthTimelineItemBody extends StatelessWidget {
  final HealthLogModel log;
  final Color color;
  final String dateStr;
  final bool expanded;

  const _HealthTimelineItemBody({
    required this.log,
    required this.color,
    required this.dateStr,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _HealthLogTypeBadge(logType: log.logType, color: color),
            const Spacer(),
            Text(
              dateStr,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
              color: Colors.white70,
            ),
          ],
        ),
        if (log.vaccines.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            log.vaccines.join(' Â· '),
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
        if (expanded) _HealthExpandedDetails(log: log, color: color),
      ],
    );
  }
}

class _HealthLogTypeBadge extends StatelessWidget {
  final String logType;
  final Color color;

  const _HealthLogTypeBadge({required this.logType, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        logType.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
