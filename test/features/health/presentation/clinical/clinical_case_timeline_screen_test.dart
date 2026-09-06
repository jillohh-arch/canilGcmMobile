import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/domain/clinical_event_gateway.dart';
import 'package:canil_gcm/features/health/domain/clinical_event_read_model.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/presentation/clinical/clinical_case_timeline_screen.dart';

class _FakeClinicalEventGateway implements ClinicalEventGateway {
  final _eventsController =
      StreamController<List<ClinicalEventReadModel>>.broadcast();
  List<ClinicalAmendmentReadModel> mockAmendments = [];

  void emitEvents(List<ClinicalEventReadModel> events) {
    _eventsController.add(events);
  }

  void emitError(Object error) {
    _eventsController.addError(error);
  }

  @override
  Stream<List<ClinicalEventReadModel>> watchCaseEvents({
    required String dogId,
    required String caseId,
  }) => _eventsController.stream;

  @override
  Future<List<ClinicalEventReadModel>> readCaseEvents({
    required String dogId,
    required String caseId,
  }) async => [];

  @override
  Stream<List<ClinicalAmendmentReadModel>> watchEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  }) => Stream.value(mockAmendments);

  @override
  Future<List<ClinicalAmendmentReadModel>> readEventAmendments({
    required String dogId,
    required String caseId,
    required String eventId,
  }) async => mockAmendments;

  @override
  Future<ClinicalEventReadModel?> readEvent({
    required String dogId,
    required String caseId,
    required String eventId,
  }) async => null;

  void dispose() {
    _eventsController.close();
  }
}

