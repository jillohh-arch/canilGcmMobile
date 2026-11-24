import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_session.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_coverage.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_succession_state_machine.dart';

void main() {
  group('OccupancySuccessionStateMachine', () {
    OccupancySession _activeSession([String id = 'sess-sm-01']) =>
        OccupancySession.validated(
          sessionId: id,
          vehicleId: 'vh-sm',
          crewId: 'crew-sm',
          generation: 1,
          state: OccupancySessionState.active,
        );

    group('proposeSelfRegularizationRequest', () {
      test('transição válida de active para selfRegularizationRequested', () {
        final session = _activeSession();
        final transition = proposeSelfRegularizationRequest(session);

        expect(transition.accepted, isTrue);
        expect(
          transition.newState,
          OccupancySessionState.selfRegularizationRequested,
        );
      });

      test('rejeita se sessão já está em selfRegularizationRequested', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeSelfRegularizationRequest(session);

        expect(transition.accepted, isFalse);
        expect(
          transition.newState,
          OccupancySessionState.selfRegularizationRequested,
        );
      });

      test('rejeita se sessão está stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.stale,
        );
        final transition = proposeSelfRegularizationRequest(session);

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('rejeita se sessão está em coverageValidated', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.coverageValidated,
        );
        final transition = proposeSelfRegularizationRequest(session);

        expect(transition.accepted, isFalse);
      });
    });

    group('proposeCoverageEvaluation', () {
      test('BLOCKING resulta em successionDenied', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.blocking,
        );

        expect(transition.accepted, isTrue);
        expect(
          transition.newState,
          OccupancySessionState.successionDenied,
        );
      });

      test('INDETERMINATE não permite avançar', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.indeterminate,
        );

        expect(transition.accepted, isFalse);
        expect(
          transition.newState,
          OccupancySessionState.selfRegularizationRequested,
        );
      });

      test('PROVEN_CLEAR resulta em coverageValidated', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.provenClear,
        );

        expect(transition.accepted, isTrue);
        expect(
          transition.newState,
          OccupancySessionState.coverageValidated,
        );
      });

      test('rejeita avaliação de cobertura se estado não é selfRegularizationRequested', () {
        final session = _activeSession(); // active
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.provenClear,
        );

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.active);
      });

      test('rejeita avaliação de cobertura se sessão está stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.stale,
        );
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.provenClear,
        );

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.stale);
      });
    });

    group('proposeSuccessionPermission', () {
      test('coverageValidated → successionAllowed', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.coverageValidated,
        );
        final transition = proposeSuccessionPermission(session);

        expect(transition.accepted, isTrue);
        expect(
          transition.newState,
          OccupancySessionState.successionAllowed,
        );
      });

      test('não libera automaticamente; apenas marca elegibilidade', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.coverageValidated,
        );
        final transition = proposeSuccessionPermission(session);

        // A transição é aceita, mas NÃO cria sucessor nem libera viatura.
        expect(transition.accepted, isTrue);
        expect(
          transition.newState,
          OccupancySessionState.successionAllowed,
        );
        // Sucessão efetiva depende de confirmação futura de autoridade.
      });

      test('rejeita se estado não é coverageValidated', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeSuccessionPermission(session);

        expect(transition.accepted, isFalse);
      });

      test('rejeita se sessão está stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.stale,
        );
        final transition = proposeSuccessionPermission(session);

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.stale);
      });
    });

    group('proteção contra comandos anteriores e repetição', () {
      test('sessão successionAllowed não pode voltar a coverageValidated', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionAllowed,
        );

        // Tentar reavaliar cobertura após sucessão permitida.
        final transition = proposeCoverageEvaluation(
          session,
          CoverageVerdict.provenClear,
        );

        expect(transition.accepted, isFalse);
        expect(
          transition.newState,
          OccupancySessionState.successionAllowed,
        );
      });

      test('repetir proposeSuccessionPermission em successionAllowed é rejeitado', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionAllowed,
        );
        final transition = proposeSuccessionPermission(session);

        expect(transition.accepted, isFalse);
      });

      test('sessão successionDenied não pode progredir', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionDenied,
        );

        final transition = proposeSuccessionPermission(session);
        expect(transition.accepted, isFalse);

        final transition2 = proposeSelfRegularizationRequest(session);
        expect(transition2.accepted, isFalse);
      });
    });

    group('proposeStale e proposeConflict', () {
      test('active pode ser marcado stale', () {
        final session = _activeSession();
        final transition = proposeStale(session);

        expect(transition.accepted, isTrue);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('selfRegularizationRequested pode ser marcado stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.selfRegularizationRequested,
        );
        final transition = proposeStale(session);

        expect(transition.accepted, isTrue);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('coverageValidated pode ser marcado stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.coverageValidated,
        );
        final transition = proposeStale(session);

        expect(transition.accepted, isTrue);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('successionAllowed NÃO pode ser marcado stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionAllowed,
        );
        final transition = proposeStale(session);

        expect(transition.accepted, isFalse);
        expect(
          transition.newState,
          OccupancySessionState.successionAllowed,
        );
      });

      test('successionDenied NÃO pode ser marcado stale', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionDenied,
        );
        final transition = proposeStale(session);

        expect(transition.accepted, isFalse);
      });

      test('já stale: repetir proposeStale é rejeitado', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.stale,
        );
        final transition = proposeStale(session);

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('active pode ser marcado conflicted', () {
        final session = _activeSession();
        final transition = proposeConflict(session);

        expect(transition.accepted, isTrue);
        expect(transition.newState, OccupancySessionState.conflicted);
      });

      test('stale não pode ser marcado conflicted', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.stale,
        );
        final transition = proposeConflict(session);

        expect(transition.accepted, isFalse);
        expect(transition.newState, OccupancySessionState.stale);
      });

      test('successionAllowed não pode ser marcado conflicted', () {
        final session = _activeSession().copyWithState(
          OccupancySessionState.successionAllowed,
        );
        final transition = proposeConflict(session);

        expect(transition.accepted, isFalse);
      });
    });

    group('fluxo completo válido', () {
      test('active → selfRegReq → coverageValidated → successionAllowed', () {
        var session = _activeSession();

        // Passo 1: solicitar auto-regularização.
        final t1 = proposeSelfRegularizationRequest(session);
        expect(t1.accepted, isTrue);
        session = session.copyWithState(t1.newState);

        // Passo 2: avaliar cobertura com PROVEN_CLEAR.
        final t2 = proposeCoverageEvaluation(
          session,
          CoverageVerdict.provenClear,
        );
        expect(t2.accepted, isTrue);
        session = session.copyWithState(t2.newState);

        // Passo 3: permitir sucessão.
        final t3 = proposeSuccessionPermission(session);
        expect(t3.accepted, isTrue);
        expect(t3.newState, OccupancySessionState.successionAllowed);
      });
    });
  });
}