import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Fonte de leitura honesta da Agenda na Fase 4B.
///
/// Sem Firestore / dual-read / dados fake de produção.
/// Sempre retorna página vazia conclusiva (empty ≠ erro).
final class EmptyHealthScheduleSource implements HealthScheduleSource {
  const EmptyHealthScheduleSource();

  @override
  Future<HealthSchedulePage> loadPage(HealthScheduleQuery query) async {
    return HealthSchedulePage.empty();
  }
}
