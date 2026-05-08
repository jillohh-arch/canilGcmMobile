part of 'daily_timeline_screen.dart';

extension _DailyTimelineDetailPanel on _DailyTimelineScreenState {
  Widget _buildTimelineDetailPanel(_TimelineEntry entry, Color accent) {
    final details = _visibleTimelineDetails(entry);
    if (details.isEmpty) {
      return const SizedBox.shrink();
    }

    final title = switch (entry.type) {
      'Treino' => 'TELEMETRIA DO TREINO',
      'Rotina' => 'ROTINA OPERACIONAL',
      'Saude' => 'PRONTUÁRIO DE SAÚDE',
      'Ocorrência' => 'DADOS DA OCORRÊNCIA',
      _ => 'DETALHES DO REGISTRO',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF070B14).withAlpha(225),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 3, height: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.oxanium(
                  color: accent.withAlpha(230),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: details.map((entryDetail) {
              final key = entryDetail.key;
              final value = entryDetail.value.toString().trim();
              final isLong = _isLongTimelineDetail(key, value);
              final child = _buildTimelineDetailTile(
                label: key,
                value: value,
                icon: _timelineDetailIcon(key),
                accent: accent,
                expanded: isLong,
              );

              if (isLong) {
                return child;
              }

              return FractionallySizedBox(widthFactor: 0.47, child: child);
            }).toList(),
          ),
        ],
      ),
    );
  }
}
