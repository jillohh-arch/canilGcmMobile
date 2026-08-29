// FF-OCC-01.D1-E1 — DIAGNOSTIC HARNESS SUPPORT (test-only, not productive source).
//
// Purpose: let the REAL OccurrencePdfGenerator reach the REAL pdf layout engine
// (pw.Document.addPage / save) inside a plain `flutter test` run, with:
//   * NO live Firebase, NO Firestore I/O, NO Storage, NO Auth,
//   * NO external network,
//   * NO edits to productive source, package cache, or shared test helpers.
//
// Two blockers were measured in FF-OCC-01.D1-R and are neutralised here.
//
// 1) FIRESTORE. OccurrencePdfGenerator.generate() constructs `AmendmentRepository()`
//    directly (occurrence_pdf_generator.dart:93), which defaults to
//    `FirebaseFirestore.instance`. There is no injection seam, so a
//    FakeFirebaseFirestore cannot be handed to it without editing productive code
//    (forbidden). `FirebaseFirestorePlatform.instance` also cannot be swapped,
//    because its setter calls PlatformInterface.verify against a private token.
//    So we intercept one level lower: the pigeon BasicMessageChannel that
//    cloud_firestore uses for `queryGet`. We answer it locally with an EMPTY
//    snapshot. This is a pure in-process message handler — nothing leaves the
//    test isolate, and no Firestore document is read or written.
//    Channel name and payload shape verified against
//    cloud_firestore_platform_interface-8.0.1/lib/src/pigeon/messages.pigeon.dart.
//
// 2) FONTS. PdfFonts.load() calls PdfGoogleFonts.* which would normally fetch
//    IBM Plex from fonts.gstatic.com. We do NOT open the network, and we install
//    an EMPTY offline cache via `PdfBaseCache.defaultCache`, so every font lookup
//    misses. printing's `DownloadableFont.getFont()` wraps its download in
//    try/catch and returns the built-in `Font.helvetica()` on any failure.
//
//    So the effective, deliberate font policy is:
//        external HTTP blocked -> remote font unavailable -> Helvetica fallback.
//    Deterministic, offline, and identical on every machine and in CI.
//
//    FIDELITY CAVEAT — read this before citing these tests as visual evidence:
//    the suite NEVER runs on IBM Plex. Helvetica has different metrics and no
//    Unicode coverage, so glyph widths and line breaking do NOT match a real
//    device. That is adequate for the two defects these tests guard (a Flex
//    constraint precondition and a Border/borderRadius paint assert, neither of
//    which depends on glyphs), but it means this harness CANNOT reproduce
//    production typography and cannot settle any glyph- or line-break-driven
//    difference. Device homologation remains the only closure point for those.

import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart' show PdfBaseCache;

// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// Local, hermetic stand-in for firebase_core's platform implementation.
///
/// NOTE (D1-E1 finding): the shared `test/helpers/firebase_test_helper.dart`
/// mocks the LEGACY `MethodChannel('plugins.flutter.io/firebase_core')`, but
/// firebase_core_platform_interface 8.0.0 talks over PIGEON channels
/// (`dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.*`),
/// whose codec is private. So that helper cannot initialize Firebase for this
/// version — it fails with `channel-error` on initializeCore. Rather than edit the
/// shared helper (out of allowlist), we override the public platform seam
/// `FirebasePlatform.instance`, which is legal because `FirebasePlatform()` passes
/// its own verification token to PlatformInterface.
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
  }) async =>
      _app;
}

class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
      : super(
          defaultFirebaseAppName,
          const FirebaseOptions(
            apiKey: 'diagnostic-api-key',
            appId: 'diagnostic-app-id',
            messagingSenderId: 'diagnostic-sender-id',
            projectId: 'diagnostic-project',
          ),
        );
}

/// Outcome of one real-generator attempt.
///
/// This replaces the D1-R pattern where any exception was flattened into a string
/// and asserted with `isNotNull`, which made a pre-layout abort look like a pass.
enum PdfAttemptOutcome {
  /// generate() completed and produced PDF bytes: layout AND save both ran.
  generatedAndSaved,

  /// The target field failure: pdf's Flex rejected an unbounded main axis.
  expectedFlexException,

  /// Aborted BEFORE the layout engine (Firebase/Firestore/network/binding).
  /// Never counts as success — the harness is at fault, not the product.
  preLayoutFailure,

  /// Reached the layout engine but failed for some other reason.
  unexpectedException,
}

class PdfAttemptResult {
  final PdfAttemptOutcome outcome;
  final String detail;
  final String? stack;
  final int byteLength;

  const PdfAttemptResult({
    required this.outcome,
    required this.detail,
    this.stack,
    this.byteLength = 0,
  });

  /// True only when the real layout engine actually ran.
  bool get reachedLayout =>
      outcome == PdfAttemptOutcome.generatedAndSaved ||
      outcome == PdfAttemptOutcome.expectedFlexException ||
      outcome == PdfAttemptOutcome.unexpectedException;

  @override
  String toString() =>
      '${outcome.name}${byteLength > 0 ? ' ($byteLength bytes)' : ''}: $detail';
}

/// Substring thrown by pdf's flex.dart when a flex child meets an unbounded main
/// axis. The vertical axis renders the word "height".
const flexUnboundedHeightMessage =
    'Flex children have non-zero flex but incoming height constraints are unbounded';

/// Any flex-unbounded message, either axis, for classification.
const flexUnboundedAnyAxis =
    'Flex children have non-zero flex but incoming';

