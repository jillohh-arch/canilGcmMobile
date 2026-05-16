part of 'history_screen.dart';

class HistoryTimelineCard extends StatelessWidget {
  final List<HistoryDayGroup> groups;

  const HistoryTimelineCard({super.key, required this.groups});

  @override
  Widget build(BuildContext context) {
    return _HistoryPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: groups.isEmpty
          ? const _HistoryEmptyState()
          : Column(
              children: [
                for (int i = 0; i < groups.length; i++) ...[
                  HistoryDaySection(group: groups[i]),
                  if (i < groups.length - 1) const SizedBox(height: 14),
                ],
                const SizedBox(height: 12),
                _LoadMoreButton(onTap: () {}),
              ],
            ),
    );
  }
}

class HistoryDaySection extends StatelessWidget {
  final HistoryDayGroup group;

  const HistoryDaySection({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.calendar_month_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: GoogleFonts.inter(
                    color: _historyTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: group.label,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(text: ' - ${group.dateFormatted}'),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: _historyBorder),
        const SizedBox(height: 9),
        Stack(
          children: [
            Positioned(
              left: 16,
              top: 22,
              bottom: 22,
              child: Container(width: 1.2, color: _historyTextSecondary),
            ),
            Column(
              children: [
                for (int i = 0; i < group.entries.length; i++) ...[
                  HistoryTimelineItem(
                    entry: group.entries[i],
                    railColor: _railColorForIndex(i),
                  ),
                  if (i < group.entries.length - 1)
                    Divider(height: 1, color: _historyBorder, indent: 74),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Color _railColorForIndex(int index) {
    switch (index) {
      case 0:
        return _historyTextSecondary;
      case 1:
        return _historyYellow;
      default:
        return _historyGreen;
    }
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            color: _historyTextMuted,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum registro encontrado',
            style: GoogleFonts.inter(
              color: _historyTextPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Ajuste os filtros ou registre uma atividade do binômio.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: _historyTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LoadMoreButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sync_rounded, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              'Carregar mais registros',
              style: GoogleFonts.inter(
                color: AppTheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
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
        dateFormatted: _formatDayDate(date),
        entries: dayEntries,
      );
    }).toList();
  }

  String _labelForDate(DateTime date, DateTime today, DateTime yesterday) {
    if (_isSameDay(date, today)) return 'HOJE';
    if (_isSameDay(date, yesterday)) return 'ONTEM';
    return DateFormat('dd/MM/yyyy').format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDayDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
