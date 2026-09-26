import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

// ignore: depend_on_referenced_packages
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

import 'package:canil_gcm/core/services/integrity_verification_service.dart';
import 'package:canil_gcm/features/dogs/domain/weight_record.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_detail_screen.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_status.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FF-OCC-09.C3.1.C1 — hermetic Firebase bootstrap, TEST-LOCAL ONLY.
//
// Why this exists: the occurrence scaffold also mounts `_AmendmentsSection`,
// whose state instantiates `AmendmentRepository()` in a field initializer,
// which touches `FirebaseFirestore.instance`. Without a registered Firebase app
// that throws [core/no-app] and the subtree aborts BEFORE the integrity card is
// built — so the card under test never renders.
//
// What this is NOT: it is not the integrity seam. Every verdict in these tests
// still comes from the injected `integrityVerifier` callback. This fake only
// satisfies construction-time plugin dependencies.
//
// `setupFirebaseForTest()` from test/helpers cannot be used: it mocks the legacy
// `MethodChannel('plugins.flutter.io/firebase_core')`, while firebase_core now
// speaks over Pigeon channels, so it fails with `channel-error`. The pattern
// below mirrors the precedent already established in
// test/features/occurrences/pdf/pdf_diagnostic_harness.dart, overriding the
// public `FirebasePlatform.instance` seam instead of the private codec.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeFirebasePlatform extends FirebasePlatform {
  _FakeFirebasePlatform() : _app = _FakeFirebaseAppPlatform();

  final FirebaseAppPlatform _app;

  @override
  List<FirebaseAppPlatform> get apps => <FirebaseAppPlatform>[_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async => _app;
}

class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'history-test-api-key',
          appId: 'history-test-app-id',
          messagingSenderId: 'history-test-sender-id',
          projectId: 'history-test-project',
        ),
      );
}

/// Pigeon channel `Query.get()` uses. Stubbed so `_AmendmentsSection` resolves
/// locally to an empty list instead of raising a channel error.
const _queryGetChannel =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet';

/// Pigeon channel `DocumentReference.get()` uses — stubbed for the same reason.
const _docGetChannel =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet';

/// Records every Firestore channel call, proving interception stayed local.
final List<String> _firestoreChannelCalls = <String>[];

/// The platform instance replaced by the fake, restored in tearDownAll so this
/// file cannot contaminate other suites through process-global state.
FirebasePlatform? _originalFirebasePlatform;

ByteData _encodeEmptyQuerySnapshot() {
  final snapshot = InternalQuerySnapshot(
    documents: <InternalDocumentSnapshot?>[],
    documentChanges: <InternalDocumentChange?>[],
    metadata: InternalSnapshotMetadata(
      hasPendingWrites: false,
      isFromCache: false,
    ),
  );
  return const PigeonCodec().encodeMessage(<Object?>[snapshot])!;
}

ByteData _encodeMissingDocumentSnapshot() {
  final snapshot = InternalDocumentSnapshot(
    path: 'occurrences/history-test',
    data: null,
    metadata: InternalSnapshotMetadata(
      hasPendingWrites: false,
      isFromCache: false,
    ),
  );
  return const PigeonCodec().encodeMessage(<Object?>[snapshot])!;
}

void _installHermeticFirebase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _originalFirebasePlatform = FirebasePlatform.instance;
  FirebasePlatform.instance = _FakeFirebasePlatform();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(_queryGetChannel, (ByteData? message) async {
    _firestoreChannelCalls.add('queryGet');
    return _encodeEmptyQuerySnapshot();
  });
  messenger.setMockMessageHandler(_docGetChannel, (ByteData? message) async {
    _firestoreChannelCalls.add('documentReferenceGet');
    return _encodeMissingDocumentSnapshot();
  });
}

