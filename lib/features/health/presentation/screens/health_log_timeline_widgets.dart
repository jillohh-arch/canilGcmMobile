part of 'health_log_screen.dart';

class _HealthFilterBar extends StatelessWidget {
  final List<String> filters;
  final String selectedFilter;
  final ValueChanged<String> onSelected;

  const _HealthFilterBar({
    required this.filters,
    required this.selectedFilter,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: filters.map((filter) {
          final isSelected = selectedFilter == filter;
          final (_, color) = _iconAndColor(
            filter == 'Todos' ? 'Consulta' : filter,
          );
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filter != 'Todos') ...[
                    Icon(
                      _logIcon(filter),
                      size: 13,
                      color: isSelected ? color : Colors.white70,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(filter),
                ],
              ),
              labelStyle: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : Colors.white70,
              ),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              selectedColor: color.withAlpha(40),
              side: BorderSide(color: isSelected ? color : Colors.white12),
              checkmarkColor: color,
              onSelected: (_) => onSelected(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _HealthTimelineList extends StatelessWidget {
  final bool isLoading;
  final List<HealthLogModel> logs;
  final String filter;

  const _HealthTimelineList({
    required this.isLoading,
    required this.logs,
    required this.filter,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logs.isEmpty) {
      return _EmptyHealth(filter: filter);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isLast = index == logs.length - 1;
        return _HealthTimelineItem(log: log, isLast: isLast);
      },
    );
  }
}

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
              style: GoogleFonts.poppins(
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
            log.vaccines.join(' · '),
            style: GoogleFonts.poppins(
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
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _HealthExpandedDetails extends StatelessWidget {
  final HealthLogModel log;
  final Color color;

  const _HealthExpandedDetails({required this.log, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 10),
        const Divider(color: Colors.white12),
        const SizedBox(height: 6),
        if (log.weight != null)
          _DetailRow(
            icon: Icons.monitor_weight_outlined,
            label: 'Peso',
            value: '${log.weight!.toStringAsFixed(1)} kg',
            color: color,
          ),
        if (log.healthObservations.isNotEmpty) ...[
          const SizedBox(height: 6),
          _DetailRow(
            icon: Icons.notes_rounded,
            label: 'Observações',
            value: log.healthObservations,
            color: color,
          ),
        ],
      ],
    );
  }
}

class _EmptyHealth extends StatelessWidget {
  final String filter;

  const _EmptyHealth({required this.filter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.health_and_safety_outlined,
            size: 56,
            color: Colors.white12,
          ),
          const SizedBox(height: 12),
          Text(
            filter == 'Todos'
                ? 'Nenhum registro médico'
                : 'Sem registros de $filter',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            'Toque em "Novo Registro" para adicionar',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color.withAlpha(180)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
