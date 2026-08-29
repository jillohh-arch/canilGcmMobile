/// Copy institucional da Agenda Preventiva (Fase 4B).
abstract final class HealthScheduleUserCopy {
  static const title = 'AGENDA PREVENTIVA';

  static String subtitle(String dogName) =>
      'Cuidados programados para $dogName';

  static const loadingMessage = 'Carregando agenda preventiva';
  static const emptyTitle = 'Nenhum cuidado programado';
  static const emptyMessage =
      'Os próximos compromissos preventivos do K9 aparecerão aqui.';
  static const errorTitle = 'Não foi possível carregar a agenda';
  static const offlineTitle = 'Sem conexão';
  static const offlineMessage =
      'Não foi possível atualizar a agenda. Verifique a conexão e tente de novo.';
  static const retryLabel = 'Tentar novamente';
  static const refreshFailedPrefix = 'Falha ao atualizar';

  static const sectionAttention = 'REQUER ATENÇÃO';
  static const sectionPending = 'PENDENTES';
  static const sectionToday = 'HOJE';
  static const sectionUpcoming = 'PRÓXIMOS';
  static const sectionScheduled = 'PROGRAMADOS';

  static const kpiPending = 'Pendências';
  static const kpiToday = 'Hoje';
  static const kpiUpcoming = 'Próximos';
  static const kpiOverdue = 'Atrasados';

  /// Subtítulos compactos dos KPIs (sem afirmar janela institucional fixa).
  static const kpiPendingHint = 'Necessitam atenção';
  static const kpiTodayHint = 'Eventos previstos';
  static const kpiUpcomingHint = 'Agendados';
  static const kpiOverdueHint = 'Requer ação';

  static const statusOverdue = 'Atrasado';
  static const statusPending = 'Pendente';
  static const statusToday = 'Hoje';
  static const statusUpcoming = 'Próximo';
  static const statusScheduled = 'Programado';
  static const statusCompleted = 'Concluído';
  static const statusCancelled = 'Cancelado';
}
