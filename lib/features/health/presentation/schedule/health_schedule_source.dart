import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_page.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_query.dart';

/// Contrato abstrato de leitura paginada da Agenda Preventiva.
///
/// - Sem Firebase/Firestore nesta fronteira.
/// - Sem escrita (Fase 4A não ativa writes).
/// - Sem stream contínuo (paginação sob demanda; UI futura pode evoluir).
/// - Implementações concretas (Firestore) ficam para fases posteriores.
abstract interface class HealthScheduleSource {
  /// Carrega uma página conforme [query] (cursor e pageSize inclusos).
  Future<HealthSchedulePage> loadPage(HealthScheduleQuery query);
}

/// Erro tipado da fonte de leitura da Agenda.
///
/// [isOffline] permite ao controller distinguir offline de erro genérico
/// sem depender de FirebaseException.
final class HealthScheduleSourceException implements Exception {
  const HealthScheduleSourceException(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
