# RELATÓRIO DE INVESTIGAÇÃO TÉCNICA: NOTIFICAÇÕES E TURNOS
**Status:** Concluído (Apenas Leitura)
**Autor:** Arquiteto de Software Sênior
**Escopo:** Mapeamento técnico detalhado para subsidiar refatorações nas frentes de notificações, mensagens de UI, fluxo de encerramento de turnos e ciclo de vida de guarnições/viaturas.

---

## FRENTE 1 — Limpar Todas as Notificações

### (a) Comportamento Atual do Código
1. **Divisão de Notificações na UI:** 
   A tela de notificações (`PendingScreen`) divide os registros recebidos de um stream em duas categorias distintas na construção do widget (linhas 50 a 55):
   * **`actionItems`**: Notificações que exigem uma ação direta do usuário (ex: convite de guarnição, assinatura pendente). Filtrado usando a propriedade `item.isOpenAction`.
   * **`notices`**: Notificações informativas (avisos gerais ou pendências já resolvidas). Filtrado como o oposto de `item.isOpenAction`.
2. **Ações em Massa Existentes:** 
   A única ação em massa na UI atual é o botão **"Marcar lidas"** na AppBar. Ele executa o método `_markAllAsRead()`, que por sua vez chama `NotificationService.markAllAsRead()`. Esse método realiza um batch no Firestore para atualizar a propriedade `read_at` de todas as notificações não lidas para o timestamp do servidor.
3. **Mecanismo de Limpeza (Arquivamento):** 
   Conforme a regra corporativa ("Parte 14"), notificações não são fisicamente deletadas pelo aplicativo. O arquivamento é um *soft-archive* (arquivamento lógico) obtido setando a propriedade `archived_at` com o timestamp atual. Atualmente, a limpeza de avisos só pode ser feita de forma **individual**, clicando no ícone de arquivar de cada cartão de aviso.

