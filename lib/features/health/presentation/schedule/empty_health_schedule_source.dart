import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// Fonte vazia explícita da Agenda (testes / harness).
///
/// Não é fallback silencioso de produção após 4D Gate 2.
/// Produção usa [FirestoreHealthScheduleSource]; injete esta source
/// apenas quando o empty local for intencional (sem I/O).
final class EmptyHealthScheduleSource implements HealthScheduleSource {
  const EmptyHealthScheduleSource();

  @override
  Future<HealthSchedulePage> loadPage(HealthScheduleQuery query) async {
    return HealthSchedulePage.empty();
  }
}
