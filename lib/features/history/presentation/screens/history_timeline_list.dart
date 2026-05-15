part of 'history_screen.dart';

/// Constrói a timeline agrupada por dia
extension _HistoryTimelineList on _HistoryScreenState {
  Widget _buildTimeline(List<HistoryDayGroup> groups, String dogId) {
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_toggle_off,
                size: 64,
                color: Colors.white.withAlpha(40),
              ),
              const SizedBox(height: 16),
              Text(
                'Nenhum registro encontrado',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ajuste os filtros ou registre uma atividade.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: groups.length,
      itemBuilder: (context, groupIndex) {
        final group = groups[groupIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header (sticky-like)
            _buildDayHeader(group),
            // Items do dia
            ...group.entries.asMap().entries.map((mapEntry) {
              final index = mapEntry.key;
              final entry = mapEntry.value;
              final isLast = index == group.entries.length - 1;
              return _buildTimelineItem(entry, isLast: isLast, dogId: dogId);
            }),
          ],
        );
      },
    );
  }

  Widget _buildDayHeader(HistoryDayGroup group) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      color: _bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            group.label,
            style: GoogleFonts.inter(
              color: _cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            group.dateFormatted,
            style: GoogleFonts.inter(
              color: _textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Agrupa entries por dia e gera labels (HOJE, ONTEM, data)
  List<HistoryDayGroup> _groupEntriesByDay(List<HistoryEntry> entries) {
    if (entries.isEmpty) return [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<HistoryEntry>> grouped = {};
    for (final entry in entries) {
      final dayKey = DateFormat('yyyy-MM-dd').format(entry.time);
      grouped.putIfAbsent(dayKey, () => []).add(entry);
    }

    // Ordena os dias (mais recente primeiro)
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return sortedKeys.map((key) {
      final date = DateTime.parse(key);
      final dayEntries = grouped[key]!
        ..sort((a, b) => b.time.compareTo(a.time));

      String label;
      if (date.year == today.year &&
          date.month == today.month &&
          date.day == today.day) {
        label = 'HOJE';
      } else if (date.year == yesterday.year &&
          date.month == yesterday.month &&
          date.day == yesterday.day) {
        label = 'ONTEM';
      } else {
        label = DateFormat('dd/MM').format(date).toUpperCase();
      }

      final dateFormatted = _formatDayDate(date);

      return HistoryDayGroup(
        date: date,
        label: label,
        dateFormatted: dateFormatted,
        entries: dayEntries,
      );
    }).toList();
  }

  String _formatDayDate(DateTime date) {
    final months = [
      '', 'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
    ];
    final weekdays = [
      '', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo',
    ];
    final day = date.day;
    final month = months[date.month];
    final weekday = weekdays[date.weekday];
    return '$day de $month · $weekday';
  }
}
