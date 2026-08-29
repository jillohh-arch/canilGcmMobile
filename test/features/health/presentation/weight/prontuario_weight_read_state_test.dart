import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/dogs/data/weight_history_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/health/presentation/weight/prontuario_weight_read_state.dart';

/// WEIGHT-01E-C2B.1A — prova executada da resolução de peso do prontuário.
///
/// O defeito original não era um rótulo errado: era informação perdida.
/// `inconclusive` e erro de leitura colapsavam em "sem registro" e a tela
/// exibia `dogs.weight` como evidência clínica. Estes testes exercitam a
/// unidade que agora decide o estado, sem montar árvore de UI.
class _FakeWeightService extends WeightHistoryService {
  _FakeWeightService({this.record, this.error})
    : super(firestore: FakeFirebaseFirestore());

  final WeightRecord? record;
  final Object? error;

  @override
  Future<WeightRecord?> getLatest(String dogId) async {
    if (error != null) throw error!;
    return record;
  }
}

WeightRecord _record(double weightKg) => WeightRecord(
  id: 'w1',
  weightKg: weightKg,
  measuredAt: DateTime.utc(2026, 8, 6, 10),
  // Autoria ausente (shape legado reconhecido): nunca inventada.
  recordedBy: null,
  schemaVersion: 1,
);

void main() {
  Future<ProntuarioWeightReadState> resolveWith({
    WeightRecord? record,
    Object? error,
  }) => ProntuarioWeightResolver(
    _FakeWeightService(record: record, error: error),
  ).resolve('dog-1');

  group('estados canônicos', () {
    test('T1 WeightRecord → current com peso factual', () async {
      final state = await resolveWith(record: _record(33.3));

      expect(state.state, ProntuarioWeightState.current);
      expect(state.isCurrent, isTrue);
      expect(state.current!.weightKg, 33.3);
      expect(state.weightKg, 33.3);
    });

    test('T2 null → none, sem peso', () async {
      final state = await resolveWith();

      expect(state.state, ProntuarioWeightState.none);
      expect(state.isNone, isTrue);
      expect(state.current, isNull);
      expect(state.weightKg, isNull);
    });

    test('T3 malformed → inconclusive, não degrada para none', () async {
      final state = await resolveWith(
        error: const WeightHistoryReadException('malformed_weight_record'),
      );

      expect(state.state, ProntuarioWeightState.inconclusive);
      expect(state.isNone, isFalse);
      expect(state.isUnavailable, isFalse);
      expect(state.weightKg, isNull);
    });

    test('T4 unsupported → inconclusive, não degrada para none', () async {
      final state = await resolveWith(
        error: const WeightHistoryReadException('unsupported_weight_schema'),
      );

      expect(state.state, ProntuarioWeightState.inconclusive);
      expect(state.isNone, isFalse);
      expect(state.weightKg, isNull);
    });

    test('duplicate entityId → inconclusive', () async {
      final state = await resolveWith(
        error: const WeightHistoryReadException('duplicate_weight_entity_id'),
      );

      expect(state.state, ProntuarioWeightState.inconclusive);
      expect(state.weightKg, isNull);
    });

    test('T5 permission-denied → unavailable, não é ausência', () async {
      final state = await resolveWith(
        error: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
      );

      expect(state.state, ProntuarioWeightState.unavailable);
      expect(state.isNone, isFalse);
      expect(state.isInconclusive, isFalse);
      expect(state.weightKg, isNull);
    });

    test('rede indisponível → unavailable', () async {
      final state = await resolveWith(
        error: FirebaseException(
          plugin: 'cloud_firestore',
          code: 'unavailable',
          message: 'client is offline',
        ),
      );

      expect(state.state, ProntuarioWeightState.unavailable);
      expect(state.weightKg, isNull);
    });

    test('T6 erro genérico → unavailable', () async {
      final state = await resolveWith(error: StateError('boom'));

      expect(state.state, ProntuarioWeightState.unavailable);
      expect(state.isNone, isFalse);
      expect(state.weightKg, isNull);
    });
  });

  group('invariantes de segurança', () {
    test('nenhum estado sem evidência expõe peso', () async {
      final blocked = [
        await resolveWith(),
        await resolveWith(
          error: const WeightHistoryReadException('malformed_weight_record'),
        ),
        await resolveWith(
          error: const WeightHistoryReadException('unsupported_weight_schema'),
        ),
        await resolveWith(error: StateError('boom')),
        await resolveWith(
          error: FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
      ];

      for (final state in blocked) {
        expect(state.weightKg, isNull, reason: '${state.state} expôs peso');
        expect(state.current, isNull, reason: '${state.state} expôs registro');
        expect(state.isCurrent, isFalse);
      }
    });

    test('os quatro estados são mutuamente exclusivos', () async {
      final byState = {
        ProntuarioWeightState.current: await resolveWith(record: _record(33.3)),
        ProntuarioWeightState.none: await resolveWith(),
        ProntuarioWeightState.inconclusive: await resolveWith(
          error: const WeightHistoryReadException('malformed_weight_record'),
        ),
        ProntuarioWeightState.unavailable: await resolveWith(
          error: StateError('boom'),
        ),
      };

      byState.forEach((expected, state) {
        expect(state.state, expected);
        final flags = [
          state.isCurrent,
          state.isNone,
          state.isInconclusive,
          state.isUnavailable,
        ];
        expect(flags.where((f) => f).length, 1);
      });
    });
  });

  group('guarda estrutural: dog.weight fora da cadeia', () {
    test('o resolver não referencia projeção legada', () {
      // A unidade que decide o peso atual não pode nem mencionar a projeção:
      // é o que impede a classe de bug original de voltar.
      final file = File(
        'lib/features/health/presentation/weight/prontuario_weight_read_state.dart',
      );
      // Somente CÓDIGO: a documentação cita os nomes justamente para registrar
      // que eles não participam da decisão.
      final code = file
          .readAsLinesSync()
          .where((line) {
            final trimmed = line.trimLeft();
            return !trimmed.startsWith('//') && !trimmed.startsWith('///');
          })
          .join('\n');

      expect(code.contains('dog.weight'), isFalse);
      expect(code.contains('_last_weight_kg'), isFalse);
      expect(code.contains('_last_weight_at'), isFalse);
      // Não recebe Dog como entrada de decisão.
      expect(code.contains('Dog dog'), isFalse);
    });
  });
}
