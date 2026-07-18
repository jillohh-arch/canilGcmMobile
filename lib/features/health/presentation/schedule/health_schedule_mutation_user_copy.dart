import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';

/// Copy UX das mutações da Agenda Preventiva (Gate 5).
///
/// Não expõe codes Firebase, stack ou detalhes de operationId/fingerprint.
abstract final class HealthScheduleMutationUserCopy {
  HealthScheduleMutationUserCopy._();

  // ── Entrada / formulários ──────────────────────────────────────────────
  static const addToSchedule = 'Adicionar à agenda';
  static const addScheduleCta = 'Adicionar agendamento';
  static const createFormTitle = 'Adicionar à agenda';
  static const editFormTitle = 'Editar item da agenda';
  static const saveLabel = 'SALVAR';
  static const savingLabel = 'SALVANDO...';
  static const fieldType = 'Tipo do cuidado';
  static const fieldTitle = 'Título';
  static const fieldScheduledFor = 'Agendado para';
  static const fieldDueUntil = 'Prazo limite (opcional)';
  static const fieldNotes = 'Observações (opcional)';

  /// Apresentação amigável; wire continua America/Sao_Paulo.
  static const fieldTimezoneHint = 'Horário de Brasília';
  static const typeSheetTitle = 'Tipo do agendamento';
  static const typeManualHint = 'Item manual';
  static const titleRequired = 'Informe um título.';
  static const scheduledForRequired = 'Informe a data e hora do agendamento.';
  static const scheduledForInPast =
      'O agendamento deve ser para o momento atual ou para o futuro.';
  static const dueUntilBeforeScheduled =
      'O prazo não pode ser anterior ao horário agendado.';
  static const typeRequired = 'Selecione o tipo do item.';

  // ── Menu ───────────────────────────────────────────────────────────────
  static const actionEdit = 'Editar';
  static const actionComplete = 'Concluir';
  static const actionCancel = 'Cancelar';
  static const generatedAutomatically = 'Gerado automaticamente';

  // ── Complete ───────────────────────────────────────────────────────────
  static const completeTitle = 'Concluir item da agenda?';
  static const completeBody =
      'Esta ação marcará o item como concluído e atualizará a agenda.';
  static const completeConfirm = 'Concluir';
  static const completeDismiss = 'Voltar';

  // ── Cancel ─────────────────────────────────────────────────────────────
  static const cancelSheetTitle = 'Cancelar item da agenda';
  static const cancelReasonLabel = 'Motivo do cancelamento';
  static const cancelReasonRequired = 'Informe o motivo do cancelamento.';
  static const cancelReasonTooLong = 'O motivo excede o limite permitido.';
  static const cancelConfirm = 'Cancelar item';
  static const cancelDismiss = 'Voltar';

  // ── Sucesso ────────────────────────────────────────────────────────────
  static const successCreated = 'Item adicionado à agenda.';
  static const successUpdated = 'Item atualizado.';
  static const successCompleted = 'Item concluído.';
  static const successCancelled = 'Item cancelado.';

  // ── Refresh pós-sucesso ────────────────────────────────────────────────
  static const refreshFailedAfterSuccess =
      'Alteração salva, mas não foi possível atualizar a agenda agora. '
      'Puxe para atualizar novamente.';

  // ── Conflito / not-found ───────────────────────────────────────────────
  static const conflictMessage =
      'Este item foi atualizado em outro dispositivo ou sessão. '
      'A agenda foi recarregada para mostrar a versão mais recente.';
  static const conflictShort =
      'Este item foi alterado em outra sessão. A agenda foi atualizada.';
  static const notFoundMessage =
      'Este item não existe mais. A agenda será atualizada.';

  // ── Empty ──────────────────────────────────────────────────────────────
  static const emptyAddHint = 'Adicione um cuidado preventivo manualmente.';

  /// Mapeia falha tipada → mensagem segura para o usuário.
  static String messageFor(HealthScheduleMutationFailure failure) {
    return switch (failure) {
      HealthScheduleMutationUnauthenticated() =>
        'Sua sessão expirou. Entre novamente para continuar.',
      HealthScheduleMutationPermissionDenied() =>
        'Você não tem permissão para realizar esta ação.',
      HealthScheduleMutationNotFound() => notFoundMessage,
      HealthScheduleMutationConflict() => conflictShort,
      HealthScheduleMutationIdempotencyConflict() =>
        'Não foi possível confirmar esta operação com segurança. '
            'Atualize a agenda e tente novamente.',
      HealthScheduleMutationAlreadyCompleted() => 'Este item já foi concluído.',
      HealthScheduleMutationAlreadyCancelled() => 'Este item já foi cancelado.',
      HealthScheduleMutationInvalidTransition() =>
        'Esta ação não é mais válida para o estado atual do item.',
      HealthScheduleMutationValidation(:final message) => _validationMessage(
        message,
      ),
      HealthScheduleMutationIntegrity() =>
        'Não foi possível validar os dados deste item. '
            'Atualize a agenda e tente novamente.',
      HealthScheduleMutationOffline() =>
        'Sem conexão. Verifique sua internet e tente novamente.',
      HealthScheduleMutationWritesNotEnabled() =>
        'As alterações da agenda ainda não estão disponíveis.',
      HealthScheduleMutationUnexpected() =>
        'Não foi possível concluir a operação. Tente novamente.',
    };
  }

  /// Falhas que devem disparar refresh da agenda após feedback.
  static bool shouldRefreshAfterFailure(HealthScheduleMutationFailure failure) {
    return switch (failure) {
      HealthScheduleMutationNotFound() => true,
      HealthScheduleMutationConflict() => true,
      HealthScheduleMutationAlreadyCompleted() => true,
      HealthScheduleMutationAlreadyCancelled() => true,
      HealthScheduleMutationInvalidTransition() => true,
      _ => false,
    };
  }

  static String _validationMessage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) {
      return 'Verifique os campos e tente novamente.';
    }
    // Evita vazar codes técnicos longos; se parecer código interno, genérico.
    if (t.contains('_') && !t.contains(' ')) {
      return 'Verifique os campos e tente novamente.';
    }
    return t;
  }
}
