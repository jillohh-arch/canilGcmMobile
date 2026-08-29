import 'authoritative_time_gateway.dart';
import 'authoritative_time_models.dart';
import 'monotonic_elapsed_clock.dart';

final class AuthoritativeTimeProvider {
  AuthoritativeTimeProvider({
    required AuthoritativeTimeGateway gateway,
    MonotonicElapsedClock? monotonicClock,
  }) : _gateway = gateway,
       _clock = monotonicClock ?? StopwatchMonotonicElapsedClock();

  static const Duration freshWindow = Duration(minutes: 5);
  static const Duration maximumRoundTrip = Duration(seconds: 10);
  static const Duration maximumUncertainty = Duration(seconds: 5);

  final AuthoritativeTimeGateway _gateway;
  final MonotonicElapsedClock _clock;

  AuthoritativeTimeSnapshot? _snapshot;
  Future<AuthoritativeTimeSyncResult>? _inFlight;
  AuthoritativeTimeFailure? _lastFailure;
  bool _synchronizing = false;
  bool _failedWithoutSnapshot = false;
  int _generation = 0;

  AuthoritativeTimeFailure? get lastFailure => _lastFailure;

  AuthoritativeTimeSnapshot? get currentSnapshot {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    return snapshot.copyWithStatus(_snapshotStatus(snapshot));
  }

  AuthoritativeTimeStatus get status {
    if (_synchronizing) return AuthoritativeTimeStatus.synchronizing;
    final snapshot = _snapshot;
    if (snapshot != null) return _snapshotStatus(snapshot);
    if (_failedWithoutSnapshot) return AuthoritativeTimeStatus.failed;
    return AuthoritativeTimeStatus.neverSynchronized;
  }

  /// Horário apto a decisões e ações temporais. Stale nunca é aceito.
  DateTime? nowFreshUtc() {
    final snapshot = _snapshot;
    if (snapshot == null ||
        _snapshotStatus(snapshot) != AuthoritativeTimeStatus.fresh) {
      return null;
    }
    return _nowFrom(snapshot);
  }

  /// Horário somente para consulta diagnosticada. Aceita fresh ou stale.
  DateTime? nowReadOnlyUtc() {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    final snapshotStatus = _snapshotStatus(snapshot);
    if (snapshotStatus != AuthoritativeTimeStatus.fresh &&
        snapshotStatus != AuthoritativeTimeStatus.stale) {
      return null;
    }
    return _nowFrom(snapshot);
  }

  /// Alias fail-closed para consumidores que exigem horário operacional.
  DateTime? nowUtc() => nowFreshUtc();

