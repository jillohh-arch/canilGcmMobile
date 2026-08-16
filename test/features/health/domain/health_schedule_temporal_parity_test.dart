// K9 Ops Mobile — HW-4A.2B
// Paridade cross-platform da derivação temporal da Agenda.
//
// Lê a MESMA fixture JSON consumida pelo Web
// (k9-ops Web: src/features/health/domain/__tests__/fixtures/
//  schedule-temporal-parity.json) e exige o mesmo estado temporal.
//
// A fixture é dado puro: não há acoplamento de runtime entre os repos.
//
// CONTRATO DE EXECUÇÃO (HW-4A.2E.1):
//   sem env  -> usa a fixture CANÔNICA versionada neste repositório.
//               O teste SEMPRE executa; nunca vira skip silencioso.
//   com env  -> usa a fixture explícita informada (prova cross-repo).
//               Alvo inexistente ou malformado FALHA de forma clara.
//
// A fixture local é mantida byte-idêntica à do Web; o gate de integração
// compara os SHA-256 dos dois lados.
//
// Execução:
//   flutter test test/features/health/domain/health_schedule_temporal_parity_test.dart
//   K9_PARITY_FIXTURE=[caminho] flutter test \
//     test/features/health/domain/health_schedule_temporal_parity_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:canil_gcm/features/health/domain/health_schedule_item.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_presentation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Config aprovada HW-4A.2B: 7d upcoming para TODOS os tipos; 24h
/// pós-vencimento para todos EXCETO dose, que não possui fallback genérico.
///
/// Usa a política canônica de produção — [healthSchedulePresentationPolicy] —
/// em vez de reconstruir os valores aqui. Assim a paridade cross-platform
/// testa o contrato real, não uma cópia que pode divergir.
///
/// HW-4A.2B tornou `toleranceAfterScheduled` nullable, então `dose` mantém sua
/// janela upcoming de 7 dias e ainda falha fechada
/// (`incomplete_schedule_temporal_config`) quando `due_until` está ausente.
/// A versão anterior omitia `dose` do mapa, o que também derrubava a janela
/// upcoming e produzia o código de erro errado.
HealthScheduleTemporalPolicy approvedPolicy() {
  return healthSchedulePresentationPolicy();
}

ScheduleType scheduleTypeFromWire(String wire) {
  return ScheduleType.values.firstWhere((t) => t.wireName == wire);
}

ScheduleLifecycleStatus lifecycleFromWire(String wire) {
  return ScheduleLifecycleStatus.values.firstWhere((s) => s.wireName == wire);
}

/// Fixture canônica versionada no repositório Mobile. Resolvida a partir da
/// raiz do pacote para funcionar independente do cwd do runner.
const _localFixtureRelativePath =
    'test/fixtures/health/schedule-temporal-parity.json';

/// Resolve a fixture a usar.
///
/// Sem `K9_PARITY_FIXTURE`, cai na fixture canônica local — o teste executa
/// sempre. Um override explícito que não existe é ERRO, não skip: o operador
/// pediu uma prova cross-repo específica e ela não pode falhar em silêncio.
String _resolveFixturePath() {
  final override = Platform.environment['K9_PARITY_FIXTURE'];
  if (override != null && override.trim().isNotEmpty) {
    if (!File(override).existsSync()) {
      throw StateError(
        'K9_PARITY_FIXTURE aponta para arquivo inexistente: $override',
      );
    }
    return override;
  }
  return _localFixtureRelativePath;
}

