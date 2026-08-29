import 'package:canil_gcm/features/health/presentation/summary/health_summary_view_data.dart';

/// Contrato abstrato de leitura contínua do Resumo.
///
/// - Sem Firebase/Firestore.
/// - Sem escrita.
/// - Emite [HealthSummaryViewData] tipado ou `null` (empty).
/// - Erros de leitura propagam via stream error ([HealthSummarySourceException]
///   quando a origem quiser marcar offline).
abstract interface class HealthSummarySource {
  /// Observa o Resumo do [dogId].
  ///
  /// Implementações futuras concretas farão dual-read / projeção; a 2B
  /// só define o contrato.
  Stream<HealthSummaryViewData?> watchSummary(String dogId);
}

/// Erro tipado da fonte de leitura do Resumo.
final class HealthSummarySourceException implements Exception {
  const HealthSummarySourceException(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
