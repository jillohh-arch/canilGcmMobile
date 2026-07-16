import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';

/// Página paginada da timeline.
///
/// Invariante:
/// - se [hasMore] == false, então [nextCursor] == null
/// - se [nextCursor] != null, então [hasMore] == true
final class HealthTimelinePage {
  HealthTimelinePage({
    required List<HealthTimelineEntryView> items,
    this.nextCursor,
    required this.hasMore,
  }) : items = List.unmodifiable(List<HealthTimelineEntryView>.of(items)) {
    if (!hasMore && nextCursor != null) {
      throw ArgumentError('hasMore == false exige nextCursor == null');
    }
    if (hasMore && nextCursor == null) {
      throw ArgumentError('hasMore == true exige nextCursor não nulo');
    }
  }

  /// Itens desta página (imutável).
  final List<HealthTimelineEntryView> items;

  /// Cursor opaco para a próxima página, se houver.
  final HealthTimelineCursor? nextCursor;

  /// Indica se existe página seguinte.
  final bool hasMore;

  /// Página vazia terminal (sem mais resultados).
  factory HealthTimelinePage.empty() =>
      HealthTimelinePage(items: const [], nextCursor: null, hasMore: false);

  @override
  bool operator ==(Object other) {
    if (other is! HealthTimelinePage) return false;
    if (other.hasMore != hasMore) return false;
    if (other.nextCursor != nextCursor) return false;
    if (other.items.length != items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (other.items[i] != items[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(hasMore, nextCursor, Object.hashAll(items));
}