void _uninstallHermeticFirebase() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(_queryGetChannel, null);
  messenger.setMockMessageHandler(_docGetChannel, null);
  final original = _originalFirebasePlatform;
  if (original != null) {
    FirebasePlatform.instance = original;
    _originalFirebasePlatform = null;
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _installHermeticFirebase();
  });

  tearDownAll(_uninstallHermeticFirebase);

  Widget buildSubject({Feeding? feeding, Map<String, dynamic>? details}) {
    final source = HistoryEntry(
      id: 'nutrition-1',
      type: HistoryEntryType.nutrition,
      title: 'Alimentação registrada',
      subtitle: '',
      time: DateTime(2026, 7, 30, 12),
      author: 'GCM Teste',
      tag: 'NUTRIÇÃO',
      icon: Icons.rice_bowl,
      color: Colors.amber,
      originalModel: feeding,
      details: details ?? const {},
    );
    final detail = RecordDetail(
      id: source.id,
      type: source.type,
      category: 'Nutrição',
      title: source.title,
      subtitle: source.subtitle,
      location: '',
      dateTime: source.time,
      author: source.author,
      dogName: 'K9 Teste',
      handlerName: 'GCM Teste',
      status: 'Finalizado',
      syncStatus: 'Sincronizado',
      duration: 'Não informado',
      team: '',
      notes: '',
      icon: source.icon,
      color: source.color,
      internalEvents: const [],
      auditEvents: const [],
      source: source,
    );

    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: HistoryNutricaoBody(detail: detail)),
      ),
    );
  }

  Feeding feeding({
    required int amount,
    required int prescription,
    required double divergence,
  }) {
    return Feeding(
      id: 'feeding-1',
      period: 'almoco',
      amountGrams: amount,
      prescriptionAtTime: prescription,
      divergencePercent: divergence,
      fedAt: DateTime(2026, 7, 30, 12),
      fedBy: 'uid-test',
    );
  }

  testWidgets(
    'exibe somente valores reais quando originalModel está presente',
    (tester) async {
      await tester.pumpWidget(
        buildSubject(
          feeding: feeding(amount: 420, prescription: 400, divergence: 5),
          details: const {'Ração': 'Ração Operacional Real'},
        ),
      );

      expect(find.text('420g'), findsOneWidget);
      expect(find.text('400g'), findsOneWidget);
      expect(find.text('Ração Operacional Real'), findsOneWidget);
      expect(find.text('EM CONFORMIDADE'), findsOneWidget);
      expect(find.text('350g'), findsNothing);
      expect(find.text('Ração Premium K9 Adulto'), findsNothing);
      expect(find.textContaining('Dra. Patrícia Lima'), findsNothing);
    },
  );

  testWidgets(
    'modelo ausente não fabrica quantidade alimento ou conformidade',
    (tester) async {
      await tester.pumpWidget(buildSubject());

      expect(find.text('350g'), findsNothing);
      expect(find.text('Ração Premium K9 Adulto'), findsNothing);
      expect(find.text('EM CONFORMIDADE'), findsNothing);
      expect(find.text('Não informado'), findsNWidgets(3));
      expect(find.text('NÃO INFORMADO'), findsOneWidget);
      expect(find.text('VÍNCULO CLÍNICO'), findsNothing);
      expect(find.text('FOTO DE VERIFICAÇÃO'), findsNothing);
    },
  );

  testWidgets('dado parcial preserva somente os valores realmente presentes', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        feeding: feeding(amount: 275, prescription: 0, divergence: 0),
        details: const {'Ração': 'Ração Parcial Real'},
      ),
    );

    expect(find.text('275g'), findsOneWidget);
    expect(find.text('Ração Parcial Real'), findsOneWidget);
    expect(find.text('Não informado'), findsOneWidget);
    expect(find.text('NÃO INFORMADO'), findsOneWidget);
    expect(find.text('0g'), findsNothing);
    expect(find.text('EM CONFORMIDADE'), findsNothing);
  });

  group('autoria ausente em pesagem legada (RecordDetail.fromEntry)', () {
    HistoryEntry weightEntry({required String author}) => HistoryEntry(
      id: 'weight_1',
      type: HistoryEntryType.health,
      title: 'Pesagem operacional registrada',
      subtitle: 'Peso atual: 32.0 kg',
      time: DateTime(2026, 8, 4, 10),
      author: author,
      authorId: author,
      tag: 'PESO',
      icon: Icons.monitor_weight_rounded,
      color: Colors.purple,
      details: const {'_healthKind': 'weight', 'Peso': '32.0 kg'},
    );

    test('peso sem autoria não fabrica Ragonha nem GCM Ragonha', () {
      final detail = RecordDetail.fromEntry(weightEntry(author: ''));

      expect(detail.author, isEmpty);
      expect(detail.handlerName, isEmpty);
      expect(detail.author, isNot(contains('Ragonha')));
      expect(detail.handlerName, isNot(contains('Ragonha')));
      // O evento de criação não afirma autoria factual.
      final created = detail.auditEvents.first;
      expect(created.user, isEmpty);
      expect(created.action, 'Registro criado');
    });

    test('peso COM autoria continua normalizando o nome (sem regressão)', () {
      final detail = RecordDetail.fromEntry(weightEntry(author: 'Ana'));

      expect(detail.author, 'GCM Ana');
      expect(detail.handlerName, 'Ana');
    });

    test('outros tipos health sem autor mantêm fallback existente', () {
      final vaccine = HistoryEntry(
        id: 'vac_1',
        type: HistoryEntryType.health,
        title: 'Vacinação',
        subtitle: '',
        time: DateTime(2026, 8, 4, 10),
        author: '',
        tag: 'SAÚDE',
        icon: Icons.vaccines,
        color: Colors.teal,
        details: const {'_healthKind': 'vaccine'},
      );

      final detail = RecordDetail.fromEntry(vaccine);

      // Comportamento legado preservado para tipos que não são pesagem.
      expect(detail.author, 'GCM Ragonha');
      expect(detail.handlerName, 'Ragonha');
    });
  });

  testWidgets('detalhe de pesagem sem autoria omite identidade e vet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final detail = RecordDetail.fromEntry(
      HistoryEntry(
        id: 'weight_1',
        type: HistoryEntryType.health,
        title: 'Pesagem operacional registrada',
        subtitle: 'Peso atual: 32.0 kg',
        time: DateTime(2026, 8, 4, 10),
        author: '',
        authorId: '',
        tag: 'PESO',
        icon: Icons.monitor_weight_rounded,
        color: Colors.purple,
        details: const {'_healthKind': 'weight', 'Peso': '32.0 kg'},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: HistorySaudeBody(detail: detail)),
        ),
      ),
    );

    expect(find.textContaining('Ragonha'), findsNothing);
    expect(find.textContaining('GCM Ragonha'), findsNothing);
    expect(find.textContaining('desconhecido'), findsNothing);
    expect(find.textContaining('RA-'), findsNothing);
    // Bloco de responsável técnico não é renderizado sem vet factual.
    expect(find.text('RESPONSÁVEL TÉCNICO'), findsNothing);
  });

  group('scaffold completo do detalhe (RegistroDetalhePage)', () {
    // Fluxo real: HistoryEntry → RecordDetail.fromEntry → RegistroDetalhePage,
    // incluindo o card de identificação (onde o antigo 'GCM Ragonha' surgia).
    HistoryEntry weightEntry({required String author}) => HistoryEntry(
      id: 'weight_1',
      type: HistoryEntryType.health,
      title: 'Pesagem operacional registrada',
      subtitle: 'Peso atual: 32.0 kg',
      time: DateTime(2026, 8, 4, 10),
      author: author,
      authorId: author,
      tag: 'PESO',
      icon: Icons.monitor_weight_rounded,
      color: Colors.purple,
      originalModel: WeightRecord(
        id: 'weight_1',
        weightKg: 32.0,
        measuredAt: DateTime.utc(2026, 8, 4, 10),
        recordedBy: null,
      ),
      details: const {
        '_healthKind': 'weight',
        'Cão': 'Aracnid',
        'Peso': '32.0 kg',
      },
    );

    // Viewport largo evita overflow horizontal do card no ambiente de teste;
    // o card de identificação usa RichText, portanto os finders precisam de
    // findRichText: true para realmente atravessar seus TextSpans.
    Future<void> pump(WidgetTester tester, HistoryEntry entry) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: RegistroDetalhePage(entry: entry)),
      );
      await tester.pump();
    }

    testWidgets('pesagem sem autoria: card renderiza sem autor fabricado', (
      tester,
    ) async {
      await pump(tester, weightEntry(author: ''));

      // Detalhe renderiza e dado factual do K9 permanece visível no card.
      expect(find.byType(RegistroDetalhePage), findsOneWidget);
      expect(find.textContaining('Aracnid', findRichText: true), findsWidgets);

      // Nenhuma autoria fabricada em toda a árvore do scaffold (inclui o
      // card de identificação em RichText, onde o antigo 'GCM Ragonha' surgia).
      expect(find.textContaining('Ragonha', findRichText: true), findsNothing);
      expect(
        find.textContaining('desconhecido', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('RA-', findRichText: true), findsNothing);
      expect(
        find.textContaining('Criado por', findRichText: true),
        findsNothing,
      );
      // Responsável técnico ausente sem vet factual.
      expect(find.text('RESPONSÁVEL TÉCNICO'), findsNothing);
    });

    testWidgets('pesagem com autoria: card preserva o nome (sem regressão)', (
      tester,
    ) async {
      await pump(tester, weightEntry(author: 'Ana'));

      expect(find.byType(RegistroDetalhePage), findsOneWidget);
      // Normalização preservada: 'Ana' → 'GCM Ana' no card de identificação.
      expect(find.textContaining('Ana', findRichText: true), findsWidgets);
      expect(find.textContaining('Ragonha', findRichText: true), findsNothing);
    });
  });

  // FF-OCC-09.C3.1 — REGRESSION GUARD: only a proven intact verdict may look
  // verified in the occurrence integrity card.
  //
  // R1 found the card rendering IntegrityStatus.unverified as green + verified
  // shield, because every non-broken/non-legacy status fell through to a
  // success `else`. C2 fixed the source; these tests are the permanent killers,
  // since 3039 green tests never touched this presentation.
  //
  // Hermetic by construction: each case injects an integrityVerifier, so no
  // Firestore and no call to the production verifyOccurrence endpoint happens.
  group('card de integridade da ocorrência (FF-OCC-09)', () {
    const occurrenceId = 'occ-ff-occ-09-ui';
    const storedSeal =
        '9e824cd05f75475ff88b2b2cb8adc26958b05a71bdaf70706935bfc13ac13371';

    Occurrence sealedOccurrence() {
      final now = DateTime.utc(2026, 8, 25, 10);
      return Occurrence(
        id: occurrenceId,
        shiftId: 'shift-ui',
        primaryHandlerId: 'handler-ui',
        dogId: 'dog-ui',
        typeCode: 'BUSCA',
        typeName: 'Ocorrencia com entorpecente',
        startedAt: now,
        createdAt: now,
        updatedAt: now.add(const Duration(hours: 2)),
        finalizedAt: now.add(const Duration(hours: 2)),
        status: OccurrenceStatus.finalized,
        integrityHash: storedSeal,
        hashVersion: 4,
      );
    }

    /// Finalized occurrence entry carrying a stored seal — the three conditions
    /// `_buildIntegrityBlock` requires to render the card. The visibility gate
    /// is exercised for real, never bypassed.
    HistoryEntry occurrenceEntry() => HistoryEntry(
      id: occurrenceId,
      type: HistoryEntryType.occurrence,
      title: 'Ocorrencia com entorpecente',
      subtitle: 'Finalizada',
      time: DateTime(2026, 8, 25, 10),
      author: 'GCM Silva',
      authorId: 'handler-ui',
      tag: 'OCORRENCIA',
      icon: Icons.local_police_rounded,
      color: Colors.blue,
      originalModel: sealedOccurrence(),
      details: const {'Status': 'Finalizado'},
    );

    /// Pumps the real page with the verifier boundary substituted. Returns how
    /// many times the injected verifier was invoked, proving the production
    /// service was never reached.
    /// Mounts the real [HistoryDetailScaffold] — the widget that owns
    /// `_buildIntegrityBlock` and therefore the visibility gate and the whole
    /// status→colour/icon mapping under test. The specialized body is a sibling
    /// of the integrity card and is replaced by an empty box: mounting
    /// `HistoryOccurrenceBody` would drag in `Provider<OccurrenceViewModel>`,
    /// which has nothing to do with this regression.
    ///
    /// Returns how many times the injected verifier ran, proving the production
    /// service was never reached.
    Future<int> pumpWithVerdict(
      WidgetTester tester,
      Future<IntegrityVerdict> Function() result,
    ) async {
      var calls = 0;
      tester.view.physicalSize = const Size(1400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryDetailScaffold(
            detail: RecordDetail.fromEntry(occurrenceEntry()),
            body: const SizedBox.shrink(),
            onPdfTap: () {},
            onShareTap: () {},
            onMenuTap: () {},
            integrityVerifier: ({required bool verifyMediaBytes}) {
              calls++;
              return result();
            },
          ),
        ),
      );
      // Settles the FutureBuilder so the resolved state is rendered.
      await tester.pumpAndSettle();
      return calls;
    }

    Color iconColor(WidgetTester tester, IconData icon) =>
        tester.widget<Icon>(find.byIcon(icon)).color!;

    testWidgets('intact: exibe sucesso verificado', (tester) async {
      final calls = await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(
          status: IntegrityStatus.intact,
          storedHash: storedSeal,
          hashVersion: 4,
        ),
      );

      expect(calls, 1, reason: 'O verificador injetado deve ser usado.');
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
      expect(find.byIcon(Icons.help_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.gpp_bad_outlined), findsNothing);
      expect(find.textContaining('INTEGRO'), findsWidgets);
    });

    testWidgets('unverified NAO parece verificado (mata M13)', (tester) async {
      final calls = await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(
          status: IntegrityStatus.unverified,
          storedHash: storedSeal,
          hashVersion: 4,
        ),
      );

      expect(calls, 1);
      expect(
        find.byIcon(Icons.verified_user_outlined),
        findsNothing,
        reason:
            'Verificacao indisponivel nunca pode exibir o escudo de '
            'verificado — foi exatamente o defeito F1 do R1.',
      );
      expect(find.byIcon(Icons.gpp_bad_outlined), findsNothing);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
      expect(find.textContaining('NAO DISPONIVEL'), findsWidgets);
      expect(find.textContaining('INTEGRO'), findsNothing);
    });

    testWidgets('erro na verificacao NAO afirma integridade (mata M14)', (
      tester,
    ) async {
      // Exercita o estado de erro real do FutureBuilder, nao uma variavel local.
      final calls = await pumpWithVerdict(
        tester,
        () async => throw StateError('verificador indisponivel'),
      );

      expect(calls, 1);
      expect(
        find.byIcon(Icons.verified_user_outlined),
        findsNothing,
        reason: 'Falha de verificacao nao é prova de integridade.',
      );
      expect(
        find.textContaining('INTEGRO'),
        findsNothing,
        reason: 'O fallback antigo dizia "Documento integro" — defeito F4.',
      );
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('unsealed NAO parece verificado (mata M15)', (tester) async {
      final calls = await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(status: IntegrityStatus.unsealed),
      );

      expect(calls, 1);
      expect(find.byIcon(Icons.verified_user_outlined), findsNothing);
      expect(find.textContaining('INTEGRO'), findsNothing);
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('broken preserva a apresentacao de selo quebrado', (
      tester,
    ) async {
      final calls = await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(
          status: IntegrityStatus.broken,
          storedHash: storedSeal,
          hashVersion: 4,
        ),
      );

      expect(calls, 1);
      expect(find.byIcon(Icons.gpp_bad_outlined), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsNothing);
      expect(find.textContaining('QUEBRADO'), findsWidgets);
    });

    testWidgets('a cor de incerteza difere da cor de sucesso', (tester) async {
      // Compara cores renderizadas em vez de duplicar as constantes privadas
      // _green/_amber no teste.
      await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(status: IntegrityStatus.intact),
      );
      final successColor = iconColor(tester, Icons.verified_user_outlined);

      // Unmount before the second scenario: repumping the same widget type
      // reuses the element, so the card's State (and its already-resolved
      // _future) would survive and keep rendering the first verdict.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await pumpWithVerdict(
        tester,
        () async => const IntegrityVerdict(status: IntegrityStatus.unverified),
      );
      final unverifiedColor = iconColor(tester, Icons.help_outline_rounded);

      expect(
        unverifiedColor,
        isNot(successColor),
        reason: 'Incerteza nao pode herdar a cor de integridade comprovada.',
      );
    });
  });
}
