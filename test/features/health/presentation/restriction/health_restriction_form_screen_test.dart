import 'dart:async';

import 'package:canil_gcm/features/health/domain/health_document_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_evidence_file.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_flow_errors.dart';
import 'package:canil_gcm/features/health/domain/health_restriction_issue_gateway.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_form_screen.dart';
import 'package:canil_gcm/features/health/presentation/restriction/health_restriction_issue_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'convergence_test_gateway.dart';

/// Fakes das três autoridades. O controller real é usado — é ele que carrega a
/// máquina de estados que queremos exercitar pela UI.
final class _FakeDocumentGateway implements HealthDocumentGateway {
  HealthRestrictionFlowFailure? prepareFailure;
  HealthRestrictionFlowFailure? finalizeFailure;
  int prepareCount = 0;
  int finalizeCount = 0;

  /// Bloqueia a conclusão até `release()`, para observar o estado submitting.
  Completer<void>? gate;

  @override
  Future<PrepareHealthDocumentResult> prepareUpload(
    PrepareHealthDocumentCommand command,
  ) async {
    prepareCount += 1;
    if (gate != null) await gate!.future;
    final f = prepareFailure;
    if (f != null) return PrepareHealthDocumentError(f);
    return PrepareHealthDocumentSuccess(
      PreparedHealthDocumentUpload(
        dogId: command.dogId,
        documentId: 'hd_abc',
        uploadPath: 'health_document_uploads/${command.dogId}/hd_abc',
        maxBytes: 20 * 1024 * 1024,
      ),
    );
  }

  @override
  Future<FinalizeHealthDocumentResult> finalizeUpload(
    FinalizeHealthDocumentCommand command,
  ) async {
    finalizeCount += 1;
    final f = finalizeFailure;
    if (f != null) return FinalizeHealthDocumentError(f);
    return FinalizeHealthDocumentSuccess(
      FinalizedHealthDocument(
        dogId: command.dogId,
        documentId: 'hd_abc',
        reference: const HealthDocumentRef(healthDocumentId: 'hd_abc'),
        wasNoOp: false,
      ),
    );
  }
}

final class _FakeUploader implements HealthEvidenceUploader {
  int count = 0;
  HealthRestrictionFlowFailure? failure;

  @override
  Future<void> upload({
    required SelectedHealthEvidenceFile file,
    required String uploadPath,
  }) async {
    count += 1;
    final f = failure;
    if (f != null) throw f;
  }
}

final class _FakeIssueGateway implements HealthRestrictionIssueGateway {
  int count = 0;
  HealthRestrictionFlowFailure? failure;
  final List<IssueOperationalRestrictionCommand> commands =
      <IssueOperationalRestrictionCommand>[];

  @override
  Future<IssueOperationalRestrictionResult> issue(
    IssueOperationalRestrictionCommand command,
  ) async {
    count += 1;
    commands.add(command);
    final f = failure;
    if (f != null) return IssueOperationalRestrictionError(f);
    return IssueOperationalRestrictionSuccess(
      IssuedOperationalRestriction(
        dogId: command.dogId,
        restrictionId: 'or_xyz',
        wasNoOp: false,
      ),
    );
  }
}

