/// Estado de ciclo de vida de um formulário Health v1.
///
/// Mantém a superfície pequena e explícita: o controller combina este status
/// com a flag [HealthFormController.isDirty] para cobrir dirty + submitting.
enum HealthFormStatus {
  /// Formulário recém-aberto ou restaurado para pristine.
  initial,

  /// Usuário alterou campos em relação ao snapshot inicial.
  dirty,

  /// Submit em andamento; novos submits são bloqueados.
  submitting,

  /// Último submit concluído com sucesso.
  success,

  /// Última tentativa de validação/submit falhou.
  error,
}