void main() {
  final fixturePath = _resolveFixturePath();

  final actor = RecordedBy(uid: 'u1', name: 'Condutor', internalRole: 'condutor');

  HealthScheduleItem buildItem(Map<String, dynamic> raw) {
    final scheduledFor = DateTime.parse(raw['scheduledFor'] as String);
    final dueUntilRaw = raw['dueUntil'] as String?;
    final lifecycle = lifecycleFromWire(raw['lifecycleStatus'] as String);
    return HealthScheduleItem(
      id: 'fixture',
      dogId: 'dog-fixture',
      scheduleType: scheduleTypeFromWire(raw['scheduleType'] as String),
      title: 'fixture',
      scheduledFor: scheduledFor,
      dueUntil: dueUntilRaw == null ? null : DateTime.parse(dueUntilRaw),
      timezone: raw['timezone'] as String,
      lifecycleStatus: lifecycle,
      sourceType: ScheduleSourceType.manual,
      createdAt: scheduledFor.subtract(const Duration(days: 30)),
      recordedBy: actor,
      schemaVersion: 1,
      completedAt: lifecycle == ScheduleLifecycleStatus.completed
          ? scheduledFor
          : null,
      completedBy: lifecycle == ScheduleLifecycleStatus.completed ? actor : null,
      cancelledAt: lifecycle == ScheduleLifecycleStatus.cancelled
          ? scheduledFor
          : null,
      cancelledBy: lifecycle == ScheduleLifecycleStatus.cancelled ? actor : null,
      cancelReason: lifecycle == ScheduleLifecycleStatus.cancelled
          ? 'fixture'
          : null,
    );
  }

  group('paridade temporal cross-platform (fixture compartilhada)', () {
    late Map<String, dynamic> fixture;

    setUpAll(() {
      // Fixture malformada FALHA aqui — não é degradada para skip.
      fixture =
          jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
    });

    test('fixture disponível', () {
      expect(File(fixturePath).existsSync(), isTrue);
      expect((fixture['cases'] as List).isNotEmpty, isTrue);
      expect((fixture['invalidCases'] as List).isNotEmpty, isTrue);
    });

    test('todos os casos resolvidos produzem o mesmo estado do Web', () {
      final policy = approvedPolicy();
      final divergences = <String>[];

      for (final raw in fixture['cases'] as List) {
        final testCase = raw as Map<String, dynamic>;
        final item = buildItem(testCase['item'] as Map<String, dynamic>);
        final now = DateTime.parse(testCase['now'] as String);
        final expected = testCase['expected'] as String;
        try {
          final actual = policy.evaluate(item, now: now).wireName;
          if (actual != expected) {
            divergences.add(
              '${testCase['name']}: esperado=$expected obtido=$actual',
            );
          }
        } on HealthDomainException catch (e) {
          divergences.add('${testCase['name']}: lançou ${e.code}');
        }
      }

      expect(divergences, isEmpty, reason: divergences.join('\n'));
    });

    test('casos inválidos falham fechado (sem estado adivinhado)', () {
      final policy = approvedPolicy();
      final divergences = <String>[];

      /// Razão do Web -> código de domínio Dart equivalente.
      /// Verificar apenas "lançou alguma coisa" deixaria o teste passar pelo
      /// motivo errado (ex.: timezone inválido mascarando dose sem due_until).
      const reasonToCode = <String, String>{
        'missing_dose_tolerance': 'incomplete_schedule_temporal_config',
        'due_until_before_scheduled_for': 'inconsistent_due_until',
        'invalid_timezone': 'invalid_schedule_timezone',
      };

      for (final raw in fixture['invalidCases'] as List) {
        final testCase = raw as Map<String, dynamic>;
        final now = DateTime.parse(testCase['now'] as String);
        final rawItem = testCase['item'] as Map<String, dynamic>;
        final expectedReason = testCase['expectedReason'] as String;
        final expectedCode = reasonToCode[expectedReason];
        if (expectedCode == null) {
          divergences.add(
            '${testCase['name']}: razão "$expectedReason" sem mapeamento '
            'Dart — fixture e domínio divergiram',
          );
          continue;
        }

        String? actualCode;
        try {
          // Timezone/due_until inválidos são rejeitados já na construção do
          // agregado canônico; tolerância ausente falha no resolver.
          final item = buildItem(rawItem);
          policy.evaluate(item, now: now);
        } on HealthDomainException catch (e) {
          actualCode = e.code;
        }

        if (actualCode == null) {
          divergences.add(
            '${testCase['name']}: NÃO falhou fechado '
            '(esperado $expectedReason)',
          );
        } else if (actualCode != expectedCode) {
          divergences.add(
            '${testCase['name']}: falhou por "$actualCode", '
            'esperado "$expectedCode" ($expectedReason)',
          );
        }
      }

      expect(divergences, isEmpty, reason: divergences.join('\n'));
    });
  });
}
