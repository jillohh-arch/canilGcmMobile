/// Estados padronizados de apresentação para telas de leitura do Health v1.
///
/// Preferir composição via [HealthAsyncBody] em vez de mega-widgets.
enum HealthPresentationStatus {
  loading,
  data,
  empty,
  error,
  offline,
  submitting,
}
