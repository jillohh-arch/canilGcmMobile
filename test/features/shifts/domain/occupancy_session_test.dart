import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_session.dart';

void main() {
  group('OccupancySession', () {
    test('cria sessão válida com geração 1 e sem predecessor', () {
      final session = OccupancySession.validated(
        sessionId: 'sess-001',
        vehicleId: 'vh-10',
        crewId: 'crew-alpha',
        generation: 1,
        state: OccupancySessionState.active,
      );

      expect(session.sessionId, 'sess-001');
      expect(session.vehicleId, 'vh-10');
      expect(session.crewId, 'crew-alpha');
      expect(session.generation, 1);
      expect(session.predecessorSessionId, isNull);
      expect(session.state, OccupancySessionState.active);
    });

    test('rejeita geração <= 0', () {
      expect(
        () => OccupancySession.validated(
          sessionId: 'sess-002',
          vehicleId: 'vh-10',
          crewId: 'crew-alpha',
          generation: 0,
          state: OccupancySessionState.active,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => OccupancySession.validated(
          sessionId: 'sess-003',
          vehicleId: 'vh-10',
          crewId: 'crew-alpha',
          generation: -1,
          state: OccupancySessionState.active,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejeita identificadores vazios', () {
      expect(
        () => OccupancySession.validated(
          sessionId: '',
          vehicleId: 'vh-10',
          crewId: 'crew-alpha',
          generation: 1,
          state: OccupancySessionState.active,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => OccupancySession.validated(
          sessionId: 'sess-004',
          vehicleId: '',
          crewId: 'crew-alpha',
          generation: 1,
          state: OccupancySessionState.active,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => OccupancySession.validated(
          sessionId: 'sess-005',
          vehicleId: 'vh-10',
          crewId: '',
          generation: 1,
          state: OccupancySessionState.active,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('createSuccessor incrementa exatamente 1 geração', () {
      final original = OccupancySession.validated(
        sessionId: 'sess-010',
        vehicleId: 'vh-20',
        crewId: 'crew-beta',
        generation: 3,
        state: OccupancySessionState.active,
      );

      final successor = original.createSuccessor(
        newSessionId: 'sess-011',
        newCrewId: 'crew-gamma',
      );

      expect(successor.generation, 4);
      expect(successor.predecessorSessionId, 'sess-010');
      expect(successor.vehicleId, 'vh-20'); // mesma viatura
      expect(successor.crewId, 'crew-gamma'); // nova guarnição
      expect(successor.state, OccupancySessionState.active);
    });

    test('createSuccessor rejeita sessão stale', () {
      final stale = OccupancySession.validated(
        sessionId: 'sess-020',
        vehicleId: 'vh-30',
        crewId: 'crew-delta',
        generation: 2,
        state: OccupancySessionState.stale,
      );

      expect(
        () => stale.createSuccessor(
          newSessionId: 'sess-021',
          newCrewId: 'crew-epsilon',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('createSuccessor rejeita estados terminais', () {
      for (final terminalState in [
        OccupancySessionState.successionAllowed,
        OccupancySessionState.successionDenied,
        OccupancySessionState.conflicted,
      ]) {
        final session = OccupancySession.validated(
          sessionId: 'sess-term-$terminalState',
          vehicleId: 'vh-40',
          crewId: 'crew-zeta',
          generation: 1,
          state: terminalState,
        );

        expect(
          () => session.createSuccessor(
            newSessionId: 'sess-next-$terminalState',
            newCrewId: 'crew-eta',
          ),
          throwsA(isA<StateError>()),
          reason: 'Should reject successor from $terminalState',
        );
      }
    });

    test('copyWithState preserva identidade e imutabilidade', () {
      final original = OccupancySession.validated(
        sessionId: 'sess-030',
        vehicleId: 'vh-50',
        crewId: 'crew-theta',
        generation: 5,
        state: OccupancySessionState.active,
        predecessorSessionId: 'sess-029',
      );

      final modified = original.copyWithState(
        OccupancySessionState.selfRegularizationRequested,
      );

      // Original não muda.
      expect(original.state, OccupancySessionState.active);

      // Cópia tem novo estado mas mesma identidade.
      expect(modified.state, OccupancySessionState.selfRegularizationRequested);
      expect(modified.sessionId, original.sessionId);
      expect(modified.vehicleId, original.vehicleId);
      expect(modified.crewId, original.crewId);
      expect(modified.generation, original.generation);
      expect(modified.predecessorSessionId, original.predecessorSessionId);
    });

    test('igualdade e hashCode por valor', () {
      final a = OccupancySession.validated(
        sessionId: 'sess-eq',
        vehicleId: 'vh-eq',
        crewId: 'crew-eq',
        generation: 1,
        state: OccupancySessionState.active,
      );

      final b = OccupancySession.validated(
        sessionId: 'sess-eq',
        vehicleId: 'vh-eq',
        crewId: 'crew-eq',
        generation: 1,
        state: OccupancySessionState.active,
      );

      final c = OccupancySession.validated(
        sessionId: 'sess-eq',
        vehicleId: 'vh-eq',
        crewId: 'crew-eq',
        generation: 2, // diferente
        state: OccupancySessionState.active,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('sucessão não assume crewId globalmente único entre gerações', () {
      final gen1 = OccupancySession.validated(
        sessionId: 'sess-reuse-1',
        vehicleId: 'vh-reuse',
        crewId: 'crew-same',
        generation: 1,
        state: OccupancySessionState.active,
      );

      // Mesma crewId na geração seguinte é permitido.
      final gen2 = gen1.createSuccessor(
        newSessionId: 'sess-reuse-2',
        newCrewId: 'crew-same',
      );

      expect(gen2.generation, 2);
      expect(gen2.crewId, 'crew-same');
      expect(gen2.predecessorSessionId, 'sess-reuse-1');
    });
  });
}