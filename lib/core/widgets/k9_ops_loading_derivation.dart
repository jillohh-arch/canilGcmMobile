import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';

/// Resultado da derivação de estado visual do loading oficial do K9 Ops (Mobile).
class K9OpsLoadingState {
  final K9OpsLoadingStage stage;
  final double progress;

  const K9OpsLoadingState({required this.stage, required this.progress});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is K9OpsLoadingState &&
          runtimeType == other.runtimeType &&
          stage == other.stage &&
          progress == other.progress;

  @override
  int get hashCode => stage.hashCode ^ progress.hashCode;

  @override
  String toString() => 'K9OpsLoadingState(stage: $stage, progress: $progress)';
}

/// Deriva o estágio e progresso do loading oficial a partir dos estados reais de bootstrap.
///
/// Regras de prioridade:
/// 1. `isLoadingCurrentUser == true`
///    -> [K9OpsLoadingStage.validatingAccess], progress: 0.35
/// 2. `shiftIsLoading == true`
///    -> [K9OpsLoadingStage.syncingModules], progress: 0.85
/// 3. nenhum dos dois
///    -> [K9OpsLoadingStage.finalizing], progress: 0.95
K9OpsLoadingState deriveK9OpsLoadingState({
  required bool isLoadingCurrentUser,
  required bool shiftIsLoading,
}) {
  if (isLoadingCurrentUser) {
    return const K9OpsLoadingState(
      stage: K9OpsLoadingStage.validatingAccess,
      progress: 0.35,
    );
  }

  if (shiftIsLoading) {
    return const K9OpsLoadingState(
      stage: K9OpsLoadingStage.syncingModules,
      progress: 0.85,
    );
  }

  return const K9OpsLoadingState(
    stage: K9OpsLoadingStage.finalizing,
    progress: 0.95,
  );
}