void main() {
  const validFile = SelectedHealthEvidenceFile(
    name: 'laudo.pdf',
    path: '/tmp/laudo.pdf',
    sizeBytes: 4096,
    mimeType: 'application/pdf',
  );

  late _FakeDocumentGateway doc;
  late _FakeUploader uploader;
  late _FakeIssueGateway issue;
  late HealthRestrictionIssueController controller;
  late List<String> layoutErrors;

  setUp(() {
    doc = _FakeDocumentGateway();
    uploader = _FakeUploader();
    issue = _FakeIssueGateway();
    var seq = 0;
    controller = HealthRestrictionIssueController(
      documentGateway: doc,
      uploader: uploader,
      restrictionGateway: issue,
      convergenceGateway: convergenceTestGateway(),
      operationIdFactory: () => 'op-${++seq}',
    );
    layoutErrors = <String>[];
  });

  /// Monta a tela em largura de celular. `popResult` captura o pop.
  Future<List<bool?>> pump(
    WidgetTester tester, {
    HealthEvidenceFileResult? pickerResult = const HealthEvidenceFileAccepted(
      validFile,
    ),
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previousOnError = FlutterError.onError;
    FlutterError.onError = (d) => layoutErrors.add(d.exceptionAsString());

    final popped = <bool?>[];
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navKey, home: const SizedBox.shrink()),
    );
    // Push imperativo: o Future do push é a única fonte confiável do
    // resultado devolvido por `Navigator.pop(context, value)`.
    navKey.currentState!
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => HealthRestrictionFormScreen(
              dogId: 'dog-1',
              dogName: 'Bono',
              controller: controller,
              evidencePicker: () async => pickerResult,
            ),
          ),
        )
        .then(popped.add);
    await tester.pumpAndSettle();
    // Restaurar ANTES de qualquer expect(): o binding falha se `expect` roda
    // com `FlutterError.onError` ainda sobrescrito.
    FlutterError.onError = previousOnError;
    expect(
      layoutErrors,
      isEmpty,
      reason: 'composição inicial não deve gerar erro de layout',
    );
    return popped;
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Preenche tudo o que é obrigatório, deixando a tela válida.
  Future<void> fillValid(
    WidgetTester tester, {
    String level = 'absolute',
    List<String> activities = const <String>[],
    bool attachFile = true,
  }) async {
    await tester.tap(find.byKey(Key('restriction_level_$level')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restriction_category_injury')));
    await tester.pumpAndSettle();

    await scrollTo(tester, find.byKey(const Key('restriction_description')));
    await tester.enterText(
      find.byKey(const Key('restriction_description')),
      'Lesão em membro anterior',
    );
    await tester.pumpAndSettle();

    for (final activity in activities) {
      await scrollTo(
        tester,
        find.byKey(const Key('restriction_activity_input')),
      );
      await tester.enterText(
        find.byKey(const Key('restriction_activity_input')),
        activity,
      );
      await tester.tap(find.byKey(const Key('restriction_activity_add')));
      await tester.pumpAndSettle();
    }

    await scrollTo(
      tester,
      find.byKey(const Key('restriction_professional_name')),
    );
    await tester.enterText(
      find.byKey(const Key('restriction_professional_name')),
      'Dra. Ana Souza',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('restriction_registration_CRMV')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_professional_number')),
      'SP-12345',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('restriction_professional_clinic')),
      'Clínica Central',
    );
    await tester.pumpAndSettle();

    if (!attachFile) return;

    await scrollTo(tester, find.byKey(const Key('restriction_pick_file')));
    await tester.tap(find.byKey(const Key('restriction_pick_file')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.byKey(const Key('restriction_nature_certificate')),
    );
    await tester.tap(find.byKey(const Key('restriction_nature_certificate')));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('REGISTRAR RESTRIÇÃO'));
    await tester.pumpAndSettle();
  }

  Finder errorText(String fragment) => find.textContaining(fragment);

  group('1. estado inicial', () {
    testWidgets('sem loading, sem atividades, sem tipo profissional', (
      tester,
    ) async {
      await pump(tester);

      // CTA no estado de repouso.
      expect(find.text('REGISTRAR RESTRIÇÃO'), findsOneWidget);
      expect(find.text('REGISTRANDO...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Título completo dentro da tela, apesar do tile curto.
      expect(find.text('Restrição Operacional'), findsOneWidget);

      // Atividades ocultas: nenhum nível escolhido ainda.
      expect(
        find.byKey(const Key('restriction_activity_input')),
        findsNothing,
      );

      // Nenhum tipo de registro pré-selecionado — não inventamos conselho.
      await scrollTo(
        tester,
        find.byKey(const Key('restriction_registration_CRMV')),
      );
      for (final type in ['CRMV', 'CRMV-Z', 'CFMV', 'CRN', 'CRF', 'other']) {
        final chip = tester.widget<ChoiceChip>(
          find.byKey(Key('restriction_registration_$type')),
        );
        expect(chip.selected, isFalse, reason: type);
      }

      // Nenhum arquivo anexado.
      expect(
        find.byKey(const Key('restriction_selected_file')),
        findsNothing,
      );
      expect(find.byKey(const Key('restriction_pick_file')), findsOneWidget);
    });
  });

  group('2/3/5. atividades condicionais ao nível', () {
    testWidgets('absolute oculta atividades', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('restriction_level_absolute')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restriction_activity_input')),
        findsNothing,
      );
    });

    testWidgets('partial revela atividades', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('restriction_level_partial')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restriction_activity_input')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('restriction_activity_add')), findsOneWidget);
    });

    testWidgets('attention oculta atividades', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('restriction_level_attention')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restriction_activity_input')),
        findsNothing,
      );
    });

    testWidgets('trocar partial → absolute oculta e não envia atividades', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester, level: 'partial', activities: ['busca']);

      // Volta para absolute: seção desaparece.
      await scrollTo(tester, find.byKey(const Key('restriction_level_absolute')));
      await tester.tap(find.byKey(const Key('restriction_level_absolute')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('restriction_activity_input')),
        findsNothing,
      );

      await submit(tester);
      expect(issue.count, 1);
      expect(
        issue.commands.single.activitiesRestricted,
        isEmpty,
        reason: 'atividades não são materiais fora de partial',
      );
    });
  });

  group('4/6/7/8. validação bloqueia submit', () {
    testWidgets('partial sem atividade bloqueia e não chama backend', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester, level: 'partial');
      await submit(tester);

      expect(errorText('ao menos uma atividade'), findsOneWidget);
      expect(doc.prepareCount, 0, reason: 'nada sai para a rede');
      expect(uploader.count, 0);
      expect(issue.count, 0);
    });

    testWidgets('nível ausente bloqueia', (tester) async {
      await pump(tester);
      await submit(tester);

      expect(errorText('Selecione o nível'), findsOneWidget);
      expect(doc.prepareCount, 0);
    });

    testWidgets('profissional incompleto bloqueia', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('restriction_level_absolute')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restriction_category_injury')));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('restriction_description')));
      await tester.enterText(
        find.byKey(const Key('restriction_description')),
        'Lesão em membro anterior',
      );
      await tester.pumpAndSettle();

      // Nome preenchido, tipo de registro deliberadamente NÃO escolhido.
      await scrollTo(
        tester,
        find.byKey(const Key('restriction_professional_name')),
      );
      await tester.enterText(
        find.byKey(const Key('restriction_professional_name')),
        'Dra. Ana Souza',
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, find.text('REGISTRAR RESTRIÇÃO'));
      await submit(tester);

      expect(errorText('tipo de registro'), findsOneWidget);
      expect(doc.prepareCount, 0);
    });

    testWidgets('arquivo ausente bloqueia', (tester) async {
      await pump(tester);
      // Tudo válido, exceto a evidência documental.
      await fillValid(tester, attachFile: false);
      await submit(tester);

      expect(errorText('Anexe o atestado'), findsOneWidget);
      expect(doc.prepareCount, 0, reason: 'nada sai para a rede');
      expect(uploader.count, 0);
      expect(issue.count, 0);
    });

    testWidgets('arquivo grande mostra mensagem amigável, sem jargão', (
      tester,
    ) async {
      await pump(
        tester,
        pickerResult: const HealthEvidenceFileRejected(
          HealthEvidenceFileRejection.tooLarge,
        ),
      );
      await scrollTo(tester, find.byKey(const Key('restriction_pick_file')));
      await tester.tap(find.byKey(const Key('restriction_pick_file')));
      await tester.pumpAndSettle();

      final message = tester
          .widget<Text>(find.byKey(const Key('restriction_file_rejection')))
          .data!;
      expect(message, contains('20 MB'));
      // Sem vocabulário do protocolo.
      for (final jargon in [
        'generation',
        'seal',
        'receipt',
        'fingerprint',
        'staging',
      ]) {
        expect(message.toLowerCase(), isNot(contains(jargon)), reason: jargon);
      }
      expect(find.byKey(const Key('restriction_selected_file')), findsNothing);
    });

    testWidgets('formato não suportado mostra formatos aceitos', (
      tester,
    ) async {
      await pump(
        tester,
        pickerResult: const HealthEvidenceFileRejected(
          HealthEvidenceFileRejection.unsupportedExtension,
        ),
      );
      await scrollTo(tester, find.byKey(const Key('restriction_pick_file')));
      await tester.tap(find.byKey(const Key('restriction_pick_file')));
      await tester.pumpAndSettle();

      final message = tester
          .widget<Text>(find.byKey(const Key('restriction_file_rejection')))
          .data!;
      expect(message, contains('PDF'));
    });

    testWidgets('cancelar o picker não é erro', (tester) async {
      await pump(tester, pickerResult: null);
      await scrollTo(tester, find.byKey(const Key('restriction_pick_file')));
      await tester.tap(find.byKey(const Key('restriction_pick_file')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('restriction_file_rejection')),
        findsNothing,
      );
      expect(find.byKey(const Key('restriction_selected_file')), findsNothing);
    });
  });

  group('9. submitting protege a intenção em voo', () {
    testWidgets('CTA não dispara segunda submissão e campos ficam travados', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester);

      // Segura o PREPARE para observar o estado submitting.
      doc.gate = Completer<void>();
      await tester.tap(find.text('REGISTRAR RESTRIÇÃO'));
      await tester.pump();

      expect(find.text('REGISTRANDO...'), findsOneWidget);

      // Double tap durante o envio não gera segunda operação.
      await tester.tap(find.text('REGISTRANDO...'), warnIfMissed: false);
      await tester.pump();
      expect(doc.prepareCount, 1, reason: 'CTA protegido contra double tap');

      // Campos materiais desabilitados: o estado visual não pode divergir da
      // intenção em execução.
      final description = tester.widget<TextFormField>(
        find.byKey(const Key('restriction_description')),
      );
      expect(description.enabled, isFalse);

      final levelChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('restriction_level_partial')),
      );
      expect(levelChip.onSelected, isNull, reason: 'nível travado');

      final categoryChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('restriction_category_chronic')),
      );
      expect(categoryChip.onSelected, isNull, reason: 'categoria travada');

      doc.gate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('10. falha preserva o formulário e permite retry', () {
    testWidgets('erro visível, dados preservados, retry sem refazer etapas', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester);

      issue.failure = const HealthRestrictionFlowOffline(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await submit(tester);

      // Erro visível em linguagem operacional.
      expect(errorText('Sem conexão'), findsOneWidget);

      // Formulário preservado: o texto continua lá.
      await scrollTo(tester, find.byKey(const Key('restriction_description')));
      expect(find.text('Lesão em membro anterior'), findsOneWidget);
      // Arquivo continua anexado.
      await scrollTo(
        tester,
        find.byKey(const Key('restriction_selected_file')),
      );
      expect(find.text('laudo.pdf'), findsOneWidget);

      // Retry: documento não é recriado, só o ISSUE repete.
      issue.failure = null;
      await scrollTo(tester, find.text('REGISTRAR RESTRIÇÃO'));
      await submit(tester);

      expect(doc.prepareCount, 1, reason: 'documento já é canônico');
      expect(uploader.count, 1, reason: 'sem re-upload');
      expect(doc.finalizeCount, 1);
      expect(issue.count, 2);
    });

    testWidgets('permission-denied não expõe capability técnica', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester);

      issue.failure = const HealthRestrictionFlowPermissionDenied(
        HealthRestrictionFlowStep.restrictionIssue,
      );
      await submit(tester);

      expect(errorText('Você não possui autorização'), findsOneWidget);
      expect(find.textContaining('issue_restriction'), findsNothing);
      expect(find.textContaining('health.'), findsNothing);
    });

    testWidgets('falha de upload não avança para as etapas seguintes', (
      tester,
    ) async {
      await pump(tester);
      await fillValid(tester);

      uploader.failure = const HealthRestrictionFlowIntegrity(
        HealthRestrictionFlowStep.documentUpload,
      );
      await submit(tester);

      expect(doc.finalizeCount, 0);
      expect(issue.count, 0);
      expect(errorText('Não foi possível concluir'), findsOneWidget);
    });
  });

  group('11. sucesso', () {
    testWidgets('pop(true) e payload correto', (tester) async {
      final popped = await pump(tester);
      await fillValid(tester);
      await submit(tester);

      expect(popped, [true], reason: 'pop(true) propaga para o hub');
      expect(issue.count, 1);

      final command = issue.commands.single;
      expect(command.dogId, 'dog-1');
      expect(command.description, 'Lesão em membro anterior');
      expect(command.professional.name, 'Dra. Ana Souza');
      expect(command.professional.registrationNumber, 'SP-12345');
      expect(command.professional.clinic, 'Clínica Central');
      expect(command.sourceDocument.healthDocumentId, 'hd_abc');
    });

    testWidgets('título do documento tem prefill editável', (tester) async {
      await pump(tester);
      await fillValid(tester);

      await scrollTo(
        tester,
        find.byKey(const Key('restriction_document_title')),
      );
      // Prefill derivado da natureza escolhida.
      expect(find.text('Atestado veterinário — Bono'), findsOneWidget);

      // Editável.
      await tester.enterText(
        find.byKey(const Key('restriction_document_title')),
        'Título do operador',
      );
      await tester.pumpAndSettle();
      expect(find.text('Título do operador'), findsOneWidget);
    });
  });

  group('12. saída com alterações não salvas', () {
    testWidgets('proteção de saída ativa após editar', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('restriction_level_absolute')));
      await tester.pumpAndSettle();

      // O scaffold instala o guard quando há controller + dirty.
      final scope = tester.widgetList(
        find.byWidgetPredicate((w) => w is PopScope),
      ).first as dynamic;
      expect(
        scope.canPop,
        isFalse,
        reason: 'formulário sujo não sai sem confirmar',
      );
    });

    testWidgets('formulário intocado sai livremente', (tester) async {
      await pump(tester);

      final scope = tester.widgetList(
        find.byWidgetPredicate((w) => w is PopScope),
      ).first as dynamic;
      expect(scope.canPop, isTrue);
    });
  });

}
