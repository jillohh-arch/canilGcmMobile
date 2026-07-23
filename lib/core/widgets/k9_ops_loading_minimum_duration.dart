import 'package:canil_gcm/core/widgets/k9_ops_loading_derivation.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';

/// Duração visual mínima oficial do loading K9 Ops Mobile (spec: 800ms).
const Duration k9OpsLoadingMinDuration = Duration(milliseconds: 800);

/// Helper puro para avaliação da política de tempo mínimo do loading Mobile.
class K9OpsLoadingDurationPolicy {
  /// Determina se a tela de loading deve continuar visível (modo de espera visual),
  /// mesmo que o estado técnico de bootstrap já tenha sido concluído.
  static bool shouldHoldVisualLoading({
    required bool isTechnicalLoadingActive,
    required bool isMinDurationElapsed,
  }) {
    // Se o estado técnico ainda está carregando, o loading permanece ativo.
    if (isTechnicalLoadingActive) return true;

    // Se o estado técnico terminou mas a duração mínima não passou, segura visualmente.
    return !isMinDurationElapsed;
  }

  /// Resolve o estado do K9OpsLoadingScreen durante o bootstrap.
  ///
  /// Se o estado técnico estiver ativo, usa o mapper técnico real.
  /// Se o estado técnico já terminou mas a janela mínima de 800ms ainda não decorreu,
  /// exibe [K9OpsLoadingStage.finalizing] com progresso 0.95.
  static K9OpsLoadingState resolveLoadingState({
    required bool isLoadingCurrentUser,
    required bool shiftIsLoading,
  }) {
    final isTechnicalActive = isLoadingCurrentUser || shiftIsLoading;

    if (isTechnicalActive) {
      return deriveK9OpsLoadingState(
        isLoadingCurrentUser: isLoadingCurrentUser,
        shiftIsLoading: shiftIsLoading,
      );
    }

    // Hold visual (técnico pronto, aguardando conclusão da janela de 800ms)
    return const K9OpsLoadingState(
      stage: K9OpsLoadingStage.finalizing,
      progress: 0.95,
    );
  }
}
