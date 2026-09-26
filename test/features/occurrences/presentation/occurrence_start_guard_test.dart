// FF-OCC-03 — REGRESSION GUARD for the central occurrence-start defence.
//
// The entrypoints (E1/E2) block navigation early, but a future or direct caller
// must not find a usable form without a crew. This file pins that the REAL
// StartOccurrenceScreen renders a blocking state instead of the form, and that
// loading is never presented as a confirmed missing vehicle.
//
// Firebase bootstrap, TEST-LOCAL ONLY: ShiftViewModel's constructor eagerly
// builds AuthService()/ShiftService(), which touch FirebaseAuth.instance and
// FirebaseFirestore.instance. Without a registered app that throws
// [core/no-app] before any widget is built — proven empirically by probe. The
// fake only satisfies construction-time plugin dependencies; the eligibility
// decision still comes from the real production helper, never from a mock.
// Pattern mirrors the precedent already established under
// test/features/occurrences/pdf/.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

import 'package:canil_gcm/features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:canil_gcm/features/dogs/presentation/viewmodels/dog_viewmodel.dart';
import 'package:canil_gcm/features/app_shell/presentation/screens/main_root_screen.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_event_repository.dart';
import 'package:canil_gcm/features/occurrences/domain/occurrence_start_eligibility.dart';
import 'package:canil_gcm/features/occurrences/data/occurrence_repository.dart';
import 'package:canil_gcm/features/occurrences/data/signature_repository.dart';
import 'package:canil_gcm/features/occurrences/presentation/screens/start_occurrence_screen.dart';
import 'package:canil_gcm/features/occurrences/presentation/view_models/occurrence_view_model.dart';
import 'package:canil_gcm/features/shifts/presentation/screens/active_shift_dashboard_screen.dart';
import 'package:canil_gcm/features/shifts/presentation/viewmodels/shift_viewmodel.dart';
import 'package:canil_gcm/features/users/presentation/viewmodels/user_viewmodel.dart';

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
          apiKey: 'ff-occ-03-api-key',
          appId: 'ff-occ-03-app-id',
          messagingSenderId: 'ff-occ-03-sender-id',
          projectId: 'ff-occ-03-project',
        ),
      );
}

FirebasePlatform? _originalFirebasePlatform;

/// Reports the shift facts the guard reads, without depending on Firebase
/// streams. Only the four observable getters are overridden; the decision
/// itself remains the production `evaluateOccurrenceStartEligibility`.
class _FakeShiftViewModel extends ShiftViewModel {
  _FakeShiftViewModel({
    this.fakeIsLoading = false,
    this.fakeError,
    this.fakeHasActiveShift = true,
    this.fakeVehicleCrewId = 'vehicle-crew-1075',
  });

  final bool fakeIsLoading;
  final String? fakeError;
  final bool fakeHasActiveShift;
  final String? fakeVehicleCrewId;

  @override
  bool get isLoading => fakeIsLoading;

  @override
  String? get error => fakeError;

  @override
  bool get hasActiveShift => fakeHasActiveShift;

  @override
  String? get vehicleCrewId => fakeVehicleCrewId;
}

OccurrenceViewModel _occurrenceVM(FakeFirebaseFirestore db) {
  return OccurrenceViewModel(
    repository: OccurrenceRepository(db),
    eventRepository: OccurrenceEventRepository(db),
    signatureRepository: SignatureRepository(firestore: db),
    sendTeamNotifications: false,
  );
}

/// Mounts the real screen with a controlled shift state.
Future<void> _pumpScreen(
  WidgetTester tester, {
  bool isLoading = false,
  String? shiftError,
  bool hasActiveShift = true,
  String? vehicleCrewId = 'vehicle-crew-1075',
}) async {
  final db = FakeFirebaseFirestore();
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ShiftViewModel>.value(
            value: _FakeShiftViewModel(
              fakeIsLoading: isLoading,
              fakeError: shiftError,
              fakeHasActiveShift: hasActiveShift,
              fakeVehicleCrewId: vehicleCrewId,
            ),
          ),
          ChangeNotifierProvider<OccurrenceViewModel>.value(
            value: _occurrenceVM(db),
          ),
          ChangeNotifierProvider<DogViewModel>(create: (_) => DogViewModel()),
          ChangeNotifierProvider<AuthViewModel>(create: (_) => AuthViewModel()),
          ChangeNotifierProvider<UserViewModel>(create: (_) => UserViewModel()),
        ],
        child: const StartOccurrenceScreen(),
      ),
    ),
  );
  await tester.pump();
}

