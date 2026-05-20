part of 'history_screen.dart';

class _HistoryTimeline extends StatelessWidget {
  final List<HistoryDayGroup> groups;

  const _HistoryTimeline({required this.groups});

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const _HistoryEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: _itemCount(),
      itemBuilder: (context, index) {
        int offset = 0;
        for (final group in groups) {
          if (index == offset) {
            return _DayHeader(group: group);
          }
          offset++;
          if (index < offset + group.entries.length) {
            final entryIndex = index - offset;
            final isLast = entryIndex == group.entries.length - 1;
            return HistoryTimelineItem(
              entry: group.entries[entryIndex],
              isLast: isLast,
            );
          }
          offset += group.entries.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  int _itemCount() {
    int count = 0;
    for (final group in groups) {
      count += 1 + group.entries.length;
    }
    return count;
  }
}

class _DayHeader extends StatelessWidget {
  final HistoryDayGroup group;

  const _DayHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _hBg,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            group.label,
            style: GoogleFonts.inter(
              color: _hCyan,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            group.dateFormatted,
            style: GoogleFonts.inter(
              color: _hTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

      final label = _labelForDate(date, today, yesterday);
      return HistoryDayGroup(
        date: date,
        label: label,
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
    const weekdays = ['', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
    const months = [
      '', 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
    ];
    final day = date.day;
    final month = months[date.month];
    final weekday = weekdays[date.weekday];
    return '$day de $month · $weekday';
  }
}