void main() {
  late _FakeClinicalEventGateway fakeGateway;

  setUp(() {
    fakeGateway = _FakeClinicalEventGateway();
  });

  tearDown(() {
    fakeGateway.dispose();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      home: ClinicalCaseTimelineScreen(
        dogId: 'dog-01',
        caseId: 'case-99',
        caseTitle: 'Caso Fratura',
        gateway: fakeGateway,
      ),
    );
  }

  group('ClinicalCaseTimelineScreen', () {
    testWidgets(
      '1. Título canônico respeita CLINICAL-DEBT-01 (Eventos Clínicos, NÃO histórico completo)',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());

        expect(find.text('Eventos Clínicos'), findsOneWidget);
        expect(find.textContaining('Histórico completo do caso'), findsNothing);
        expect(find.textContaining('Caso Fratura'), findsOneWidget);
      },
    );

    testWidgets('2. Estado de carregamento exibe indicador de progresso', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Carregando eventos clínicos...'), findsOneWidget);
    });

    testWidgets('3. Estado vazio exibe mensagem acolhedora sem erro', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      fakeGateway.emitEvents([]);
      await tester.pumpAndSettle();

      expect(find.text('Nenhum evento clínico registrado'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      '4. Estado de erro exibe mensagem de erro e botão tentar novamente',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        fakeGateway.emitError(
          const ClinicalEventReadException(
            'Permissão negada para leitura do prontuário',
            code: 'permission-denied',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Falha ao carregar linha do tempo'), findsOneWidget);
        expect(
          find.text('Permissão negada para leitura do prontuário'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Sucesso: renderiza cards de eventos draft, final e cancelado com chips corretos',
      (tester) async {
        final now = DateTime.utc(2026, 9, 6, 12, 0);

        final eventDraft = ClinicalEventReadModel(
          id: 'evt-draft',
          caseId: 'case-99',
          dogId: 'dog-01',
          type: ClinicalEventTypeWire.parse('consultation'),
          status: ClinicalEventStatusWire.parse('draft'),
          occurredAt: now,
          recordedBy: const ClinicalActorReadModel(
            uid: 'u1',
            name: 'Dr. Lucas',
            internalRole: 'veterinario',
          ),
          content: const {'reason': 'Consulta preventiva'},
        );

        final eventFinal = ClinicalEventReadModel(
          id: 'evt-final',
          caseId: 'case-99',
          dogId: 'dog-01',
          type: ClinicalEventTypeWire.parse('vaccination'),
          status: ClinicalEventStatusWire.parse('final'),
          occurredAt: now.subtract(const Duration(days: 1)),
          recordedBy: const ClinicalActorReadModel(
            uid: 'u2',
            name: 'Dra. Maria',
            internalRole: 'veterinario',
          ),
          content: const {'title': 'Vacinação V10'},
        );

        final eventCancelled = ClinicalEventReadModel(
          id: 'evt-cancelled',
          caseId: 'case-99',
          dogId: 'dog-01',
          type: ClinicalEventTypeWire.parse('incident'),
          status: ClinicalEventStatusWire.parse('cancelled'),
          occurredAt: now.subtract(const Duration(days: 2)),
          cancelReason: 'Registro em caso errado',
          recordedBy: const ClinicalActorReadModel(
            uid: 'u3',
            name: 'Operador Silva',
            internalRole: 'operador',
          ),
          content: const {'diagnosis': 'Acidente cancelado'},
        );

        await tester.pumpWidget(buildTestWidget());
        fakeGateway.emitEvents([eventDraft, eventFinal, eventCancelled]);
        await tester.pumpAndSettle();

        // Verifica status chips
        expect(find.text('RASCUNHO'), findsOneWidget);
        expect(find.text('FINAL'), findsOneWidget);
        expect(find.text('CANCELADO'), findsOneWidget);

        // Verifica tipos
        expect(find.text('Consulta Veterinária'), findsOneWidget);
        expect(find.text('Vacinação'), findsOneWidget);
        expect(find.text('Incidente Clínico'), findsOneWidget);

        // Verifica motivo de cancelamento
        expect(find.textContaining('Registro em caso errado'), findsOneWidget);
      },
    );

    testWidgets('6. Emendas: exibe indicador e expande histórico ao tocar', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 9, 6, 12, 0);

      final eventWithAmendments = ClinicalEventReadModel(
        id: 'evt-with-amends',
        caseId: 'case-99',
        dogId: 'dog-01',
        type: ClinicalEventTypeWire.parse('consultation'),
        status: ClinicalEventStatusWire.parse('final'),
        occurredAt: now,
        hasAmendments: true,
        amendmentCount: 1,
        content: const {'diagnosis': 'Otite bilateral'},
      );

      fakeGateway.mockAmendments = [
        ClinicalAmendmentReadModel(
          id: 'ca-01',
          eventId: 'evt-with-amends',
          caseId: 'case-99',
          dogId: 'dog-01',
          type: ClinicalAmendmentType.parse('correction'),
          reason: 'Ajuste de medicamento para otite',
          content: const {},
          recordedAt: now.add(const Duration(hours: 1)),
          ordinal: 1,
          recordedBy: const ClinicalActorReadModel(
            uid: 'u1',
            name: 'Dr. Alberto',
            internalRole: 'veterinario',
          ),
        ),
      ];

      await tester.pumpWidget(buildTestWidget());
      fakeGateway.emitEvents([eventWithAmendments]);
      await tester.pumpAndSettle();

      // Indicador de emenda
      expect(find.text('Emenda registrada'), findsOneWidget);

      // Toca para expandir
      await tester.tap(find.text('Emenda registrada'));
      await tester.pumpAndSettle();

      // Detalhe da emenda exibido
      expect(find.text('#1 Correção'), findsOneWidget);
      expect(find.text('Ajuste de medicamento para otite'), findsOneWidget);
      expect(find.textContaining('Dr. Alberto'), findsOneWidget);
    });

    testWidgets(
      '7. Degradação de qualidade: exibe alerta discreto quando item possui inconformidades',
      (tester) async {
        final degradedEvent = ClinicalEventReadModel(
          id: 'evt-deg',
          caseId: 'case-99',
          dogId: 'dog-01',
          type: ClinicalEventTypeWire.parse('desconhecido_futuro'),
          status: ClinicalEventStatusWire.parse('final'),
          occurredAt: null, // ausente
          dataQualityIssues: const [
            'missing_occurred_at',
            'unknown_event_type:desconhecido_futuro',
          ],
          content: const {'note': 'Dado incompleto'},
        );

        await tester.pumpWidget(buildTestWidget());
        fakeGateway.emitEvents([degradedEvent]);
        await tester.pumpAndSettle();

        expect(find.text('Data não informada'), findsOneWidget);
        expect(
          find.textContaining('Qualidade: missing_occurred_at'),
          findsOneWidget,
        );
      },
    );
  });
}
