part of 'health_log_screen.dart';

class _HealthTimeline extends StatefulWidget {
  final String dogId;
  const _HealthTimeline({required this.dogId});

  @override
  State<_HealthTimeline> createState() => _HealthTimelineState();
}

class _HealthTimelineState extends State<_HealthTimeline> {
  String _filter = 'Todos';
  final _filters = [
    'Todos',
    'Vacina',
    'Consulta',
    'Exame',
    'Medicação',
    'Banho',
  ];

  @override
  Widget build(BuildContext context) {
    final hVM = Provider.of<HealthViewModel>(context);
    final logs =
        hVM.healthLogs
            .where((l) => _filter == 'Todos' || l.logType == _filter)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: [
        // Filter chips
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: _filters.map((f) {
              final isSelected = _filter == f;
              final (_, color) = _iconAndColor(f == 'Todos' ? 'Consulta' : f);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (f != 'Todos') ...[
                        Icon(
                          _logIcon(f),
                          size: 13,
                          color: isSelected ? color : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(f),
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
                  onSelected: (_) => setState(() => _filter = f),
                ),
              );
            }).toList(),
          ),
        ),

        // Timeline list
        Expanded(
          child: hVM.isLoading
              ? const Center(child: CircularProgressIndicator())
              : logs.isEmpty
              ? _EmptyHealth(filter: _filter)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: logs.length,
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final isLast = i == logs.length - 1;
                    return _HealthTimelineItem(log: log, isLast: isLast);
                  },
                ),
        ),
      ],
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
          // Line + Dot
          SizedBox(
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
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: Colors.white10,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Card
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Log type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: color.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            log.logType.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
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
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
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
                    // Expanded details
                    if (_expanded) ...[
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
          Icon(
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

// ── New Log Form ──────────────────────────────────────────────────────────────