  Future<AuthoritativeTimeSyncResult> synchronize({bool force = false}) {
    final active = _inFlight;
    if (active != null) return active;

    final existing = currentSnapshot;
    if (!force && existing?.status == AuthoritativeTimeStatus.fresh) {
      return Future<AuthoritativeTimeSyncResult>.value(
        AuthoritativeTimeSyncSuccess(existing!),
      );
    }

    _synchronizing = true;
    final generation = _generation;
    late final Future<AuthoritativeTimeSyncResult> operation;
    operation = _performSynchronization(generation).whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
        _synchronizing = false;
      }
    });
    _inFlight = operation;
    return operation;
  }

  Future<AuthoritativeTimeSyncResult> _performSynchronization(
    int generation,
  ) async {
    final t0 = _clock.elapsed;
    try {
      final response = await _gateway.fetchAuthoritativeTime();
      final t3 = _clock.elapsed;
      final roundTrip = _checkedDifference(t3, t0);
      final serverProcessing = response.serverSentAtUtc.difference(
        response.requestReceivedAtUtc,
      );
      if (serverProcessing.isNegative || serverProcessing > roundTrip) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.invalidMeasurement,
          'Processamento do servidor incompatível com o RTT.',
        );
      }

      final networkRoundTrip = roundTrip - serverProcessing;
      if (networkRoundTrip.isNegative) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.invalidMeasurement,
          'RTT de rede temporal inválido.',
        );
      }
      final uncertainty = Duration(
        microseconds: networkRoundTrip.inMicroseconds ~/ 2,
      );
      if (uncertainty > maximumUncertainty) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.excessiveUncertainty,
          'Incerteza temporal acima do limite seguro.',
        );
      }
      if (roundTrip > maximumRoundTrip) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.excessiveRoundTrip,
          'RTT temporal acima do limite seguro.',
        );
      }

      final anchor = response.serverSentAtUtc.add(uncertainty);
      if (generation != _generation) return _invalidatedResult();
      _rejectRegressiveAnchor(
        newAnchor: anchor,
        newUncertainty: uncertainty,
        atMonotonic: t3,
      );

      final snapshot = AuthoritativeTimeSnapshot(
        anchorServerUtcAtReceive: anchor,
        anchorMonotonicElapsed: t3,
        synchronizedServerUtc: response.serverSentAtUtc,
        roundTrip: roundTrip,
        serverProcessing: serverProcessing,
        networkRoundTrip: networkRoundTrip,
        uncertainty: uncertainty,
        maxAge: response.maxAge,
        requestId: response.requestId,
        source: AuthoritativeTimeSource.systemAuthoritativeTimeNow,
        status: AuthoritativeTimeStatus.fresh,
      );
      _snapshot = snapshot;
      _lastFailure = null;
      _failedWithoutSnapshot = false;
      return AuthoritativeTimeSyncSuccess(snapshot);
    } on AuthoritativeTimeFailure catch (failure) {
      if (generation != _generation) return _invalidatedResult();
      return _recordFailure(failure);
    } catch (_) {
      if (generation != _generation) return _invalidatedResult();
      return _recordFailure(
        const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unexpected,
          'Falha inesperada na sincronização temporal.',
        ),
      );
    }
  }

  AuthoritativeTimeSyncFailure _invalidatedResult() {
    return const AuthoritativeTimeSyncFailure(
      AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidated,
        'Sincronização temporal invalidada.',
      ),
    );
  }

  AuthoritativeTimeSyncFailure _recordFailure(
    AuthoritativeTimeFailure failure,
  ) {
    _lastFailure = failure;
    _failedWithoutSnapshot = _snapshot == null;
    return AuthoritativeTimeSyncFailure(
      failure,
      retainedSnapshot: currentSnapshot,
    );
  }

  Duration _checkedDifference(Duration later, Duration earlier) {
    final value = later - earlier;
    if (value.isNegative) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.invalidMeasurement,
        'Relógio monotônico regressivo.',
      );
    }
    return value;
  }

  void _rejectRegressiveAnchor({
    required DateTime newAnchor,
    required Duration newUncertainty,
    required Duration atMonotonic,
  }) {
    final previous = _snapshot;
    if (previous == null) return;
    final previousAtNewMeasurement = previous.anchorServerUtcAtReceive.add(
      _checkedDifference(atMonotonic, previous.anchorMonotonicElapsed),
    );
    final previousEarliest = previousAtNewMeasurement.subtract(
      previous.uncertainty,
    );
    final newLatest = newAnchor.add(newUncertainty);
    if (newLatest.isBefore(previousEarliest)) {
      throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.regressiveAnchor,
        'Nova âncora temporal é regressiva fora da incerteza.',
      );
    }
  }

  AuthoritativeTimeStatus _snapshotStatus(AuthoritativeTimeSnapshot snapshot) {
    final age = _clock.elapsed - snapshot.anchorMonotonicElapsed;
    if (age.isNegative || age > snapshot.maxAge) {
      return AuthoritativeTimeStatus.expired;
    }
    if (age <= freshWindow) return AuthoritativeTimeStatus.fresh;
    return AuthoritativeTimeStatus.stale;
  }

  DateTime _nowFrom(AuthoritativeTimeSnapshot snapshot) {
    final elapsed = _checkedDifference(
      _clock.elapsed,
      snapshot.anchorMonotonicElapsed,
    );
    return snapshot.anchorServerUtcAtReceive.add(elapsed);
  }

  void invalidate() {
    _generation += 1;
    _snapshot = null;
    _inFlight = null;
    _synchronizing = false;
    _lastFailure = null;
    _failedWithoutSnapshot = false;
  }
}
