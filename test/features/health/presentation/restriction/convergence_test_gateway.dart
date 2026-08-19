import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_readiness_convergence_gateway.dart';

/// Barreira causal para testes que não exercitam convergência (B4-R.C3.R).
///
/// Desde o C3.R a dependência causal é OBRIGATÓRIA nos três controllers de
/// restrição: não existe caminho em que uma mutation commita sem que uma
/// tentativa de convergência aconteça. Testes focados no writer ainda precisam
/// fornecê-la, então usam este gateway real ligado a fakes.
///
/// Por padrão o summary fake está vazio, então a convergência falha de forma
/// benigna (`contractAbsent`/`notConfirmed`) sem interferir nas asserções de
/// mutation — e sem nunca reportar convergido falsamente.
HealthReadinessConvergenceGateway convergenceTestGateway({
  Map<String, Object?>? convergence,
  Map<String, Object?>? summary,
  String dogId = 'dog-1',
}) {
  final firestore = FakeFirebaseFirestore();
  if (summary != null) {
    firestore
        .collection('dogs')
        .doc(dogId)
        .collection('health_summary')
        .doc('current')
        .set(summary);
  }

  return HealthReadinessConvergenceGateway(
    invoke: (name, payload) async => {
      'ok': true,
      'result': {
        'dogId': payload['dogId'],
        'projectionStatus': 'ready',
        'readinessStatus': 'operational',
        'readinessLabel': 'Apto',
        'readinessReasonCode': 'none',
        'technicalBlockers': <String>[],
        'operation': 'ready',
        if (convergence != null) 'convergence': convergence,
      },
    },
    firestore: firestore,
  );
}
