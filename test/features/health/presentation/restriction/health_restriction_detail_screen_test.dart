import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/health_restriction_read_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_controller.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_detail_screen.dart';

/// B4-C.2 — renderização do detalhe canônico, somente leitura.
///
/// Assere exclusivamente dados do aggregate canônico: nenhum campo é preenchido
/// com valor da projeção de Prontidão.
void main() {
  const dogId = 'dog-1';
  const restrictionId = 'or_abc123';

  RecordedBy actor([String name = 'Cb. Silva']) =>
      RecordedBy(uid: 'uid-1', name: name, internalRole: 'condutor');

  ProfessionalIdentity professional() => ProfessionalIdentity(
    name: 'Dra. Ana Souza',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'SP-12345',
    clinic: 'Clínica Central',
  );

  OperationalRestriction fixture({
    RestrictionStatus status = RestrictionStatus.active,
    RestrictionLevel level = RestrictionLevel.absolute,
    List<String> activities = const <String>[],
    DateTime? expectedEnd,
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
      expectedEnd: expectedEnd,
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

  Future<void> pump(
    WidgetTester tester,
    HealthRestrictionReadResult result,
  ) async {
    final controller = HealthRestrictionDetailController(
      dogId: dogId,
      restrictionId: restrictionId,
      gateway: _FakeGateway(result),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: HealthRestrictionDetailScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ACTIVE renderiza os campos canônicos', (tester) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(
        fixture(
          level: RestrictionLevel.absolute,
          expectedEnd: DateTime.utc(2026, 8, 30),
        ),
      ),
    );

    expect(find.text('ATIVA'), findsOneWidget);
    expect(find.text('Restrição absoluta'), findsOneWidget);
    expect(find.text('Lesão em membro anterior'), findsOneWidget);
    expect(find.text('Lesão / trauma'), findsOneWidget);
    expect(find.textContaining('01/08/2026'), findsOneWidget);
    // Profissional exibido como armazenado, sem inferência de conselho.
    expect(find.text('Dra. Ana Souza'), findsOneWidget);
    expect(find.text('CRMV SP-12345'), findsOneWidget);
    expect(find.text('Clínica Central'), findsOneWidget);
    expect(find.text('Cb. Silva'), findsOneWidget);
  });

  testWidgets('expectedEnd é PREVISÃO, nunca liberação automática', (
    tester,
  ) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(
        fixture(expectedEnd: DateTime.utc(2026, 8, 30)),
      ),
    );

    expect(find.textContaining('previsão'), findsWidgets);
    // Linguagem proibida: nada pode sugerir que a restrição se encerra sozinha.
    expect(find.textContaining('encerra em'), findsNothing);
    expect(find.textContaining('Liberação automática'), findsNothing);
    expect(find.textContaining('liberação automática'), findsNothing);
  });

  testWidgets('expectedEnd ausente não inventa data', (tester) async {
    await pump(tester, HealthRestrictionReadSuccess(fixture()));

    expect(find.text('Não informada'), findsOneWidget);
  });

  testWidgets('PARTIAL renderiza todas as atividades, sem fabricar', (
    tester,
  ) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(
        fixture(
          level: RestrictionLevel.partial,
          activities: const ['Saltos', 'Mordida', 'Farejamento em altura'],
        ),
      ),
    );

    expect(find.text('Saltos'), findsOneWidget);
    expect(find.text('Mordida'), findsOneWidget);
    expect(find.text('Farejamento em altura'), findsOneWidget);
    expect(find.text('Restrição parcial'), findsOneWidget);
    // Nunca inventar "todas as atividades".
    expect(find.textContaining('Todas as atividades'), findsNothing);
  });

  testWidgets('ABSOLUTE sem atividades não fabrica lista', (tester) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(fixture(level: RestrictionLevel.absolute)),
    );

    expect(find.textContaining('Todas as atividades'), findsNothing);
  });

  testWidgets('ENDED renderiza metadata terminal, sem ações', (tester) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(fixture(status: RestrictionStatus.ended)),
    );

    expect(find.text('ENCERRADA'), findsOneWidget);
    expect(find.text('Alta clínica confirmada'), findsOneWidget);
    expect(find.text('Sgt. Costa'), findsWidgets);
    expect(find.textContaining('10/08/2026'), findsOneWidget);
    // Zero lifecycle neste gate.
    expect(find.textContaining('Encerrar'), findsNothing);
    expect(find.textContaining('Cancelar restrição'), findsNothing);
  });

  testWidgets('CANCELLED é invalidação administrativa, não liberação clínica', (
    tester,
  ) async {
    await pump(
      tester,
      HealthRestrictionReadSuccess(
        fixture(status: RestrictionStatus.cancelled),
      ),
    );

    // Exato: `textContaining('CANCELADA')` também casaria com os rótulos
    // "CANCELADA EM"/"CANCELADA POR", que o campo emite em maiúsculas.
    expect(find.text('CANCELADA (REGISTRO INVALIDADO)'), findsOneWidget);
    expect(find.text('Registro criado por engano'), findsOneWidget);
    expect(find.textContaining('Não representa liberação'), findsOneWidget);
    // Nunca apresentar cancelamento como alta/liberação.
    expect(find.textContaining('Alta clínica'), findsNothing);
    expect(find.textContaining('liberado'), findsNothing);
  });

  testWidgets('nenhuma ação de lifecycle existe na tela', (tester) async {
    await pump(tester, HealthRestrictionReadSuccess(fixture()));

    expect(find.widgetWithText(ElevatedButton, 'ENCERRAR'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'CANCELAR'), findsNothing);
    expect(find.byType(BottomAppBar), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  group('falhas tipadas recebem apresentação distinta', () {
    testWidgets('notFound', (tester) async {
      await pump(
        tester,
        const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.notFound,
            message: 'Restrição não encontrada.',
          ),
        ),
      );

      expect(find.textContaining('não encontrada'), findsWidgets);
      // Sem fallback para dado da projeção.
      expect(find.text('Lesão em membro anterior'), findsNothing);
    });

    testWidgets('permissionDenied não vira "não encontrada"', (tester) async {
      await pump(
        tester,
        const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.permissionDenied,
            message: 'Você não tem acesso a este registro.',
          ),
        ),
      );

      expect(find.textContaining('Acesso não autorizado'), findsOneWidget);
      expect(find.text('Lesão em membro anterior'), findsNothing);
    });

    testWidgets('integrity falha fechada, sem detalhe parcial', (tester) async {
      await pump(
        tester,
        const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.integrity,
            message: 'Registro inconsistente.',
          ),
        ),
      );

      expect(find.textContaining('inconsistente'), findsWidgets);
      expect(find.text('Lesão em membro anterior'), findsNothing);
    });

    testWidgets('unavailable é distinguível de ausência', (tester) async {
      await pump(
        tester,
        const HealthRestrictionReadError(
          HealthRestrictionReadFailure(
            code: HealthRestrictionReadErrorCode.unavailable,
            message: 'Sem conexão no momento.',
          ),
        ),
      );

      expect(find.textContaining('Sem conexão'), findsWidgets);
    });
  });
}

final class _FakeGateway implements HealthRestrictionReadGateway {
  _FakeGateway(this._result);

  final HealthRestrictionReadResult _result;

  @override
  Future<HealthRestrictionReadResult> getById({
    required String dogId,
    required String restrictionId,
  }) async => _result;
}
