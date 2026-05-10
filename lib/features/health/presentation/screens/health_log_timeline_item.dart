part of 'health_log_screen.dart';

class _HealthTimelineItem extends StatefulWidget {
  final HealthLogModel log;
  final bool isLast;

  const _HealthTimelineItem({required this.log, required this.isLast});

  @override
  State<_HealthTimelineItem> createState() => _HealthTimelineItemState();
}

class _HealthTimelineItemState extends State<_HealthTimelineItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final (icon, color) = _iconAndColor(log.logType);
    final dateStr =
        '${log.date.day.toString().padLeft(2, '0')}/${log.date.month.toString().padLeft(2, '0')}/${log.date.year}';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HealthTimelineRail(icon: icon, color: color, isLast: widget.isLast),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: EdgeInsets.only(bottom: widget.isLast ? 0 : 14),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(_expanded ? 15 : 8),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _expanded ? color.withAlpha(80) : Colors.white10,
                    width: _expanded ? 1 : 0.5,
                  ),
                ),
                child: _HealthTimelineItemBody(
                  log: log,
                  color: color,
                  dateStr: dateStr,
                  expanded: _expanded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthTimelineRail extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isLast;

  const _HealthTimelineRail({
    required this.icon,
    required this.color,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withAlpha(30),
              border: Border.all(color: color.withAlpha(150), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          if (!isLast)
            Expanded(
              child: Container(
                width: 1.5,
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
        ],
      ),
    );
  }
}