/// Marks failures that happened before any pdf widget was laid out.
bool isPreLayoutFailure(Object error) {
  final s = error.toString();
  return s.contains('core/no-app') ||
      s.contains('No Firebase App') ||
      s.contains('has not been initialized') ||
      s.contains('MissingPluginException') ||
      s.contains('Binding has not yet been initialized') ||
      s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('channel-error');
}

/// Classifies a thrown error into an outcome.
PdfAttemptResult classifyError(Object error, StackTrace st) {
  final msg = error.toString();
  final frames = st
      .toString()
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .take(12)
      .join('\n      ');

  if (msg.contains(flexUnboundedAnyAxis)) {
    return PdfAttemptResult(
      outcome: PdfAttemptOutcome.expectedFlexException,
      detail: msg.split('\n').first,
      stack: frames,
    );
  }
  if (isPreLayoutFailure(error)) {
    return PdfAttemptResult(
      outcome: PdfAttemptOutcome.preLayoutFailure,
      detail: '${error.runtimeType}: ${msg.split('\n').first}',
      stack: frames,
    );
  }
  return PdfAttemptResult(
    outcome: PdfAttemptOutcome.unexpectedException,
    detail: '${error.runtimeType}: ${msg.split('\n').first}',
    stack: frames,
  );
}

/// An offline cache: holds only what we pre-seed and never downloads.
/// For keys it does not hold, the pdf/printing package's own try/catch falls back
/// to Helvetica, so font resolution stays offline and deterministic.
class OfflinePdfCache extends PdfBaseCache {
  final Map<String, Uint8List> _store = {};

  @override
  Future<void> add(String key, Uint8List bytes) async => _store[key] = bytes;

  @override
  Future<Uint8List?> get(String key) async => _store[key];

  @override
  Future<bool> contains(String key) async => _store.containsKey(key);

  @override
  Future<void> remove(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();
}

/// Pigeon channel cloud_firestore uses for `Query.get()`.
const _queryGetChannel =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet';

/// Pigeon channel for `DocumentReference.get()` — stubbed too, so any incidental
/// document read also stays local instead of throwing a channel error.
const _docGetChannel =
    'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet';

/// Every Firestore channel call the generator made. Lets the report prove that
/// the interception happened locally and show exactly what was asked for.
final List<String> firestoreChannelCalls = <String>[];

ByteData _encodeEmptyQuerySnapshot() {
  final snapshot = InternalQuerySnapshot(
    documents: <InternalDocumentSnapshot?>[],
    documentChanges: <InternalDocumentChange?>[],
    metadata: InternalSnapshotMetadata(
      hasPendingWrites: false,
      isFromCache: false,
    ),
  );
  // Pigeon success envelope is a single-element list.
  return const PigeonCodec().encodeMessage(<Object?>[snapshot])!;
}

ByteData _encodeMissingDocumentSnapshot() {
  final snapshot = InternalDocumentSnapshot(
    path: 'occurrences/diagnostic',
    data: null,
    metadata: InternalSnapshotMetadata(
      hasPendingWrites: false,
      isFromCache: false,
    ),
  );
  return const PigeonCodec().encodeMessage(<Object?>[snapshot])!;
}

/// Any outbound HTTP attempt during the run. MUST stay empty.
final List<String> attemptedNetworkHosts = <String>[];

/// Blocks every outbound HTTP connection at the dart:io layer, so "hermetic" is
/// enforced rather than assumed. Any attempt is recorded and fails fast.
class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _BlockedHttpClient();
  }
}

class _BlockedHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    attemptedNetworkHosts.add(url.host);
    throw const SocketException(
      'FF-OCC-01.D1-E1: external network is blocked in this harness',
    );
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('get', url);

  @override
  noSuchMethod(Invocation invocation) {
    if (invocation.memberName == const Symbol('close')) return null;
    throw const SocketException(
      'FF-OCC-01.D1-E1: external network is blocked in this harness',
    );
  }
}

/// Installs the hermetic harness. Call from setUpAll().
///
/// Order matters: Firebase must be initialized BEFORE the generator runs,
/// otherwise `FirebaseFirestore.instance` throws [core/no-app] at
/// occurrence_pdf_generator.dart:93 and the pigeon stub never gets a chance to
/// answer (measured in the first D1-E1 run).
Future<void> installHermeticPdfHarness() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  HttpOverrides.global = _NoNetworkHttpOverrides();

  // Empty offline cache: nothing is pre-seeded and nothing can be downloaded, so
  // every font request misses and the printing package falls back to Helvetica.
  PdfBaseCache.defaultCache = OfflinePdfCache();

  // Hermetic Firebase core: local platform stand-in, no project, no network.
  FirebasePlatform.instance = _FakeFirebasePlatform();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  messenger.setMockMessageHandler(_queryGetChannel, (ByteData? message) async {
    firestoreChannelCalls.add('queryGet');
    return _encodeEmptyQuerySnapshot();
  });

  messenger.setMockMessageHandler(_docGetChannel, (ByteData? message) async {
    firestoreChannelCalls.add('documentReferenceGet');
    return _encodeMissingDocumentSnapshot();
  });
}

/// Removes the mock handlers so state does not leak into other test files.
void uninstallHermeticPdfHarness() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(_queryGetChannel, null);
  messenger.setMockMessageHandler(_docGetChannel, null);
  HttpOverrides.global = null;
}
