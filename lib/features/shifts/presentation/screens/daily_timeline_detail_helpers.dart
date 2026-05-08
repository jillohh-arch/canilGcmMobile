part of 'daily_timeline_screen.dart';

extension _DailyTimelineDetailHelpers on _DailyTimelineScreenState {
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
}
