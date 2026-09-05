/// Nomes wire exatos dos callables clínicos consumidos pela Consulta V1.
///
/// Fonte: `functions/src/index.ts` no trunk `142b374`. Não renomear sem
/// reconciliar com o backend: o nome é o contrato.
abstract final class ClinicalConsultationCallableNames {
  ClinicalConsultationCallableNames._();

  /// Abre `ClinicalCase` + evento de abertura, atomicamente.
  static const openClinicalCase = 'healthOpenClinicalCase';

  /// Anexa um `ClinicalEvent` a um caso existente.
  static const appendClinicalEvent = 'healthAppendClinicalEvent';

  /// Promove um evento `draft` para `final`.
  static const finalizeClinicalEvent = 'healthFinalizeClinicalEvent';

  /// Mesma região das demais Functions Health.
  static const region = 'southamerica-east1';
}
