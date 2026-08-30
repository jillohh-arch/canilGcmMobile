import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';

/// Contrato abstrato de leitura paginada da timeline Health.
///
/// - Sem Firebase/Firestore.
/// - Sem escrita.
/// - Sem stream contínuo (a timeline é paginada; necessidades distintas do Resumo).
/// - Implementações concretas ficam para fases posteriores (3C+).
abstract interface class HealthTimelineSource {
  /// Carrega uma página conforme [query] (inclui cursor e pageSize).
  Future<HealthTimelinePage> loadPage(HealthTimelineQuery query);
}

/// Erro tipado da fonte de leitura da timeline.
///
/// [isOffline] permite ao controller distinguir offline de erro genérico
/// sem depender de FirebaseException.
final class HealthTimelineSourceException implements Exception {
  const HealthTimelineSourceException(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
