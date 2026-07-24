import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_derivation.dart';
import 'package:canil_gcm/core/widgets/k9_ops_loading_stage.dart';

void main() {
  group('deriveK9OpsLoadingState — derivação de estágio e progresso', () {
    test(
      '1. isLoadingCurrentUser == true -> validatingAccess (progress 0.35)',
      () {
        final state = deriveK9OpsLoadingState(
          isLoadingCurrentUser: true,
          shiftIsLoading: false,
        );

        expect(state.stage, equals(K9OpsLoadingStage.validatingAccess));
        expect(state.progress, equals(0.35));
      },
    );

    test(
      '2. shiftIsLoading == true (e user carregado) -> syncingModules (progress 0.85)',
      () {
        final state = deriveK9OpsLoadingState(
          isLoadingCurrentUser: false,
          shiftIsLoading: true,
        );

        expect(state.stage, equals(K9OpsLoadingStage.syncingModules));
        expect(state.progress, equals(0.85));
      },
    );

    test('3. nenhum loading ativo -> finalizing (progress 0.95)', () {
      final state = deriveK9OpsLoadingState(
        isLoadingCurrentUser: false,
        shiftIsLoading: false,
      );

      expect(state.stage, equals(K9OpsLoadingStage.finalizing));
      expect(state.progress, equals(0.95));
    });

    test(
      '4. Prioridade: isLoadingCurrentUser prevalece sobre shiftIsLoading',
      () {
        final state = deriveK9OpsLoadingState(
          isLoadingCurrentUser: true,
          shiftIsLoading: true,
        );

        expect(state.stage, equals(K9OpsLoadingStage.validatingAccess));
        expect(state.progress, equals(0.35));
      },
    );

    test(
      '5. Progress nunca retorna 1.0, ready ou error na derivação de bootstrap',
      () {
        final inputs = [
          (true, true),
          (true, false),
          (false, true),
          (false, false),
        ];

        for (final (user, shift) in inputs) {
          final state = deriveK9OpsLoadingState(
            isLoadingCurrentUser: user,
            shiftIsLoading: shift,
          );

          expect(state.progress, lessThan(1.0));
          expect(state.stage, isNot(equals(K9OpsLoadingStage.ready)));
          expect(state.stage, isNot(equals(K9OpsLoadingStage.error)));
        }
      },
    );
  });
}
