import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_minimum_duration.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';

void main() {
  group('K9OpsLoadingDurationPolicy — política de tempo mínimo (800ms)', () {
    test(
      '1. Estado técnico ativo continua segurando visual independente de 800ms',
      () {
        expect(
          K9OpsLoadingDurationPolicy.shouldHoldVisualLoading(
            isTechnicalLoadingActive: true,
            isMinDurationElapsed: false,
          ),
          isTrue,
        );

        expect(
          K9OpsLoadingDurationPolicy.shouldHoldVisualLoading(
            isTechnicalLoadingActive: true,
            isMinDurationElapsed: true,
          ),
          isTrue,
        );
      },
    );

    test(
      '2. Estado técnico concluído antes de 800ms continua segurando visualmente',
      () {
        expect(
          K9OpsLoadingDurationPolicy.shouldHoldVisualLoading(
            isTechnicalLoadingActive: false,
            isMinDurationElapsed: false,
          ),
          isTrue,
        );
      },
    );

    test(
      '3. Estado técnico concluído E 800ms cumpridos encerra o hold visual',
      () {
        expect(
          K9OpsLoadingDurationPolicy.shouldHoldVisualLoading(
            isTechnicalLoadingActive: false,
            isMinDurationElapsed: true,
          ),
          isFalse,
        );
      },
    );

    test(
      '4. Resolve estado técnico ativo: validatingAccess quando isLoadingCurrentUser == true',
      () {
        final state = K9OpsLoadingDurationPolicy.resolveLoadingState(
          isLoadingCurrentUser: true,
          shiftIsLoading: false,
        );

        expect(state.stage, equals(K9OpsLoadingStage.validatingAccess));
        expect(state.progress, equals(0.35));
      },
    );

    test(
      '5. Resolve estado técnico ativo: syncingModules quando shiftIsLoading == true',
      () {
        final state = K9OpsLoadingDurationPolicy.resolveLoadingState(
          isLoadingCurrentUser: false,
          shiftIsLoading: true,
        );

        expect(state.stage, equals(K9OpsLoadingStage.syncingModules));
        expect(state.progress, equals(0.85));
      },
    );

    test(
      '6. Hold visual após término técnico exibe finalizing / 0.95 (nunca ready/1.0)',
      () {
        final state = K9OpsLoadingDurationPolicy.resolveLoadingState(
          isLoadingCurrentUser: false,
          shiftIsLoading: false,
        );

        expect(state.stage, equals(K9OpsLoadingStage.finalizing));
        expect(state.progress, equals(0.95));
        expect(state.stage, isNot(equals(K9OpsLoadingStage.ready)));
        expect(state.stage, isNot(equals(K9OpsLoadingStage.error)));
      },
    );
  });
}
