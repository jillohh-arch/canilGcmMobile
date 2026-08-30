import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_readiness_convergence.dart';

/// B4-R.C3 — parser estrito do wire `result.convergence`.
///
/// Autoridade: `docs/health/adr/ADR-009-READINESS-PROJECTION-CAUSAL-CONSISTENCY.md` §11.
void main() {
  Map<String, dynamic> wire(Object? convergence, {bool ok = true}) => {
    'ok': ok,
    'result': {
      'dogId': 'dog-1',
      'projectionStatus': 'ready',
      'readinessStatus': 'operational',
      'readinessLabel': 'Apto',
      'readinessReasonCode': 'none',
      'technicalBlockers': <String>[],
      'operation': 'ready',
      if (convergence != _absent) 'convergence': convergence,
    },
  };

  group('contrato válido', () {
    test('lê os três campos congelados', () {
      final parse = parseHealthReadinessConvergenceResponse(
        wire({
          'status': 'confirmed',
          'requiredGeneration': 42,
          'observedGeneration': 43,
        }),
      );
      expect(parse.failure, isNull);
      expect(parse.report!.status, HealthReadinessServerConvergence.confirmed);
      expect(parse.report!.requiredGeneration, 42);
      expect(parse.report!.observedGeneration, 43);
    });

    test('observedGeneration null é válido', () {
      final parse = parseHealthReadinessConvergenceResponse(
        wire({
          'status': 'unavailable',
          'requiredGeneration': 7,
          'observedGeneration': null,
        }),
      );
      expect(parse.report!.observedGeneration, isNull);
      expect(
        parse.report!.status,
        HealthReadinessServerConvergence.unavailable,
      );
    });
  });

  group('rollout backend-first — contrato ausente', () {
    test('ok true sem convergence NUNCA é convergido', () {
      final parse = parseHealthReadinessConvergenceResponse(wire(_absent));
      expect(
        parse.failure,
        HealthReadinessConvergenceContractFailure.contractAbsent,
      );
      expect(parse.report, isNull);
    });

    test('convergence null é ausência, não malformação', () {
      final parse = parseHealthReadinessConvergenceResponse(wire(null));
      expect(
        parse.failure,
        HealthReadinessConvergenceContractFailure.contractAbsent,
      );
    });

    test('resposta sem result é ausência', () {
      final parse = parseHealthReadinessConvergenceResponse({'ok': true});
      expect(
        parse.failure,
        HealthReadinessConvergenceContractFailure.contractAbsent,
      );
    });
  });

  group('fail-closed — contrato malformado', () {
    test('status desconhecido', () {
      for (final status in ['failed', 'converged', 'pending', '', 42, null]) {
        final parse = parseHealthReadinessConvergenceResponse(
          wire({
            'status': status,
            'requiredGeneration': 42,
            'observedGeneration': null,
          }),
        );
        expect(
          parse.failure,
          HealthReadinessConvergenceContractFailure.contractMalformed,
          reason: 'status: $status',
        );
      }
    });

    test('requiredGeneration inválido', () {
      for (final required in [0, -1, 1.5, '42', null, true]) {
        final parse = parseHealthReadinessConvergenceResponse(
          wire({
            'status': 'confirmed',
            'requiredGeneration': required,
            'observedGeneration': null,
          }),
        );
        expect(
          parse.failure,
          HealthReadinessConvergenceContractFailure.contractMalformed,
          reason: 'required: $required',
        );
      }
    });

    test('observedGeneration presente mas inválido', () {
      for (final observed in [0, -1, 2.5, '43', true]) {
        final parse = parseHealthReadinessConvergenceResponse(
          wire({
            'status': 'confirmed',
            'requiredGeneration': 42,
            'observedGeneration': observed,
          }),
        );
        expect(
          parse.failure,
          HealthReadinessConvergenceContractFailure.contractMalformed,
          reason: 'observed: $observed',
        );
      }
    });

    test('chave observedGeneration ausente é malformação', () {
      final parse = parseHealthReadinessConvergenceResponse(
        wire({'status': 'confirmed', 'requiredGeneration': 42}),
      );
      expect(
        parse.failure,
        HealthReadinessConvergenceContractFailure.contractMalformed,
      );
    });

    test('convergence não é objeto', () {
      for (final bad in ['confirmed', 42, <int>[1]]) {
        final parse = parseHealthReadinessConvergenceResponse(wire(bad));
        expect(
          parse.failure,
          HealthReadinessConvergenceContractFailure.contractMalformed,
          reason: 'convergence: $bad',
        );
      }
    });
  });

  test('convergência não é inferida de ok', () {
    // ok=false com contrato válido ainda parseia: `ok` não é autoridade causal.
    final parse = parseHealthReadinessConvergenceResponse(
      wire({
        'status': 'confirmed',
        'requiredGeneration': 42,
        'observedGeneration': 42,
      }, ok: false),
    );
    expect(parse.report, isNotNull);

    // E ok=true sem contrato não convergeu.
    final absent = parseHealthReadinessConvergenceResponse(wire(_absent));
    expect(absent.report, isNull);
  });
}

/// Sentinela para "chave ausente", distinta de `null` no wire.
const Object _absent = Object();
