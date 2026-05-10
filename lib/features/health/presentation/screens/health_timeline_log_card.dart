part of 'health_dashboard_screen.dart';

class _TacticalHealthLogCard extends StatelessWidget {
  final HealthLogModel log;
  final ValueChanged<String?> onOpenAttachment;

  const _TacticalHealthLogCard({
    required this.log,
    required this.onOpenAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final isExam = log.logType == 'Exame';
    final hasAttachments =
        log.mediaAttachments != null && log.mediaAttachments!.isNotEmpty;
    final accentColor = _healthLogColor(log.logType);
    final iconData = _healthLogIcon(log.logType);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: ShapeDecoration(
          color: const Color(0xFF0F172A),
          shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: accentColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          shadows: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HealthLogCardHeader(
              log: log,
              accentColor: accentColor,
              iconData: iconData,
            ),
            _HealthLogCardBody(
              log: log,
              accentColor: accentColor,
              isExam: isExam,
              hasAttachments: hasAttachments,
              onOpenAttachment: onOpenAttachment,
            ),
          ],
        ),
      ),
    );
  }
}
