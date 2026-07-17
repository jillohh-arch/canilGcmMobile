import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_cursor.dart';

/// Página paginada da Agenda (agregados canônicos, sem estado temporal).
///
/// A derivação temporal ocorre no controller via
/// [HealthScheduleTemporalPolicy] — a fonte não calcula estados derivados.
final class HealthSchedulePage {
  HealthSchedulePage({
    required List<HealthScheduleItem> items,
    this.nextCursor,
    required this.hasMore,
  }) : items = List.unmodifiable(List<HealthScheduleItem>.of(items)) {
    if (!hasMore && nextCursor != null) {
      throw ArgumentError('hasMore == false exige nextCursor == null');
    }
    if (hasMore && nextCursor == null) {
      throw ArgumentError('hasMore == true exige nextCursor não nulo');
    }
  }

  final List<HealthScheduleItem> items;
  final HealthScheduleCursor? nextCursor;
  final bool hasMore;

  factory HealthSchedulePage.empty() =>
      HealthSchedulePage(items: const [], nextCursor: null, hasMore: false);
}
