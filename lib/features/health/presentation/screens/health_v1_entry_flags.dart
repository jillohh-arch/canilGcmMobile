/// Gate de integração controlada da Fase 2E.
///
/// `true`  → aba Saúde usa Health v1 (shell + Resumo real).
/// `false` → restaura [DogHealthProntuarioScreen] legado sem outras mudanças.
///
/// Reversível sem migration nem alteração de dados.
///
/// Valor de produção do APK de teste 2E/2E-R: **true**.
const bool kHealthV1SummaryEntryEnabled = true;

/// Resolve se a aba Saúde deve montar o entry Health v1.
///
/// [overrideGate] permite testar o ramo legado sem recompilar a flag const.
bool shouldUseHealthV1SummaryEntry({bool? overrideGate}) {
  return overrideGate ?? kHealthV1SummaryEntryEnabled;
}
