import 'package:canil_gcm/features/health/domain/health_schedule_mutation_errors.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_mutation_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_schedule_revision.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Resultado de apresentação de uma mutação da Agenda (Gate 5).
///
/// Distingue:
/// - mutação bem-sucedida (com ou sem refresh posterior);
/// - falha de mutação;
/// - bloqueio por double-submit / item ocupado.
sealed class HealthScheduleMutationUiOutcome {
  const HealthScheduleMutationUiOutcome();
}

/// Mutação remota OK. [refreshFailed] separa falha de atualização pós-sucesso.
final class HealthScheduleMutationUiSuccess
    extends HealthScheduleMutationUiOutcome {
  const HealthScheduleMutationUiSuccess({
    required this.successMessage,
    required this.refreshFailed,
    required this.dogId,
    required this.scheduleId,
    required this.revision,
    required this.lifecycleStatus,
    required this.wasNoOp,
    this.refreshWarning,
  });

  factory HealthScheduleMutationUiSuccess.fromRemote({
    required HealthScheduleMutationSuccess remote,
    required String successMessage,
    required bool refreshFailed,
    String? refreshWarning,
  }) {
    return HealthScheduleMutationUiSuccess(
      successMessage: successMessage,
      refreshFailed: refreshFailed,
      dogId: remote.dogId,
      scheduleId: remote.scheduleId,
      revision: remote.revision,
      lifecycleStatus: remote.lifecycleStatus,
      wasNoOp: remote.wasNoOp,
      refreshWarning: refreshWarning,
    );
  }

  final String successMessage;
  final bool refreshFailed;
  final String? refreshWarning;
  final String dogId;
  final String scheduleId;
  final HealthScheduleRevision revision;
  final ScheduleLifecycleStatus lifecycleStatus;
  final bool wasNoOp;
}

/// Falha tipada mapeada para copy de UX.
final class HealthScheduleMutationUiFailure
    extends HealthScheduleMutationUiOutcome {
  const HealthScheduleMutationUiFailure({
    required this.failure,
    required this.userMessage,
    required this.shouldRefresh,
  });

  final HealthScheduleMutationFailure failure;
  final String userMessage;

  /// true → UI deve recarregar a agenda (notFound, conflict, already*, …).
  final bool shouldRefresh;
}

/// Segunda submissão bloqueada (double tap / item busy).
final class HealthScheduleMutationUiBlocked
    extends HealthScheduleMutationUiOutcome {
  const HealthScheduleMutationUiBlocked();
}