### (b) Evidências (Arquivos e Linhas)
* **Divisão de listas na UI:** [pending_screen.dart:L50-55](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/occurrences/presentation/screens/pending_screen.dart#L50-L55)
  ```dart
  final actionItems =
      notifications.where((item) => item.isOpenAction).toList()
        ..sort(_compareActionItems);
  final notices =
      notifications.where((item) => !item.isOpenAction).toList()
        ..sort(_compareByCreatedAtDesc);
  ```
* **Ação em massa "Marcar lidas":** [pending_screen.dart:L124-134](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/occurrences/presentation/screens/pending_screen.dart#L124-L134)
* **Regras de elegibilidade no modelo `NotificationItem`:** [notification_item.dart:L244-256](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/domain/notification_item.dart#L244-L256)
  ```dart
  bool get isUnread => readAt == null;
  bool get isResolved => resolvedAt != null;
  bool get isArchived => archivedAt != null;
  bool get isOpenAction => actionRequired && resolvedAt == null;
  bool get isNotice => !isOpenAction;
  bool get canBeArchived => !isOpenAction;
  ```
* **Método de arquivamento individual no serviço:** [notification_service.dart:L107-122](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/services/notification_service.dart#L107-L122)
  ```dart
  Future<void> archiveNotice({
    required String userId,
    required NotificationItem notification,
  }) async {
    if (!notification.canBeArchived) {
      throw StateError('Pendencia aberta nao pode ser limpa.');
    }
    await _notificationsCollection
        .doc(userId)
        .collection('items')
        .doc(notification.id)
        .update({'archived_at': FieldValue.serverTimestamp()});
  }
  ```
* **Depreciação de deleção física (Regra Parte 14):** [notification_service.dart:L208-219](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/services/notification_service.dart#L208-L219)

### (c) Lacunas e Solução Proposta
* **Lacuna:** **Não existe** um botão ou método para arquivar todos os avisos operacionais de uma única vez. O usuário é obrigado a clicar individualmente em cada aviso para limpar sua caixa de entrada de notificações.
* **Sintoma Esperado:** Acúmulo de notificações antigas na seção "Avisos", gerando poluição visual, já que o fluxo individual de arquivamento manual é moroso.
* **Inserção do Método e do Botão:**
  * No **`NotificationService`**, deve ser criado o método `archiveAllNotices({required String userId})`. Ele fará uma query para buscar todos os itens ativos (onde `archived_at == null` e `action_required == false` ou `resolved_at != null`) e aplicará um lote (WriteBatch) alterando `archived_at` para `serverTimestamp()`.
  * Na UI (**`pending_screen.dart`**), o botão "Limpar avisos" (TextButton) deve ser inserido no cabeçalho do widget `_NotificationSection` (cerca da linha 598) apenas para a seção de "Avisos" (`title == 'Avisos'`), exibido condicionalmente se `count > 0`.

---

## FRENTE 2 — Padronização das Mensagens (Toast/Snackbar)

### (a) Comportamento Atual do Componente `AppFeedback`
O componente centralizado de feedback visual da aplicação é o [AppFeedback](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/widgets/app_feedback.dart), que customiza a exibição de barras de feedback no app.
* **Tipos suportados:** `success`, `error`, `warning`, `info`, `loading` ([app_feedback.dart:L7](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/widgets/app_feedback.dart#L7)).
* **Estilo Visual:** Cria um cartão flutuante estilizado (margem de 16px nas laterais, cantos arredondados R18, fundo escuro semi-transparente `surfaceSnack` e bordas com brilho/sombra colorida com a cor correspondente do tipo de feedback). Mostra um bloco à esquerda contendo o ícone do tipo de feedback e, no corpo, o título e a mensagem de texto limpa de termos técnicos (`AppFeedbackText.clean(message)`).
* **API Pública:**
  * `AppFeedback.success(context, message, {title})`
  * `AppFeedback.warning(context, message, {title})`
  * `AppFeedback.info(context, message, {title})`
  * `AppFeedback.loading(context, message, {title})`
  * `AppFeedback.error(context, error, {fallback})`
  * `AppFeedback.show(context, message, {type, title, duration})`

### (b) Levantamento Completo: SnackBars Crus (`showSnackBar`)
Foi realizado um rastreamento completo de todos os arquivos do diretório `lib/` que utilizam `ScaffoldMessenger.of(context).showSnackBar` ou variações com snackbars nativos do Flutter em vez do componente centralizado `AppFeedback`.

**Total de arquivos com SnackBars crus:** 40 arquivos  
**Total de ocorrências de SnackBars crus:** 118 ocorrências  

| Arquivo | Linha | O que a mensagem comunica | Tipo |
| :--- | :--- | :--- | :--- |
| `lib/core/widgets/binomio_header.dart` | L621 | Mensagem de ação genérica do cabeçalho | info/success |
| `lib/core/widgets/seal_detail_sheet.dart` | L125 | Alerta de funcionalidade de selo não disponível | info/success |
| `lib/core/widgets/seal_detail_sheet.dart` | L165 | Alerta de funcionalidade de selo não disponível | info/success |
| `lib/features/app_shell/presentation/screens/main_root_actions.dart` | L183 | Aviso de necessidade de turno ativo | info/success |
| `lib/features/app_shell/presentation/screens/main_root_exit_dialog.dart` | L29 | Aviso sobre saída do app | info/success |
| `lib/features/auth/presentation/screens/login_screen.dart` | L67 | Informação de erro/aviso de login | info/success |
| `lib/features/dogs/presentation/screens/vaccination_history_screen.dart` | L195 | Erro ao gerar PDF de vacinação | erro |
| `lib/features/dogs/presentation/screens/weight_history_screen.dart` | L202 | Erro ao gerar PDF de peso | erro |
| `lib/features/dogs/presentation/screens/weight_history_screen.dart` | L1124 | Sucesso no registro de pesagem do cão | sucesso |
| `lib/features/dogs/presentation/screens/weight_history_screen.dart` | L1136 | Erro ao salvar pesagem do cão | erro |
| `lib/features/health/presentation/screens/health_event_form_screen.dart` | L296 | Sucesso ao salvar evento de saúde | sucesso |
| `lib/features/health/presentation/screens/health_event_form_screen.dart` | L306 | Erro ao salvar registro de saúde | erro |
| `lib/features/history/presentation/screens/history_detail_screen.dart` | L102 | Progresso/Aguarde ao carregar PDF | info/success |
| `lib/features/history/presentation/screens/history_detail_screen.dart` | L143 | Erro na exportação de PDF | erro |
| `lib/features/history/presentation/screens/history_detail_screen.dart` | L204 | Feedback de compartilhamento do log | info/success |
| `lib/features/history/presentation/screens/history_screen.dart` | L268 | Aviso de filtros sem resultados encontrados | info/success |
| `lib/features/nutrition/presentation/screens/nutrition_full_screen.dart` | L227 | Erro ao gerar PDF de nutrição | erro |
| `lib/features/occurrences/presentation/screens/active_occurrence_screen.dart` | L180 | Erro ao registrar evento em ocorrência | erro |
| `lib/features/occurrences/presentation/screens/active_occurrence_screen.dart` | L670 | Alerta de ocorrência bloqueada para edição | info/success |
| `lib/features/occurrences/presentation/screens/active_occurrence_screen.dart` | L680 | Alerta de falta de permissão de escrita | info/success |
| `lib/features/occurrences/presentation/screens/create_amendment_screen.dart` | L114 | Sucesso na criação de retificação | sucesso |
| `lib/features/occurrences/presentation/screens/create_amendment_screen.dart` | L126 | Erro controlado ao criar retificação | erro |
| `lib/features/occurrences/presentation/screens/create_amendment_screen.dart` | L132 | Erro genérico ao criar retificação | erro |
| `lib/features/occurrences/presentation/screens/edit_event_location_screen.dart` | L145 | Aviso de permissão de GPS negada | info/success |
| `lib/features/occurrences/presentation/screens/edit_event_location_screen.dart` | L176 | Erro ao obter endereço do GPS | erro |
| `lib/features/occurrences/presentation/screens/edit_event_location_screen.dart` | L239 | Erro ao gravar localização do evento | erro |
| `lib/features/occurrences/presentation/screens/edit_event_screen.dart` | L225 | Erro: horário do evento no futuro | info/success |
| `lib/features/occurrences/presentation/screens/edit_event_screen.dart` | L255 | Sucesso: coordenadas GPS capturadas | info/success |
| `lib/features/occurrences/presentation/screens/edit_event_screen.dart` | L265 | Erro: GPS indisponível no aparelho | erro |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L111 | Aviso: relato final obrigatório | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L124 | Aviso: resultado obrigatório | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L172 | Erro: microfone inacessível para áudio | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L189 | Aviso: texto necessário para IA | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L222 | Erro na chamada da IA assistiva | erro |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L587 | Erro: campos obrigatórios ausentes | erro |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L615 | Aviso: já aguarda assinaturas | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L655 | Alerta: ocorrência em fase de fechamento | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L730 | Erro: limite de tempo de transação | erro |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L740 | Erro genérico na finalização | erro |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L1715 | Erro: acesso à câmera/mídia negado | info/success |
| `lib/features/occurrences/presentation/screens/finalize_occurrence_screen.dart` | L1733 | Erro ao registrar foto na finalização | erro |
| `lib/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart` | L260 | Sucesso: hash copiado para clipboard | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart` | L483 | Sucesso: PDF compartilhado | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_confirmation_screen.dart` | L506 | Erro na exportação do PDF | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L151 | Sucesso: assinatura digital enviada | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L186 | Aviso: motivo de devolução obrigatório | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L230 | Aviso: motivo de recusa obrigatório | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L262 | Sucesso: participação aceita na equipe | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L265 | Erro ao aceitar participação | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L287 | Sucesso: participação recusada | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L290 | Erro ao recusar participação | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L315 | Sucesso: devolvido para correção | erro |
| `lib/features/occurrences/presentation/screens/occurrence_review_screen.dart` | L320 | Erro ao devolver para correção | erro |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L287 | Erro: sem assinatura pendente | erro |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L475 | Sucesso na operação de equipe | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L483 | Erro ao processar membro da guarnição | erro |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L497 | Sucesso ao alterar integrantes | info/success |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L505 | Erro no salvamento da equipe | erro |
| `lib/features/occurrences/presentation/screens/occurrence_team_screen.dart` | L522 | Mensagem de erro de assinatura | erro |
| `lib/features/occurrences/presentation/screens/start_occurrence_screen.dart` | L253 | Erro: horário de início inválido | info/success |
| `lib/features/occurrences/presentation/screens/start_occurrence_screen.dart` | L564 | Erro ao registrar ocorrência operacional | erro |
| `lib/features/occurrences/presentation/widgets/deadline_expired_dialog.dart` | L166 | Erro genérico na validação de prazo | erro |
| `lib/features/profiles/presentation/screens/handler_profile_page.dart` | L150 | Sucesso no encerramento de expediente | info/success |
| `lib/features/shifts/presentation/screens/active_shift_cockpit.dart` | L98 | Erro/Sucesso na entrada da viatura | erro |
| `lib/features/shifts/presentation/screens/active_shift_dashboard_screen.dart` | L235 | Erro ao forçar encerramento anterior | info/success |
| `lib/features/shifts/presentation/screens/live_tracking_screen.dart` | L69 | Erro ao atualizar coordenadas do mapa | erro |
| `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart` | L177 | Sucesso: convite de guarnição enviado | erro |
| `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart` | L182 | Erro no envio de convite de guarnição | erro |
| `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart` | L205 | Sucesso: resposta gravada na viatura | info/success |
| `lib/features/shifts/presentation/screens/vehicle_crew_profile_screen.dart` | L216 | Erro ao responder convite da guarnição | erro |
| `lib/features/shifts/presentation/screens/_dynamic_activity_sheet_environment_actions.dart` | L18 | Erro ao consultar endereço reverso | erro |
| `lib/features/shifts/presentation/screens/_dynamic_activity_sheet_environment_actions.dart` | L41 | Sucesso: dados meteorológicos salvos | sucesso |
| `lib/features/shifts/presentation/screens/_dynamic_activity_sheet_environment_actions.dart` | L53 | Erro ao consultar dados Open-Meteo | erro |
| `lib/features/shifts/presentation/screens/_dynamic_activity_sheet_status.dart` | L41 | Sucesso: status da atividade alterado | info/success |
| `lib/features/shifts/presentation/screens/_standard_sheet_controls.dart` | L166 | Sucesso: rastreamento de trajeto salvo | info/success |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1165 | Mensagem de erro de validação de dados | erro |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1218 | Alerta: trilha pendente local salva | info/success |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1297 | Sucesso no salvamento do log de B&C | erro |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1323 | Alerta: checkpoint atingido no treino | info/success |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1539 | Exibição de snackbar local customizado | erro |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1575 | Erro de validação no formulário | erro |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1601 | Erro ao salvar dados locais | erro |
| `lib/features/training/presentation/screens/busca_captura_formacao_screen.dart` | L1636 | Confirmação de descarte de trilha | info/success |
| `lib/features/training/presentation/screens/busca_captura_manutencao_screen.dart` | L833 | Sucesso no salvamento do treino B&C | sucesso |
| `lib/features/training/presentation/screens/busca_captura_manutencao_screen.dart` | L1117 | Alerta: trilha de manutenção pendente | info/success |
| `lib/features/training/presentation/screens/busca_captura_manutencao_screen.dart` | L1185 | Sucesso: trilha salva no histórico | sucesso |
| `lib/features/training/presentation/screens/busca_captura_manutencao_screen.dart` | L1190 | Erro: falha de envio para a nuvem | erro |
| `lib/features/training/presentation/screens/conditioning_screen.dart` | L845 | Validação: intensidade física ausente | info/success |
| `lib/features/training/presentation/screens/conditioning_screen.dart` | L951 | Sucesso: condicionamento registrado | sucesso |
| `lib/features/training/presentation/screens/conditioning_screen.dart` | L962 | Erro ao gravar treino físico | erro |
| `lib/features/training/presentation/screens/detection_maintenance_screen.dart` | L92 | Validação: resultado ausente | info/success |
| `lib/features/training/presentation/screens/detection_maintenance_screen.dart` | L126 | Sucesso: detecção registrada | info/success |
| `lib/features/training/presentation/screens/detection_maintenance_screen.dart` | L135 | Erro ao gravar treino de faro | erro |
| `lib/features/training/presentation/screens/gps_tracking_screen.dart` | L61 | Erro no sinal de localização do GPS | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L94 | Mensagem de erro de validação | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L122 | Mensagem de erro de salvamento | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L146 | Mensagem de erro na alteração | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L187 | Mensagem de erro ao remover item | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L284 | Mensagem de alerta de preenchimento | aviso |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L293 | Mensagem de erro de validação | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L321 | Sucesso no salvamento do currículo | info/success |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L329 | Erro ao salvar currículo | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L370 | Definição de snackbar customizado | erro |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L1163 | Sucesso: sessão de mordida gravada | info/success |
| `lib/features/training/presentation/screens/guard_protection_curriculum_screen.dart` | L1172 | Erro no registro de mordida/guarda | erro |
| `lib/features/training/presentation/screens/guard_protection_screen.dart` | L2496 | Validação: impulso instintivo ausente | info/success |
| `lib/features/training/presentation/screens/guard_protection_screen.dart` | L2540 | Sucesso: treino de proteção gravado | info/success |
| `lib/features/training/presentation/screens/guard_protection_screen.dart` | L2549 | Erro ao salvar proteção do cão | erro |
| `lib/features/training/presentation/screens/obedience_training_screen.dart` | L86 | Validação: comando trabalhado ausente | info/success |
| `lib/features/training/presentation/screens/obedience_training_screen.dart` | L95 | Validação: nota de obediência ausente | info/success |
| `lib/features/training/presentation/screens/obedience_training_screen.dart` | L128 | Sucesso: obediência registrada | info/success |
| `lib/features/training/presentation/screens/obedience_training_screen.dart` | L137 | Erro ao salvar obediência do cão | erro |
| `lib/features/training/presentation/screens/training_log_screen.dart` | L114 | Mensagem de carregamento dos dados | info/success |
| `lib/features/training/presentation/screens/training_log_screen.dart` | L129 | Alerta: K9 sem histórico de treinos | aviso |
| `lib/features/training/presentation/screens/training_log_screen.dart` | L168 | Erro na exportação do relatório PDF | erro |
| `lib/features/training/presentation/widgets/add_command_modal.dart` | L279 | Sucesso: comando de obediência salvo | sucesso |
| `lib/features/training/presentation/widgets/add_specialty_modal.dart` | L357 | Sucesso: especialidade de faro salva | sucesso |
| `lib/features/training/presentation/widgets/add_specialty_modal.dart` | L370 | Erro ao salvar especialidade de faro | erro |

*(Nota: As 69 ocorrências adicionais referem-se a telas repetidas ou tratamentos de formulários análogos nas features de ocorrência e treino).*

### (c) Casos Especiais (Migração Não Trivial)
Estes são os SnackBars que não podem ser substituídos simplesmente por um método estático do `AppFeedback` devido a lógicas particulares:
1. **SnackBar com Ação Interativa (`SnackBarAction`):**
   * **`busca_captura_formacao_screen.dart:L1224`** e **`busca_captura_formacao_screen.dart:L1329`**: O Snackbar detecta um rascunho de trilha GPS local e oferece o botão **`REVISAR`** para abrir o rascunho.
   * **`busca_captura_manutencao_screen.dart:L1123`**: Mesma funcionalidade do rascunho de trilha, exigindo o botão **`REVISAR`**.
   * *Motivo:* A API atual do `AppFeedback` não suporta a definição de um botão de ação interativo (`SnackBarAction`). Para migrar estes pontos, a API do `AppFeedback` precisará ser estendida para aceitar um parâmetro opcional de ação (`SnackBarAction? action` ou um callback de ação).
2. **Métodos Customizados de Exibição Local (`void _showSnackBar`):**
   * **`busca_captura_formacao_screen.dart:L1539`** e **`guard_protection_curriculum_screen.dart:L370`**: Estas telas encapsulam a criação do widget de SnackBar com propriedades locais (ex: cor de fundo passada como parâmetro na função auxiliar). A migração exigirá refatorar a assinatura destas funções locais para delegar para `AppFeedback.show()`.

---

## FRENTE 3 — Mensagem de Despedida ao Encerrar Turno

### (a) Comportamento Atual do Código
1. **Início do Encerramento:** 
   O encerramento é acionado pelo usuário na UI através de três pontos principais:
   * **`binomio_header.dart:L527`**: Menu lateral superior.
   * **`handler_profile_page.dart:L92`**: Botão de encerramento no perfil do condutor.
   * **`active_shift_dashboard_screen.dart:L228`**: Limpeza/encerramento forçado de turno anterior inativo em caso de falha de dados do K9.
2. **Fluxo na ViewModel:** 
   Todos invocam o método `shiftVM.endShift()` em `ShiftViewModel`. O fluxo faz o seguinte:
   * Define o estado de carregamento (`_isLoading = true`).
   * Chama o serviço do Firestore `_shiftService.endShift(resolvedHandlerId)`.
   * Executa a limpeza da sessão local do turno através de `_clearSession()`.
   * Cancela lembretes locais pendentes do FCM via `_pushNotifications.cancelShiftEndReminders()`.
3. **Persistência no Firestore:**
   O `ShiftService.endShift` executa uma transação no Firestore:
   * No documento **`active_shifts/{ra}`**, altera o campo `status` para `"ended"`, insere o timestamp `endedAt` e atualiza `updatedAt` com a hora do servidor. *(Importante: o documento permanece gravado para fins históricos, não é apagado).*
   * No documento do log histórico **`shift_logs/{shiftId}`**, repete a inserção de status `"ended"` e `endedAt`.
   * Sob a coleção **`vehicle_crews/{crewId}/members/{ra}`**, atualiza o status do membro correspondente para `"ended"` e preenche `left_at`.
   * **Se o condutor for o titular da viatura** (`crew_role == 'titular'`), atualiza o documento da guarnição em `vehicle_crews/{crewId}` setando o campo `active: false` e `ended_at`.

### (b) Evidências (Arquivos e Linhas)
* **Ação no cabeçalho:** [binomio_header.dart:L547-550](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/core/widgets/binomio_header.dart#L547-L550)
  ```dart
  await shiftVM.endShift();
  if (context.mounted) {
    _showSnack(context, 'Turno encerrado.');
  }
  ```
* **Ação na página de perfil:** [handler_profile_page.dart:L144-152](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/profiles/presentation/screens/handler_profile_page.dart#L144-L152)
  ```dart
  Future<void> _endShift(BuildContext context, ShiftViewModel shiftVM) async {
    HapticFeedback.mediumImpact();
    await shiftVM.endShift();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expediente encerrado')));
    }
  }
  ```
* **Implementação lógica no serviço:** [shift_service.dart:L335-378](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/shifts/data/shift_service.dart#L335-L378)
  ```dart
  Future<void> endShift(String handlerId) {
    final activeRef = _activeShiftDoc(handlerId);
    final endedAt = Timestamp.fromDate(DateTime.now());

    return _db.runTransaction((transaction) async {
      ...
      transaction.set(activeRef, {
        'status': 'ended',
        'endedAt': endedAt,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      ...
  ```

### (c) Lacunas e Solução Proposta
* **Lacuna:** A resposta visual ao fechar o turno é um **toast/snackbar cru** ("Turno encerrado." ou "Expediente encerrado"). Não há um feedback humanizado, personalizado ou de alta qualidade visual para marcar a desmobilização do GCM.
* **Sintoma Esperado:** O encerramento do expediente é tratado de forma seca e sem o padrão visual rico do design system da aplicação.
* **Ponto Exato de Inserção da Mensagem:**
  A UI deve ser alterada nos pontos de retorno do sucesso do encerramento para exibir uma mensagem de despedida estilizada com o `AppFeedback.success`:
  * No **`binomio_header.dart`** (linha 548):
    ```dart
    await shiftVM.endShift();
    if (context.mounted) {
      AppFeedback.success(
        context,
        'Expediente finalizado. Bom descanso, GCM!',
        title: 'Até logo',
      );
    }
    ```
  * No **`handler_profile_page.dart`** (linha 147):
    ```dart
    await shiftVM.endShift();
    if (context.mounted) {
      AppFeedback.success(
        context,
        'Expediente finalizado. Obrigado pelo serviço!',
        title: 'Até logo',
      );
    }
    ```

---

## FRENTE 4 — Convite de Guarnição Preso + Viatura não Encerra

### (a) Comportamento Atual do Ciclo de Vida do Convite
1. **Criação do Convite:** 
   O titular da viatura envia um convite chamando o Cloud Function `inviteVehicleCrewMember`. O Firestore cria um documento sob `vehicle_crews/{crewId}/members/{ra}` com `status: "pending"`, `role: "integrante"` e uma notificação de ação requerida do tipo `vehicle_crew_invitation`.
2. **Resposta do Convidado:** 
   O convidado responde chamando `respondVehicleCrewInvitation` no Cloud Functions:
   * **Se aceito:** O status do membro sob `members/{ra}` vai para `"accepted"`, a notificação é resolvida, os dados da viatura são inseridos/mesclados em seu `active_shifts/{ra}` e ele passa a fazer parte da guarnição.
   * **Se recusado:** O status do membro vai para `"declined"`, a notificação é resolvida e o motivo da recusa é gravado no banco de dados (`decline_reason`).
3. **Valores Possíveis de Status:**
   * `"titular"`: O condutor principal (criador da viatura).
   * `"pending"`: Convidado que ainda não respondeu ao convite.
   * `"accepted"`: Convidado que aceitou e faz parte da equipe da viatura.
   * `"declined"`: Convidado que recusou o convite.
   * `"ended"`: Condutor que encerrou o expediente (turno finalizado).

### (b) Evidências (Arquivos e Linhas)
* **Envio do convite no Cloud Functions:** [index.ts:L4307-4385](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L4307-L4385)
* **Escrita do status "pending":** [index.ts:L4350-4360](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L4350-L4360)
  ```typescript
  transaction.set(memberRef, {
    handler_id: handlerId,
    role: "integrante",
    status: "pending",
    invited_at: admin.firestore.FieldValue.serverTimestamp(),
    ...
  ```
* **Processamento de aceite/recusa no Cloud Functions:** [index.ts:L4387-4498](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L4387-L4498)
* **Validação de convites duplicados:** [index.ts:L4341-4344](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L4341-L4344)
  ```typescript
  const existingMember = membersSnap.docs.find((doc) => doc.id === handlerId)?.data();
  if (existingMember && ["titular", "accepted", "pending"].includes(String(existingMember.status ?? ""))) {
    throw new HttpsError("already-exists", "Condutor ja esta vinculado ou convidado.");
  }
  ```
* **Desativação condicional da viatura (apenas titular):** [shift_service.dart:L369-376](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/lib/features/shifts/data/shift_service.dart#L369-L376)
  ```dart
  if (activeData?['crew_role'] == 'titular') {
    transaction.set(_vehicleCrews.doc(crewId), {
      'active': false,
      'ended_at': endedAt,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  ```
* **Corte por retorno inalcançável (Código Morto em `checkOpenShiftsAndNotify`):** [index.ts:L7303-7305](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L7303-L7305)
  ```typescript
  return runShiftReminderScan(new Date());

  const now = new Date(); // <-- CÓDIGO MORTO (NUNCA EXECUTA)
  const maxOpenHours = 12;
  ```
* **Corte por retorno inalcançável (Código Morto em `scheduledCheckOpenShifts`):** [index.ts:L7420-7424](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L7420-L7424)
  ```typescript
  await runShiftReminderScan(new Date());
  return;

  logger.info("Running scheduled check for open shifts"); // <-- CÓDIGO MORTO (NUNCA EXECUTA)
  ```
* **Trigger do Cloud Functions que reage ao encerramento de turno:** [index.ts:L7258-7293](file:///c:/Projetos/canil_gcm_mobile_chatgpt/canil-gcm/functions/src/index.ts#L7258-L7293)
  ```typescript
  export const onActiveShiftUpdatedResolveReminders = onDocumentUpdated(
    { document: "active_shifts/{handlerId}", region },
    async (event) => {
      ...
      if (wasActive && (!isActive || endedAt !== null)) {
        await resolveShiftReminderNotificationsForKeys(...);
      }
    }
  );
  ```

### (c) Bugs e Lacunas Identificados

#### 1. Convite "Preso" Indefinidamente (Bug Conhecido)
* **Pergunta-chave:** Existe mecanismo de cancelamento/expiração de convite `"pending"`? **NÃO EXISTE**.
* **Sintoma:** Se o titular convidar um integrante e este nunca responder, o convite fica ativo para sempre no Firestore. Como a função de convite bloqueia novos convites para usuários que já estejam com status `"pending"`, o condutor convidado fica permanentemente bloqueado de ser associado a qualquer outra viatura até que ele decline o convite. O titular também não tem uma função para "cancelar" ou "retirar" o convite enviado.

#### 2. Viatura não Encerra se Auxiliar sair por Último (Bug de Lógica)
* **Segunda pergunta-chave:** Existe lógica de desativar a viatura quando o último membro encerra o expediente? **NÃO DE FORMA SEGURA**.
* **Sintoma:** A inativação da viatura (`'active': false`) é feita unicamente dentro de `endShift` se o papel do usuário logado for `'titular'`. 
  * Se o condutor **titular** encerrar o expediente mais cedo e os integrantes auxiliares permanecerem em patrulha, a viatura é marcada como **inativa instantaneamente**, mesmo com policiais operando dentro dela.
  * Se os auxiliares encerrarem o turno por último (depois que o titular já saiu do turno), a viatura **nunca** será desativada, pois o bloco que desativa o doc pai da viatura nunca será executado (já que o integrante auxiliar tem `crew_role != 'titular'`). A viatura ficará "ativa" infinitamente no banco do Firestore.

#### 3. Inexistência da Ação "Sair da Guarnição"
* **Sintoma:** Um integrante aceito não consegue "desembarcar" ou sair de uma viatura de forma avulsa durante o dia sem antes fechar o seu turno de trabalho inteiro (`endShift`). Não há rotinas do tipo `leaveCrew` ou `removeCrewMember`. A associação à viatura dura o turno completo do policial.

#### 4. Código Morto nas Rotinas de Varredura do Cloud Functions
* **Sintoma:** A rotina do cronjob `scheduledCheckOpenShifts` e a função chamável `checkOpenShiftsAndNotify` possuem um `return` precoce direcionando a execução para `runShiftReminderScan(new Date())`. Todo o código nativo subsequente (que executa a busca manual, cálculo de limite de 12 horas, leitura de tokens FCM individuais de `userData` e despacho direto de multicast) está inacessível. O serviço funciona apenas sob as regras agregadas de `runShiftReminderScan`.

---

## RESUMO DE ALTERAÇÕES NECESSÁRIAS (ROADMAP DE ENGENHARIA)

Para subsidiar a fase de correção das 4 frentes, este é o inventário de métodos e APIs que devem ser criados, alterados ou removidos.

### 1. Métodos a serem Criados/Modificados no Flutter (App)

* **`NotificationService` (`lib/core/services/notification_service.dart`)**
  * **Criar:** `Future<void> archiveAllNotices({required String userId})`
    * *Assinatura:* `Future<void> archiveAllNotices({required String userId}) async`
    * *Objetivo:* Localizar e atualizar em lote (WriteBatch) o campo `archived_at` com o timestamp atual para todas as notificações ativas (`archived_at == null`) pertencentes ao usuário que possuem `action_required == false` ou `resolved_at != null` (ou seja, são avisos).
* **`PendingScreen` (`lib/features/occurrences/presentation/screens/pending_screen.dart`)**
  * **Modificar UI:** Inserir um `TextButton` para acionar `archiveAllNotices` dentro de `_NotificationSection` (cerca de `pending_screen.dart:581`) quando `title == 'Avisos'` e `count > 0`.
* **`AppFeedback` (`lib/core/widgets/app_feedback.dart`)**
  * **Modificar:** Adicionar suporte a `SnackBarAction` na assinatura do método genérico `show` para viabilizar a migração das telas de B&C do treinamento.
    * *Nova Assinatura:* `static void show(BuildContext context, String message, {AppFeedbackType type, String? title, Duration duration, SnackBarAction? action})`
* **`ShiftService` (`lib/features/shifts/data/shift_service.dart`)**
  * **Modificar:** Alterar o método `endShift(String handlerId)` para não inativar a viatura com base exclusiva no papel de `'titular'`. O encerramento da viatura deve ser baseado no fato de que não existem mais membros em turno ativo vinculados àquele `crewId`.

### 2. Métodos a serem Criados/Modificados no Cloud Functions (Backend/TS)

* **`cancelVehicleCrewInvitation` (`functions/src/index.ts`)**
  * **Criar:** Novo endpoint do tipo `onCall`.
    * *Assinatura:* `export const cancelVehicleCrewInvitation = onCall({region}, async (request) => { ... })`
    * *Parâmetros:* `crew_id: string`, `handler_id: string` (ID do integrante cujo convite pendente será revogado).
    * *Validações:* Somente o titular da viatura pode cancelar convites. O status do membro deve ser `"pending"`. O método limpará a notificação correspondente do convidado e definirá o status do membro para `"cancelled"`.
* **`respondVehicleCrewInvitation` (`functions/src/index.ts`)**
  * **Modificar:** Adicionar lógica de expiração temporal de convites (ex: convites sem resposta com mais de 30 minutos recebem status `"expired"` no Firestore).
* **`checkOpenShiftsAndNotify` / `scheduledCheckOpenShifts` (`functions/src/index.ts`)**
  * **Saneamento:** Remover a linha de código morto de bypass precoce (`return runShiftReminderScan...`) ou expurgar as mais de 100 linhas inacessíveis redundantes se o fluxo consolidado da varredura estiver correto.
