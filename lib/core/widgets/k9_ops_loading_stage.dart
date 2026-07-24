/// Estágios de apresentação do loading oficial do K9 Ops (Mobile).
///
/// Este contrato é **puramente apresentacional**. Ele não executa
/// autenticação, não consulta permissões e não decide navegação — apenas
/// descreve qual marco visual o [K9OpsLoadingScreen] deve refletir.
///
/// O mapeamento entre estados técnicos reais do bootstrap e estes estágios
/// será feito na fase de integração, fora deste arquivo.
library;

/// Marcos visuais do loading. Ordenados na sequência natural do bootstrap.
///
/// No Mobile, apenas dois marcos são exibidos como etapas na interface
/// (`validatingAccess` e `syncingModules`), conforme a spec oficial. Os demais
/// existem para permitir interpolação suave do progresso entre marcos reais e
/// para representar os estados terminais (`ready`/`error`).
enum K9OpsLoadingStage {
  /// App iniciando — antes de qualquer sinal técnico de acesso.
  initializing,

  /// Validando acesso. Primeiro marco visível no Mobile.
  validatingAccess,

  /// Sincronizando módulos. Segundo marco visível no Mobile.
  syncingModules,

  /// Finalização visual antes da prontidão real.
  finalizing,

  /// Bootstrap concluído — pode navegar para a tela de destino.
  ready,

  /// Falha real no bootstrap. O loading não deve permanecer infinito.
  error;

  /// `true` quando o estágio representa conclusão bem-sucedida.
  bool get isComplete => this == K9OpsLoadingStage.ready;

  /// `true` quando o estágio representa uma falha.
  bool get isError => this == K9OpsLoadingStage.error;

  /// Título curto exibido como etapa na interface Mobile.
  ///
  /// Estágios internos (não exibidos como etapa própria) reaproveitam o
  /// rótulo do marco visível mais próximo.
  String get stepLabel {
    switch (this) {
      case K9OpsLoadingStage.initializing:
      case K9OpsLoadingStage.validatingAccess:
        return 'Validando acesso';
      case K9OpsLoadingStage.syncingModules:
      case K9OpsLoadingStage.finalizing:
      case K9OpsLoadingStage.ready:
        return 'Sincronizando módulos';
      case K9OpsLoadingStage.error:
        return 'Falha na inicialização';
    }
  }
}