/// The form's decisive control. Present only when the screen is usable.
final _formCta = find.textContaining('OCORR', findRichText: true);

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    _originalFirebasePlatform = FirebasePlatform.instance;
    FirebasePlatform.instance = _FakeFirebasePlatform();
  });

  tearDownAll(() {
    final original = _originalFirebasePlatform;
    if (original != null) {
      FirebasePlatform.instance = original;
      _originalFirebasePlatform = null;
    }
  });

  group('FF-OCC-03 M6 — central defensive guard', () {
    testWidgets('no vehicleCrewId: form is replaced by the crew prerequisite', (
      tester,
    ) async {
      await _pumpScreen(tester, vehicleCrewId: null);

      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsOneWidget,
        reason:
            'FF-OCC-03 M6 killer: a direct caller must not reach a usable '
            'form without a crew.',
      );
      expect(
        find.textContaining('Erro ao criar'),
        findsNothing,
        reason: 'The late submit-error prefix is the symptom being removed.',
      );
      expect(find.textContaining('StateError'), findsNothing);
    });

    testWidgets('blank vehicleCrewId is treated as absent', (tester) async {
      await _pumpScreen(tester, vehicleCrewId: '   ');

      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsOneWidget,
      );
    });

    testWidgets('M3: loading never claims a missing vehicle', (tester) async {
      await _pumpScreen(tester, isLoading: true, vehicleCrewId: null);

      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsNothing,
        reason:
            'FF-OCC-03 M3 killer: the shift load window lasts up to 8s. '
            'Accusing a missing vehicle there would block a valid operator.',
      );
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shift error is not reported as a missing vehicle', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        shiftError: 'Tempo excedido ao carregar turno ativo.',
        vehicleCrewId: null,
      );

      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsNothing,
      );
      expect(find.textContaining('Nao foi possivel confirmar'), findsOneWidget);
    });

    testWidgets('no active shift asks for a shift, not a vehicle', (
      tester,
    ) async {
      await _pumpScreen(tester, hasActiveShift: false, vehicleCrewId: null);

      expect(
        find.text('Inicie um turno para registrar ocorrência.'),
        findsOneWidget,
      );
      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsNothing,
      );
    });

    testWidgets('M5: a valid crew renders the real form, not a block', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(
        find.text('Assuma uma viatura antes de abrir ocorrência operacional.'),
        findsNothing,
        reason:
            'FF-OCC-03 M5 killer: the guard must not cost the operator a '
            'legitimate occurrence.',
      );
      expect(
        _formCta,
        findsWidgets,
        reason: 'The ready path must still reach the occurrence form.',
      );
    });
  });
  // FF-OCC-03 — ENTRYPOINT FAIL-EARLY regressions.
  //
  // These exercise the SAME orchestration functions production calls
  // (routeRootOccurrenceEntrypoint / routeQuickActionOccurrenceEntrypoint), not
  // a test-only copy. Mounting MainRootScreen or the shift dashboard is not
  // viable: they build every tab and drag in services that construct
  // FirebaseFirestore.instance in field initializers with no injection seam.
  //
  // Central blocking (M6 above) proves SAFETY. These prove FAIL-EARLY UX —
  // that the operator is stopped before navigating, which is the actual
  // FF-OCC-03 defect.
  group('FF-OCC-03 M1/M2/M8 — entrypoint orchestration', () {
    test('M1: E1 blocks a NEW occurrence when the crew is absent', () async {
      var navigated = false;
      var recovered = false;
      String? blockedWith;

      await routeRootOccurrenceEntrypoint(
        hasOpenOccurrence: false,
        eligibility: OccurrenceStartEligibility.noVehicleCrew,
        onRecoverOpenOccurrence: () async => recovered = true,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (m) => blockedWith = m,
      );

      expect(
        navigated,
        isFalse,
        reason:
            'FF-OCC-03 M1 killer: the root entrypoint must not navigate to the '
            'form without a crew. Central blocking alone would still let the '
            'operator leave the dashboard.',
      );
      expect(recovered, isFalse);
      expect(
        blockedWith,
        'Assuma uma viatura antes de abrir ocorrência operacional.',
      );
    });

    test('M8: an open occurrence is recovered, never intercepted', () async {
      var navigated = false;
      var recovered = false;
      String? blockedWith;

      // Eligibility would block a NEW occurrence — the guard must not apply.
      await routeRootOccurrenceEntrypoint(
        hasOpenOccurrence: true,
        eligibility: OccurrenceStartEligibility.noVehicleCrew,
        onRecoverOpenOccurrence: () async => recovered = true,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (m) => blockedWith = m,
      );

      expect(
        recovered,
        isTrue,
        reason:
            'FF-OCC-03 M8 killer: recovery of an already-created occurrence '
            'must survive. Its crew was validated when it was opened.',
      );
      expect(
        blockedWith,
        isNull,
        reason: 'The new-creation guard must not intercept recovery.',
      );
      expect(navigated, isFalse);
    });

    test('M8b: recovery wins even while the shift is still loading', () async {
      var recovered = false;
      String? blockedWith;

      await routeRootOccurrenceEntrypoint(
        hasOpenOccurrence: true,
        eligibility: OccurrenceStartEligibility.loading,
        onRecoverOpenOccurrence: () async => recovered = true,
        onStartNewOccurrence: () {},
        onBlocked: (m) => blockedWith = m,
      );

      expect(recovered, isTrue);
      expect(blockedWith, isNull);
    });

    test('E1 ready opens the form exactly once', () async {
      var navigated = 0;
      String? blockedWith;

      await routeRootOccurrenceEntrypoint(
        hasOpenOccurrence: false,
        eligibility: OccurrenceStartEligibility.ready,
        onRecoverOpenOccurrence: () async {},
        onStartNewOccurrence: () => navigated++,
        onBlocked: (m) => blockedWith = m,
      );

      expect(navigated, 1);
      expect(blockedWith, isNull);
    });

    test('M2: E2 blocks a NEW occurrence when the crew is absent', () {
      var navigated = false;
      String? blockedWith;

      routeQuickActionOccurrenceEntrypoint(
        eligibility: OccurrenceStartEligibility.noVehicleCrew,
        onStartNewOccurrence: () => navigated = true,
        onBlocked: (m) => blockedWith = m,
      );

      expect(
        navigated,
        isFalse,
        reason:
            'FF-OCC-03 M2 killer: the quick action had no check at all before '
            'this fix.',
      );
      expect(
        blockedWith,
        'Assuma uma viatura antes de abrir ocorrência operacional.',
      );
    });

    test('M2b: E2 ready navigates exactly once', () {
      var navigated = 0;
      String? blockedWith;

      routeQuickActionOccurrenceEntrypoint(
        eligibility: OccurrenceStartEligibility.ready,
        onStartNewOccurrence: () => navigated++,
        onBlocked: (m) => blockedWith = m,
      );

      expect(navigated, 1);
      expect(blockedWith, isNull);
    });

    test('M3 at both entrypoints: loading never accuses a missing vehicle', () {
      final messages = <String>[];

      routeQuickActionOccurrenceEntrypoint(
        eligibility: OccurrenceStartEligibility.loading,
        onStartNewOccurrence: () {},
        onBlocked: messages.add,
      );

      expect(messages.single.toLowerCase(), isNot(contains('viatura')));
    });

    test('both entrypoints agree on every blocking message', () async {
      for (final state in OccurrenceStartEligibility.values) {
        if (state.canStart) continue;
        String? viaRoot;
        String? viaQuick;

        await routeRootOccurrenceEntrypoint(
          hasOpenOccurrence: false,
          eligibility: state,
          onRecoverOpenOccurrence: () async {},
          onStartNewOccurrence: () {},
          onBlocked: (m) => viaRoot = m,
        );
        routeQuickActionOccurrenceEntrypoint(
          eligibility: state,
          onStartNewOccurrence: () {},
          onBlocked: (m) => viaQuick = m,
        );

        expect(
          viaRoot,
          viaQuick,
          reason: 'Message drift between entrypoints for $state.',
        );
        expect(viaRoot, isNot(contains('Erro ao criar')));
        expect(viaRoot, isNot(contains('StateError')));
      }
    });
  });
}
