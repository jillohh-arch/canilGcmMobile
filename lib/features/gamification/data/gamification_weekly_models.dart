part of 'gamification_service.dart';

const List<_WeeklyMissionDefinition> _weeklyMissions = [
  _WeeklyMissionDefinition(
    id: 'treino_da_semana',
    title: 'Treino em Dia',
    description: 'Acumule 2 horas de treino na semana.',
    target: 2,
    unitLabel: 'horas',
    rewardXp: 80,
  ),
  _WeeklyMissionDefinition(
    id: 'turno_da_semana',
    title: 'Presença em Campo',
    description: 'Registre 2 turnos operacionais nesta semana.',
    target: 2,
    unitLabel: 'turnos',
    rewardXp: 60,
  ),
  _WeeklyMissionDefinition(
    id: 'ocorrencia_da_semana',
    title: 'Resposta Operacional',
    description: 'Conclua 1 ocorrência com resultado registrado na semana.',
    target: 1,
    unitLabel: 'ocorrência',
    rewardXp: 120,
  ),
  _WeeklyMissionDefinition(
    id: 'cuidado_da_semana',
    title: 'Cuidado Constante',
    description: 'Registre 2 ações de saúde ou manejo do K9 na semana.',
    target: 2,
    unitLabel: 'ações',
    rewardXp: 50,
  ),
];

class _WeeklyMissionDefinition {
  final String id;
  final String title;
  final String description;
  final int target;
  final String unitLabel;
  final int rewardXp;

  const _WeeklyMissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.unitLabel,
    required this.rewardXp,
  });
}

class _WeeklyMetrics {
  final DateTime weekStart;
  final String weekKey;
  final int weeklyShiftCount;
  final int weeklyTrainingHours;
  final int weeklyConcludedIncidents;
  final int weeklyHealthActions;
  final List<String> claimedMissionIds;

  const _WeeklyMetrics({
    required this.weekStart,
    required this.weekKey,
    required this.weeklyShiftCount,
    required this.weeklyTrainingHours,
    required this.weeklyConcludedIncidents,
    required this.weeklyHealthActions,
    required this.claimedMissionIds,
  });
}
