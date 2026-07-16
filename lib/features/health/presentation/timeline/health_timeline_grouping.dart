import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';

/// Grupo puro de entradas por dia de calendário.
///
/// - [date] é meia-noite local do dia (sem labels "Hoje"/"Ontem").
/// - Labels e localização ficam para a Fase 3B.
final class HealthTimelineDayGroup {
  HealthTimelineDayGroup({
    required this.date,
    required List<HealthTimelineEntryView> entries,
  }) : entries = List.unmodifiable(List<HealthTimelineEntryView>.of(entries)) {
    if (date.hour != 0 ||
        date.minute != 0 ||
        date.second != 0 ||
        date.millisecond != 0 ||
        date.microsecond != 0) {
      throw ArgumentError.value(
        date,
        'date',
        'deve ser meia-noite (dia normalizado)',
      );
    }
  }

  /// Dia calendário normalizado (local meia-noite).
  final DateTime date;

  /// Entradas do dia, na ordem recebida (já devem estar ordenadas).
  final List<HealthTimelineEntryView> entries;

  @override
  bool operator ==(Object other) {
    if (other is! HealthTimelineDayGroup) return false;
    if (other.date != date) return false;
    if (other.entries.length != entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (other.entries[i] != entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(date, Object.hashAll(entries));
}

/// Agrupa entradas por dia de calendário local.
///
/// - Não reordena globalmente: assume que [entries] já está em
///   `occurredAt DESC` (+ tie-break).
/// - Ordem dos grupos: dia mais recente primeiro.
/// - Ordem interna: preserva a ordem relativa de [entries].
/// - Normalização: `DateTime(year, month, day)` no fuso local do
///   `occurredAt` convertido via [toLocal] (padrão: `DateTime.toLocal`).
///
/// Não inventa timezone clínico novo.
List<HealthTimelineDayGroup> groupTimelineByDay(
  List<HealthTimelineEntryView> entries, {
  DateTime Function(DateTime value)? toLocal,
}) {
  if (entries.isEmpty) return const [];

  final localize = toLocal ?? (DateTime d) => d.toLocal();
  final buckets = <DateTime, List<HealthTimelineEntryView>>{};
  final order = <DateTime>[];

  for (final entry in entries) {
    final local = localize(entry.occurredAt);
    final day = DateTime(local.year, local.month, local.day);
    final list = buckets.putIfAbsent(day, () {
      order.add(day);
      return <HealthTimelineEntryView>[];
    });
    list.add(entry);
  }

  // Garante grupos em ordem de dia DESC (mais recente primeiro),
  // estável caso a lista de entrada já venha ordenada.
  order.sort((a, b) => b.compareTo(a));

  return [
    for (final day in order)
      HealthTimelineDayGroup(date: day, entries: buckets[day]!),
  ];
}

/// Comparador oficial de entradas: `occurredAt DESC`, empate por `id ASC`.
int compareTimelineEntries(
  HealthTimelineEntryView a,
  HealthTimelineEntryView b,
) {
  final byTime = b.occurredAt.compareTo(a.occurredAt);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}

/// Ordena deterministicamente (nova lista).
List<HealthTimelineEntryView> sortTimelineEntries(
  Iterable<HealthTimelineEntryView> entries,
) {
  final list = List<HealthTimelineEntryView>.of(entries);
  list.sort(compareTimelineEntries);
  return list;
}

/// Mescla [existing] com [incoming], deduplicando por [HealthTimelineEntryView.id].
///
/// Política de colisão: o payload **mais novo do carregamento atual**
/// ([incoming]) substitui o anterior com o mesmo id.
///
/// Resultado ordenado por [compareTimelineEntries].
List<HealthTimelineEntryView> mergeTimelineEntries({
  required List<HealthTimelineEntryView> existing,
  required List<HealthTimelineEntryView> incoming,
}) {
  final byId = <String, HealthTimelineEntryView>{};
  for (final e in existing) {
    byId[e.id] = e;
  }
  // Incoming sobrescreve (resultado mais novo do carregamento atual).
  for (final e in incoming) {
    byId[e.id] = e;
  }
  return sortTimelineEntries(byId.values);
}
