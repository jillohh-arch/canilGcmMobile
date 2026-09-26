library;

import 'operational_restriction.dart';

/// Contrato de leitura da coleção de restrições operacionais de um cão.
///
/// Lê exclusivamente `dogs/{dogId}/operational_restrictions`.
/// Somente leitura — sem escrita, sem mutação, sem efeitos colaterais.
abstract interface class HealthRestrictionHistoryReader {
  /// Retorna as restrições canônicas persistidas para o [dogId].
  ///
  /// Se o cão não possuir restrições, retorna uma lista vazia.
  Future<List<OperationalRestriction>> getRestrictionsForDog(String dogId);
}
