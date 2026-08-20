import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_controller.dart';

/// B4-C.2 — controller do detalhe canônico.
///
/// Prova a fronteira de dados: exatamente UM `getById` por carga, identidade
/// exata, e falha tipada preservada sem fallback para projeção.
void main() {
  const dogId = 'dog-1';
  const restrictionId = 'or_abc123';

  RecordedBy actor([String name = 'Cb. Silva']) => RecordedBy(
    uid: 'uid-1',
    name: name,
    internalRole: 'condutor',
  );

  ProfessionalIdentity professional() => ProfessionalIdentity(
    name: 'Dra. Ana Souza',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-12345',
    clinic: 'Clínica Central',
  );

  /// O aggregate impõe exclusividade terminal: `ended` exige os cinco campos de
  /// encerramento, `cancelled` exige os três de cancelamento, e metadata dos
  /// dois lados é recusada. A fixture respeita isso em vez de contorná-lo.
  OperationalRestriction fixture({
    RestrictionStatus status = RestrictionStatus.active,
    RestrictionLevel level = RestrictionLevel.absolute,
    List<String> activities = const <String>[],
  }) {
    final ended = status == RestrictionStatus.ended;
    final cancelled = status == RestrictionStatus.cancelled;

    return OperationalRestriction(
      id: restrictionId,
      dogId: dogId,
      level: level,
      category: RestrictionCategory.injury,
      description: 'Lesão em membro anterior',
      issuedAt: DateTime.utc(2026, 8, 1, 10),
      recordedBy: actor(),
      professional: professional(),
      sourceDocument: const HealthDocumentRef(healthDocumentId: 'hd_abc'),
      status: status,
      schemaVersion: 1,
      activitiesRestricted: activities,
      actualEnd: ended ? DateTime.utc(2026, 8, 10, 9) : null,
      endedBy: ended ? actor('Sgt. Costa') : null,
      endReason: ended ? 'Alta clínica confirmada' : null,
      endProfessional: ended ? professional() : null,
      endSourceDocument: ended
          ? const HealthDocumentRef(healthDocumentId: 'hd_end')
          : null,
      cancelledAt: cancelled ? DateTime.utc(2026, 8, 5, 8) : null,
      cancelledBy: cancelled ? actor('Sgt. Costa') : null,
      cancelReason: cancelled ? 'Registro criado por engano' : null,
    );
  }

  test('carga bem-sucedida expõe o aggregate canônico', () async {
    var calls = 0;
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: _FakeGateway((d, r) {
        calls += 1;
        expect(d, dogId);
        expect(r, restrictionId);
        return HealthRestrictionReadSuccess(fixture());
      }),
    );

    await controller.load();

    expect(calls, 1, reason: 'exatamente uma leitura canônica');
    expect(controller.status, HealthRestrictionDetailStatus.loaded);
    expect(controller.restriction!.id, restrictionId);
    expect(controller.failure, isNull);
  });

  test('identidade exata é repassada ao gateway', () async {
    final seen = <({String dogId, String restrictionId})>[];
    final controller = HealthRestrictionDetailController(
      dogId: 'dog-9',
      restrictionId: 'or_xyz',
      gateway: _FakeGateway((d, r) {
        seen.add((dogId: d, restrictionId: r));
        return HealthRestrictionReadSuccess(fixture());
      }),
    );

    await controller.load();

    expect(seen.single.dogId, 'dog-9');
    expect(seen.single.restrictionId, 'or_xyz');
  });

  group('falhas tipadas são preservadas', () {
    for (final code in HealthRestrictionReadErrorCode.values) {
      test('código ${code.name} não degrada em dado', () async {
        final controller = HealthRestrictionDetailController(
          dogId: dogId,
          restrictionId: restrictionId,
          gateway: _FakeGateway(
            (_, _) => HealthRestrictionReadError(
              HealthRestrictionReadFailure(
                code: code,
                message: 'falha ${code.name}',
              ),
            ),
          ),
        );

        await controller.load();

        expect(controller.status, HealthRestrictionDetailStatus.failed);
        expect(controller.failure!.code, code);
        // Nunca fabricar detalhe a partir da projeção.
        expect(controller.restriction, isNull);
      });
    }
  });

  test('exceção inesperada falha fechada, sem vazar raw error', () async {
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: _FakeGateway((_, _) => throw StateError('boom')),
    );

    await controller.load();

    expect(controller.status, HealthRestrictionDetailStatus.failed);
    expect(
      controller.failure!.code,
      HealthRestrictionReadErrorCode.unexpected,
    );
    expect(controller.failure!.message, isNot(contains('boom')));
    expect(controller.restriction, isNull);
  });

  test('retry repete a MESMA identidade', () async {
    final seen = <String>[];
    var fail = true;
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: _FakeGateway((d, r) {
        seen.add('$d/$r');
        if (fail) {
          return const HealthRestrictionReadError(
            HealthRestrictionReadFailure(
              code: HealthRestrictionReadErrorCode.unavailable,
              message: 'offline',
            ),
          );
        }
        return HealthRestrictionReadSuccess(fixture());
      }),
    );

    await controller.load();
    expect(controller.status, HealthRestrictionDetailStatus.failed);

    fail = false;
    await controller.load();

    expect(controller.status, HealthRestrictionDetailStatus.loaded);
    expect(seen, ['$dogId/$restrictionId', '$dogId/$restrictionId']);
  });

  test('carga concorrente não dispara segunda leitura', () async {
    var calls = 0;
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: _FakeGateway((_, _) {
        calls += 1;
        return HealthRestrictionReadSuccess(fixture());
      }),
    );

    await Future.wait([controller.load(), controller.load()]);

    expect(calls, 1, reason: 'guarda contra carga dupla');
  });

  test('terminal ended e cancelled são carregados como estão', () async {
    for (final status in [
      RestrictionStatus.ended,
      RestrictionStatus.cancelled,
    ]) {
      final controller = HealthRestrictionDetailController(
        dogId: dogId,
        restrictionId: restrictionId,
        gateway: _FakeGateway(
          (_, _) => HealthRestrictionReadSuccess(fixture(status: status)),
        ),
      );

      await controller.load();

      expect(controller.restriction!.status, status);
    }
  });
}

final class _FakeGateway implements HealthRestrictionReadGateway {
  _FakeGateway(this._handler);

  final HealthRestrictionReadResult Function(String dogId, String restrictionId)
  _handler;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async => _handler(dogId, restrictionId);
}
