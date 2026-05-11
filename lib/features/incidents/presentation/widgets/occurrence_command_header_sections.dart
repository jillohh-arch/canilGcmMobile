part of 'occurrence_command_header.dart';

class _HeaderTopBar extends StatelessWidget {
  final VoidCallback? onBack;
  final String status;
  final Color statusColor;

  const _HeaderTopBar({
    required this.onBack,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          if (onBack != null)
            SizedBox(
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
          const Spacer(),
          _HeaderChip(label: _displayStatus(status), color: statusColor),
        ],
      ),
    );
  }
}

class _HeaderTitleBlock extends StatelessWidget {
  final String nature;
  final Color accent;

  const _HeaderTitleBlock({required this.nature, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Row(
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
                  boxShadow: [BoxShadow(color: accent, blurRadius: 10)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OperationalMetricsRow extends StatelessWidget {
  final String elapsedLabel;
  final int? eventCount;
  final Color accent;

  const _OperationalMetricsRow({
    required this.elapsedLabel,
    required this.eventCount,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

String _displayStatus(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('andamento')) return 'EM ANDAMENTO';
  if (normalized.contains('conclu')) return 'FINALIZAÇÃO';
  if (normalized.contains('cancel')) return 'CANCELADA';
  return value.toUpperCase();
}

String _safeNature(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Averiguação' : trimmed;
}
