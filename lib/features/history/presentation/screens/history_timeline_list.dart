part of 'history_screen.dart';

class _HistoryTimeline extends StatelessWidget {
  final List<HistoryDayGroup> groups;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _HistoryTimeline({
    required this.groups,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const _HistoryEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 142),
      itemCount: groups.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasMore && index == groups.length) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            child: OutlinedButton(
              onPressed: onLoadMore,
              style: OutlinedButton.styleFrom(
                foregroundColor: _hCyan,
                side: BorderSide(color: _hCyan.withAlpha(120)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Carregar mais 30',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        return _HistoryDaySection(group: groups[index]);
      },
    );
  }
}

class _HistoryDaySection extends StatelessWidget {
  final HistoryDayGroup group;

  const _HistoryDaySection({required this.group});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          _DayHeader(group: group),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _hTextPrimary.withAlpha(6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _hTextPrimary.withAlpha(18)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < group.entries.length; i++)
                  HistoryTimelineItem(
                    entry: group.entries[i],
                    isLast: i == group.entries.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final HistoryDayGroup group;

  const _DayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          group.label,
          style: GoogleFonts.inter(
            color: _hCyan,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const Spacer(),
        Text(
          group.dateFormatted,
          style: GoogleFonts.inter(
            color: _hTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              color: _hTextMuted,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhum registro encontrado',
              style: GoogleFonts.inter(
                color: _hTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Ajuste os filtros ou registre uma atividade.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: _hTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension _HistoryGrouping on _HistoryScreenState {
  List<HistoryDayGroup> _groupEntriesByDay(List<HistoryEntry> entries) {
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final grouped = <String, List<HistoryEntry>>{};
    for (final entry in entries) {
      final key = DateFormat('yyyy-MM-dd').format(entry.time);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return sortedKeys.map((key) {
      final date = DateTime.parse(key);
      final dayEntries = grouped[key]!
        ..sort((a, b) => b.time.compareTo(a.time));

      return HistoryDayGroup(
        date: date,
        label: _labelForDate(date, today, yesterday),
        dateFormatted: _formatDayDateExtended(date),
        entries: dayEntries,
      );
    }).toList();
  }

  String _labelForDate(DateTime date, DateTime today, DateTime yesterday) {
    if (_isSameDay(date, today)) return 'HOJE';
    if (_isSameDay(date, yesterday)) return 'ONTEM';
    return DateFormat('dd/MM').format(date).toUpperCase();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDayDateExtended(DateTime date) {
    const weekdays = [
      '',
      'segunda',
      'terça',
      'quarta',
      'quinta',
      'sexta',
      'sábado',
      'domingo',
    ];
    const months = [
      '',
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    return '${date.day} de ${months[date.month]} · ${weekdays[date.weekday]}';
  }
}
