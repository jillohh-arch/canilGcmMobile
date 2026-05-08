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

  List<MapEntry<String, dynamic>> _visibleTimelineDetails(
    _TimelineEntry entry,
  ) {
    return entry.details.entries.where((detail) {
      final key = detail.key;
      final value = detail.value;
      final normalizedKey = key.toLowerCase();

      if (value == null || value.toString().trim().isEmpty) return false;
      if (key.startsWith('_')) return false;
      if (key == 'Resultado') return false;
      if (normalizedKey.contains('tracking')) return false;
      if (normalizedKey.contains('_mediaattachments')) return false;

      return true;
    }).toList();
  }

  bool _isLongTimelineDetail(String key, String value) {
    final normalizedKey = key.toLowerCase();
    return normalizedKey == 'notas' ||
        normalizedKey == 'observações' ||
        normalizedKey == 'descrição' ||
        value.length > 46;
  }

  IconData _timelineDetailIcon(String key) {
    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('clima')) return Icons.cloud_outlined;
    if (normalizedKey.contains('duração')) return Icons.timer_outlined;
    if (normalizedKey.contains('distância')) return Icons.straighten_rounded;
    if (normalizedKey.contains('status')) return Icons.verified_rounded;
    if (normalizedKey.contains('peso')) return Icons.monitor_weight_outlined;
    if (normalizedKey.contains('vacina')) return Icons.vaccines_rounded;
    if (normalizedKey.contains('veterin')) return Icons.medical_services;
    if (normalizedKey.contains('nota') ||
        normalizedKey.contains('observ') ||
        normalizedKey.contains('descr')) {
      return Icons.notes_rounded;
    }
    if (normalizedKey.contains('umidade')) return Icons.water_drop_outlined;
    if (normalizedKey.contains('vento')) return Icons.air_rounded;
    return Icons.data_object_rounded;
  }

  Widget _buildTimelineDetailTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    required bool expanded,
  }) {
    return Container(
      width: expanded ? double.infinity : null,
      constraints: BoxConstraints(minHeight: expanded ? 0 : 74),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020).withAlpha(230),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(70)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withAlpha(20),
            const Color(0xFF0F1726),
            const Color(0xFF070B14),
          ],
        ),
      ),
      child: expanded
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(width: 9),
                Expanded(child: _buildTimelineDetailText(label, value, true)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimelineDetailIcon(icon, accent),
                const SizedBox(height: 8),
                _buildTimelineDetailText(label, value, false),
              ],
            ),
    );
  }

  Widget _buildTimelineDetailIcon(IconData icon, Color accent) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withAlpha(110)),
      ),
      child: Icon(icon, size: 14, color: accent.withAlpha(230)),
    );
  }

  Widget _buildTimelineDetailText(String label, String value, bool expanded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.robotoMono(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.7,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: expanded ? 12 : 13,
            fontWeight: expanded ? FontWeight.w500 : FontWeight.w800,
            height: 1.35,
          ),
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          maxLines: expanded ? null : 2,
        ),
      ],
    );
  }
}
