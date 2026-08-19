import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_readiness_convergence.dart';

/// B4-R.C3 — prova causal local e marcador de generation.
///
/// Autoridade: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md`.
void main() {
  HealthReadinessServerConvergenceReport server(
    HealthReadinessServerConvergence status, {
    int required = 42,
    int? observed,
  }) => HealthReadinessServerConvergenceReport(
    status: status,
    requiredGeneration: required,
    observedGeneration: observed,
  );

  HealthReadinessConvergenceOutcome decide({
    required HealthReadinessServerConvergence status,
    required bool localReady,
    required int? localGeneration,
    int required = 42,
  }) => decideHealthReadinessConvergence(
    serverReport: server(status, required: required),
    observedMarker: HealthReadinessCausalMarker(
      isReady: localReady,
      generation: localGeneration,
    ),
  ).outcome;

  group('marcador causal — leitura fail-closed', () {
    test('generation válida é lida como está', () {
      final marker = HealthReadinessCausalMarker.fromDocument({
        'projection_status': 'ready',
        'projection_generation': 42,
      });
      expect(marker.isReady, isTrue);
      expect(marker.generation, 42);
    });

    test('ausente, nulo ou malformado nunca vira 0', () {
      final cases = <Object?>[
        null,
        0,
        -3,
        1.5,
        '7',
        true,
        <String, Object?>{},
        <int>[42],
      ];
      for (final raw in cases) {
        final marker = HealthReadinessCausalMarker.fromDocument({
          'projection_status': 'ready',
          'projection_generation': raw,
        });
        expect(
          marker.generation,
          isNull,
          reason: 'deveria falhar fechado para: $raw',
        );
      }
      // Chave completamente ausente.
      expect(
        HealthReadinessCausalMarker.fromDocument({
          'projection_status': 'ready',
        }).generation,
        isNull,
      );
      // Documento inexistente.
      expect(HealthReadinessCausalMarker.fromDocument(null).generation, isNull);
      expect(HealthReadinessCausalMarker.fromDocument(null).isReady, isFalse);
    });

    test('inteiro grande seguro é aceito', () {
      final marker = HealthReadinessCausalMarker.fromDocument({
        'projection_status': 'ready',
        'projection_generation': 9007199254740990,
      });
      expect(marker.generation, 9007199254740990);
    });

    test('projection_status diferente de ready não é ready', () {
      for (final status in ['unavailable', null, 'READY', 'pending']) {
        expect(
          HealthReadinessCausalMarker.fromDocument({
            'projection_status': status,
            'projection_generation': 42,
          }).isReady,
          isFalse,
          reason: 'status: $status',
        );
      }
    });
  });

  group('prova local — >= e não igualdade', () {
    test('observed == required confirma', () {
      expect(
        decide(
          status: HealthReadinessServerConvergence.confirmed,
          localReady: true,
          localGeneration: 42,
        ),
        HealthReadinessConvergenceOutcome.converged,
      );
    });

    test('observed > required confirma', () {
      expect(
        decide(
          status: HealthReadinessServerConvergence.confirmed,
          localReady: true,
          localGeneration: 43,
        ),
        HealthReadinessConvergenceOutcome.converged,
      );
    });

    test('observed < required não confirma', () {
      expect(
        decide(
          status: HealthReadinessServerConvergence.confirmed,
          localReady: true,
          localGeneration: 41,
        ),
        HealthReadinessConvergenceOutcome.notConfirmed,
      );
    });
  });

  group('precedência: prova local é a autoridade final', () {
    test(
      'UPGRADE — servidor unavailable + READY local mais novo -> converged',
      () {
        // Entre a resposta HTTP e a releitura, uma projeção READY 43 commitou.
        expect(
          decide(
            status: HealthReadinessServerConvergence.unavailable,
            localReady: true,
            localGeneration: 43,
          ),
          HealthReadinessConvergenceOutcome.converged,
        );
      },
    );

    test(
      'UPGRADE — servidor not_confirmed + READY local >= G -> converged',
      () {
        expect(
          decide(
            status: HealthReadinessServerConvergence.notConfirmed,
            localReady: true,
            localGeneration: 42,
          ),
          HealthReadinessConvergenceOutcome.converged,
        );
      },
    );

    test(
      'DOWNGRADE — servidor confirmed + local unavailable -> unavailable',
      () {
        // O marcador 42 sobrevive como last-known-good, mas o estado atual não é
        // ready: renderizar convergido aqui usaria uma fotografia antiga.
        expect(
          decide(
            status: HealthReadinessServerConvergence.confirmed,
            localReady: false,
            localGeneration: 42,
          ),
          HealthReadinessConvergenceOutcome.unavailable,
        );
      },
    );

    test('marcador >= required com estado local unavailable nunca confirma', () {
      expect(
        decide(
          status: HealthReadinessServerConvergence.confirmed,
          localReady: false,
          localGeneration: 99,
        ),
        HealthReadinessConvergenceOutcome.unavailable,
      );
    });
  });

  group('matriz completa de classificação local', () {
    test('10 casos congelados', () {
      final cases = <String, HealthReadinessConvergenceOutcome>{};

      void check(
        String label,
        HealthReadinessConvergenceOutcome expected, {
        required HealthReadinessServerConvergence status,
        required bool localReady,
        required int? localGeneration,
      }) {
        final actual = decide(
          status: status,
          localReady: localReady,
          localGeneration: localGeneration,
        );
        expect(actual, expected, reason: label);
        cases[label] = actual;
      }

      check(
        'confirmed + local READY == G',
        HealthReadinessConvergenceOutcome.converged,
        status: HealthReadinessServerConvergence.confirmed,
        localReady: true,
        localGeneration: 42,
      );
      check(
        'confirmed + local READY > G',
        HealthReadinessConvergenceOutcome.converged,
        status: HealthReadinessServerConvergence.confirmed,
        localReady: true,
        localGeneration: 43,
      );
      check(
        'unavailable + local READY > G',
        HealthReadinessConvergenceOutcome.converged,
        status: HealthReadinessServerConvergence.unavailable,
        localReady: true,
        localGeneration: 43,
      );
      check(
        'not_confirmed + local READY >= G',
        HealthReadinessConvergenceOutcome.converged,
        status: HealthReadinessServerConvergence.notConfirmed,
        localReady: true,
        localGeneration: 42,
      );
      check(
        'confirmed + local UNAVAILABLE',
        HealthReadinessConvergenceOutcome.unavailable,
        status: HealthReadinessServerConvergence.confirmed,
        localReady: false,
        localGeneration: 42,
      );
      check(
        'unavailable + local UNAVAILABLE',
        HealthReadinessConvergenceOutcome.unavailable,
        status: HealthReadinessServerConvergence.unavailable,
        localReady: false,
        localGeneration: 41,
      );
      check(
        'unavailable + local READY stale (< G)',
        HealthReadinessConvergenceOutcome.unavailable,
        status: HealthReadinessServerConvergence.unavailable,
        localReady: true,
        localGeneration: 41,
      );
      check(
        'confirmed + local READY stale (< G)',
        HealthReadinessConvergenceOutcome.notConfirmed,
        status: HealthReadinessServerConvergence.confirmed,
        localReady: true,
        localGeneration: 41,
      );
      check(
        'confirmed + local READY sem marcador',
        HealthReadinessConvergenceOutcome.notConfirmed,
        status: HealthReadinessServerConvergence.confirmed,
        localReady: true,
        localGeneration: null,
      );
      check(
        'unavailable + local UNAVAILABLE sem marcador',
        HealthReadinessConvergenceOutcome.unavailable,
        status: HealthReadinessServerConvergence.unavailable,
        localReady: false,
        localGeneration: null,
      );

      expect(cases.length, 10);
    });
  });

  group('vocabulário do servidor', () {
    test('apenas os três literais congelados são aceitos', () {
      expect(
        HealthReadinessServerConvergence.fromWire('confirmed'),
        HealthReadinessServerConvergence.confirmed,
      );
      expect(
        HealthReadinessServerConvergence.fromWire('not_confirmed'),
        HealthReadinessServerConvergence.notConfirmed,
      );
      expect(
        HealthReadinessServerConvergence.fromWire('unavailable'),
        HealthReadinessServerConvergence.unavailable,
      );
    });

    test('spellings rejeitados e estados de cliente não são aceitos', () {
      final rejected = [
        'failed',
        'success',
        'ready',
        'pending',
        'converged',
        'convergenceFailed',
        'notConfirmed',
        'CONFIRMED',
        '',
        null,
        42,
      ];
      for (final wire in rejected) {
        expect(
          HealthReadinessServerConvergence.fromWire(wire),
          isNull,
          reason: 'não deveria aceitar: $wire',
        );
      }
    });
  });

  test('resultado preserva a resposta do servidor mesmo quando discorda', () {
    final result = decideHealthReadinessConvergence(
      serverReport: server(
        HealthReadinessServerConvergence.unavailable,
        observed: 41,
      ),
      observedMarker: const HealthReadinessCausalMarker(
        isReady: true,
        generation: 43,
      ),
    );
    expect(result.outcome, HealthReadinessConvergenceOutcome.converged);
    // Diagnóstico: a barreira do servidor disse unavailable, a prova local não.
    expect(
      result.serverReport!.status,
      HealthReadinessServerConvergence.unavailable,
    );
    expect(result.serverReport!.requiredGeneration, 42);
    expect(result.serverReport!.observedGeneration, 41);
    expect(result.observedMarker!.generation, 43);
  });
}
