import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_gateway.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_models.dart';
import 'package:canil_gcm/core/services/authoritative_time/authoritative_time_provider.dart';
import 'package:canil_gcm/core/services/authoritative_time/monotonic_elapsed_clock.dart';

final class _FakeMonotonicClock implements MonotonicElapsedClock {
  Duration value = Duration.zero;

  @override
  Duration get elapsed => value;

  void advance(Duration duration) => value += duration;
}

final class _CallbackGateway implements AuthoritativeTimeGateway {
  _CallbackGateway(this.callback);

  Future<AuthoritativeTimeRemoteResponse> Function() callback;
  int calls = 0;

  @override
  Future<AuthoritativeTimeRemoteResponse> fetchAuthoritativeTime() {
    calls += 1;
    return callback();
  }
}

AuthoritativeTimeRemoteResponse response({
  DateTime? received,
  DateTime? sent,
  String requestId = '00000000-0000-4000-8000-000000000001',
}) {
  final base = DateTime.utc(2026, 8, 2, 12);
  return AuthoritativeTimeRemoteResponse(
    protocolVersion: 1,
    requestId: requestId,
    requestReceivedAtUtc: received ?? base,
    serverSentAtUtc: sent ?? base,
    maxAge: const Duration(minutes: 15),
  );
}

void main() {
  test('computes RTT, processing, network, uncertainty and anchor', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 1000));
      return response(
        received: base,
        sent: base.add(const Duration(milliseconds: 200)),
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    final result = await provider.synchronize();
    final snapshot = (result as AuthoritativeTimeSyncSuccess).snapshot;

    expect(snapshot.roundTrip, const Duration(milliseconds: 1000));
    expect(snapshot.serverProcessing, const Duration(milliseconds: 200));
    expect(snapshot.networkRoundTrip, const Duration(milliseconds: 800));
    expect(snapshot.uncertainty, const Duration(milliseconds: 400));
    expect(
      snapshot.anchorServerUtcAtReceive,
      base.add(const Duration(milliseconds: 600)),
    );
  });

  test(
    'accepts RTT exactly 10 seconds and uncertainty exactly 5 seconds',
    () async {
      final clock = _FakeMonotonicClock();
      final base = DateTime.utc(2026, 8, 2, 12);
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async {
          clock.advance(const Duration(seconds: 10));
          return response(received: base, sent: base);
        }),
        monotonicClock: clock,
      );

      final result = await provider.synchronize();
      final snapshot = (result as AuthoritativeTimeSyncSuccess).snapshot;

      expect(snapshot.roundTrip, const Duration(seconds: 10));
      expect(snapshot.serverProcessing, Duration.zero);
      expect(snapshot.networkRoundTrip, const Duration(seconds: 10));
      expect(snapshot.uncertainty, const Duration(seconds: 5));
      expect(
        snapshot.anchorServerUtcAtReceive,
        base.add(const Duration(seconds: 5)),
      );
    },
  );

  test('accepts zero RTT and equal backend timestamps', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(
        () async => response(received: base, sent: base),
      ),
      monotonicClock: clock,
    );

    final result = await provider.synchronize();
    final snapshot = (result as AuthoritativeTimeSyncSuccess).snapshot;

    expect(snapshot.roundTrip, Duration.zero);
    expect(snapshot.serverProcessing, Duration.zero);
    expect(snapshot.networkRoundTrip, Duration.zero);
    expect(snapshot.uncertainty, Duration.zero);
    expect(snapshot.anchorServerUtcAtReceive, base);
  });

  test('rejects negative monotonic RTT without publishing an anchor', () async {
    final clock = _FakeMonotonicClock();
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        clock.value = const Duration(microseconds: -1);
        return response();
      }),
      monotonicClock: clock,
    );

    final result = await provider.synchronize();

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.invalidMeasurement,
    );
    expect(provider.currentSnapshot, isNull);
  });

  test(
    'accepts server processing equal to RTT with zero network time',
    () async {
      final clock = _FakeMonotonicClock();
      final base = DateTime.utc(2026, 8, 2, 12);
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async {
          clock.advance(const Duration(milliseconds: 25));
          return response(
            received: base,
            sent: base.add(const Duration(milliseconds: 25)),
          );
        }),
        monotonicClock: clock,
      );

      final result = await provider.synchronize();
      final snapshot = (result as AuthoritativeTimeSyncSuccess).snapshot;

      expect(snapshot.roundTrip, const Duration(milliseconds: 25));
      expect(snapshot.serverProcessing, const Duration(milliseconds: 25));
      expect(snapshot.networkRoundTrip, Duration.zero);
      expect(snapshot.uncertainty, Duration.zero);
      expect(
        snapshot.anchorServerUtcAtReceive,
        base.add(const Duration(milliseconds: 25)),
      );
    },
  );

  test('rejects negative server processing', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        clock.advance(const Duration(milliseconds: 1));
        return response(
          received: base,
          sent: base.subtract(const Duration(milliseconds: 1)),
        );
      }),
      monotonicClock: clock,
    );

    final result = await provider.synchronize();

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.invalidMeasurement,
    );
    expect(provider.currentSnapshot, isNull);
  });

  test('floors odd network microseconds without floating point math', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        clock.advance(const Duration(microseconds: 5));
        return response(received: base, sent: base);
      }),
      monotonicClock: clock,
    );

    final result = await provider.synchronize();
    final snapshot = (result as AuthoritativeTimeSyncSuccess).snapshot;

    expect(snapshot.networkRoundTrip, const Duration(microseconds: 5));
    expect(snapshot.uncertainty, const Duration(microseconds: 2));
    expect(
      snapshot.anchorServerUtcAtReceive,
      base.add(const Duration(microseconds: 2)),
    );
  });

  test('rejects RTT above 10 seconds', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(seconds: 10, microseconds: 1));
      return response(
        received: base,
        sent: base.add(const Duration(seconds: 1)),
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    final result = await provider.synchronize();

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.excessiveRoundTrip,
    );
    expect(provider.status, AuthoritativeTimeStatus.failed);
    expect(provider.nowFreshUtc(), isNull);
  });

  test('rejects uncertainty above 5 seconds', () async {
    final clock = _FakeMonotonicClock();
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(seconds: 10, microseconds: 2));
      return response();
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    final result = await provider.synchronize();

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.excessiveUncertainty,
    );
  });

  test('rejects server processing greater than RTT', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 50));
      return response(
        received: base,
        sent: base.add(const Duration(milliseconds: 51)),
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    final result = await provider.synchronize();

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.invalidMeasurement,
    );
  });

  test(
    'deduplicates concurrent synchronization with one gateway call',
    () async {
      final clock = _FakeMonotonicClock();
      final completer = Completer<AuthoritativeTimeRemoteResponse>();
      final gateway = _CallbackGateway(() => completer.future);
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: clock,
      );

      final first = provider.synchronize();
      final secondWithoutForce = provider.synchronize();
      final second = provider.synchronize(force: true);

      expect(identical(first, secondWithoutForce), isTrue);
      expect(identical(first, second), isTrue);
      expect(gateway.calls, 1);
      expect(provider.status, AuthoritativeTimeStatus.synchronizing);
      clock.advance(const Duration(milliseconds: 20));
      completer.complete(response());
      await first;
      expect(provider.status, AuthoritativeTimeStatus.fresh);
    },
  );

  test('fresh sync is reused and force refresh calls gateway', () async {
    final clock = _FakeMonotonicClock();
    var id = 0;
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 10));
      id += 1;
      return response(
        requestId: '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    await provider.synchronize();
    await provider.synchronize();
    expect(gateway.calls, 1);

    await provider.synchronize(force: true);
    expect(gateway.calls, 2);
    expect(
      provider.currentSnapshot?.requestId,
      '00000000-0000-4000-8000-000000000002',
    );
  });

  test('failure preserves valid snapshot and records diagnostic', () async {
    final clock = _FakeMonotonicClock();
    var fail = false;
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 10));
      if (fail) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unavailable,
          'offline',
        );
      }
      return response();
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    await provider.synchronize();
    fail = true;
    final result = await provider.synchronize(force: true);

    expect(result, isA<AuthoritativeTimeSyncFailure>());
    expect(provider.status, AuthoritativeTimeStatus.fresh);
    expect(provider.nowFreshUtc(), isNotNull);
    expect(
      provider.lastFailure?.code,
      AuthoritativeTimeFailureCode.unavailable,
    );
  });

  test('failure without snapshot is failed and has no time', () async {
    final gateway = _CallbackGateway(
      () async => throw const AuthoritativeTimeFailure(
        AuthoritativeTimeFailureCode.unavailable,
        'offline',
      ),
    );
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: _FakeMonotonicClock(),
    );

    await provider.synchronize();

    expect(provider.status, AuthoritativeTimeStatus.failed);
    expect(provider.nowFreshUtc(), isNull);
    expect(provider.nowReadOnlyUtc(), isNull);
  });

  test('incompatible regressive anchor is rejected', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    var call = 0;
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 200));
      call += 1;
      return response(
        received: call == 1 ? base : base.subtract(const Duration(seconds: 2)),
        sent: call == 1 ? base : base.subtract(const Duration(seconds: 2)),
        requestId:
            '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    await provider.synchronize();
    clock.advance(const Duration(milliseconds: 100));
    final result = await provider.synchronize(force: true);

    expect(
      (result as AuthoritativeTimeSyncFailure).failure.code,
      AuthoritativeTimeFailureCode.regressiveAnchor,
    );
    expect(
      provider.currentSnapshot?.requestId,
      '00000000-0000-4000-8000-000000000001',
    );
  });

  test('regression covered by uncertainty overlap is accepted', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    var call = 0;
    final gateway = _CallbackGateway(() async {
      clock.advance(const Duration(milliseconds: 200));
      call += 1;
      return response(
        received: call == 1
            ? base
            : base.add(const Duration(milliseconds: 150)),
        sent: call == 1 ? base : base.add(const Duration(milliseconds: 150)),
        requestId:
            '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
      );
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    await provider.synchronize();
    final result = await provider.synchronize(force: true);

    expect(result, isA<AuthoritativeTimeSyncSuccess>());
    expect(
      provider.currentSnapshot?.requestId,
      '00000000-0000-4000-8000-000000000002',
    );
  });

  test('accepts an anchor entirely posterior with zero uncertainty', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    var call = 0;
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        call += 1;
        return response(
          received: call == 1 ? base : base.add(const Duration(seconds: 2)),
          sent: call == 1 ? base : base.add(const Duration(seconds: 2)),
          requestId:
              '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
        );
      }),
      monotonicClock: clock,
    );

    await provider.synchronize();
    clock.advance(const Duration(seconds: 1));
    final result = await provider.synchronize(force: true);

    expect(result, isA<AuthoritativeTimeSyncSuccess>());
    expect(provider.currentSnapshot?.uncertainty, Duration.zero);
    expect(
      provider.currentSnapshot?.requestId,
      '00000000-0000-4000-8000-000000000002',
    );
  });

  test(
    'accepts anchor equality when candidate upper equals previous lower',
    () async {
      final clock = _FakeMonotonicClock();
      final base = DateTime.utc(2026, 8, 2, 12);
      var call = 0;
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async {
          clock.advance(const Duration(microseconds: 200));
          call += 1;
          return response(
            received: base,
            sent: base,
            requestId:
                '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
          );
        }),
        monotonicClock: clock,
      );

      await provider.synchronize();
      final result = await provider.synchronize(force: true);

      expect(result, isA<AuthoritativeTimeSyncSuccess>());
      expect(
        provider.currentSnapshot?.uncertainty,
        const Duration(microseconds: 100),
      );
      expect(
        provider.currentSnapshot?.requestId,
        '00000000-0000-4000-8000-000000000002',
      );
    },
  );

  test('accepts overlapping anchors at maximum uncertainty', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    var call = 0;
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        clock.advance(const Duration(seconds: 10));
        call += 1;
        final sent = call == 1 ? base : base.add(const Duration(seconds: 5));
        return response(
          received: sent,
          sent: sent,
          requestId:
              '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
        );
      }),
      monotonicClock: clock,
    );

    await provider.synchronize();
    final result = await provider.synchronize(force: true);

    expect(result, isA<AuthoritativeTimeSyncSuccess>());
    expect(provider.currentSnapshot?.uncertainty, const Duration(seconds: 5));
  });

  test('accepts posterior refresh from a stale snapshot', () async {
    final clock = _FakeMonotonicClock();
    final base = DateTime.utc(2026, 8, 2, 12);
    var call = 0;
    final provider = AuthoritativeTimeProvider(
      gateway: _CallbackGateway(() async {
        call += 1;
        final sent = call == 1
            ? base
            : base.add(const Duration(minutes: 6, seconds: 1));
        return response(
          received: sent,
          sent: sent,
          requestId:
              '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
        );
      }),
      monotonicClock: clock,
    );

    await provider.synchronize();
    clock.advance(const Duration(minutes: 6));
    expect(provider.status, AuthoritativeTimeStatus.stale);

    final result = await provider.synchronize(force: true);

    expect(result, isA<AuthoritativeTimeSyncSuccess>());
    expect(provider.status, AuthoritativeTimeStatus.fresh);
  });

  test(
    'expired snapshot recovers and reset paths remove prior reference',
    () async {
      final clock = _FakeMonotonicClock();
      final base = DateTime.utc(2026, 8, 2, 12);
      var call = 0;
      final gateway = _CallbackGateway(() async {
        call += 1;
        final sent = switch (call) {
          1 => base,
          2 => base.add(const Duration(minutes: 16, seconds: 1)),
          _ => base,
        };
        return response(
          received: sent,
          sent: sent,
          requestId:
              '00000000-0000-4000-8000-${call.toString().padLeft(12, '0')}',
        );
      });
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: clock,
      );

      await provider.synchronize();
      clock.advance(const Duration(minutes: 16));
      expect(provider.status, AuthoritativeTimeStatus.expired);

      final recovered = await provider.synchronize(force: true);
      expect(recovered, isA<AuthoritativeTimeSyncSuccess>());
      expect(provider.status, AuthoritativeTimeStatus.fresh);

      provider.invalidate();
      expect(await provider.synchronize(), isA<AuthoritativeTimeSyncSuccess>());

      final restarted = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async => response()),
        monotonicClock: _FakeMonotonicClock(),
      );
      expect(
        await restarted.synchronize(),
        isA<AuthoritativeTimeSyncSuccess>(),
      );
    },
  );

  test(
    'failed refresh preserves stale snapshot for read-only access',
    () async {
      final clock = _FakeMonotonicClock();
      var fail = false;
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async {
          if (fail) {
            throw const AuthoritativeTimeFailure(
              AuthoritativeTimeFailureCode.unavailable,
              'offline',
            );
          }
          return response();
        }),
        monotonicClock: clock,
      );

      await provider.synchronize();
      clock.advance(const Duration(minutes: 6));
      final staleTime = provider.nowReadOnlyUtc();
      fail = true;

      final result = await provider.synchronize(force: true);

      expect(result, isA<AuthoritativeTimeSyncFailure>());
      expect(provider.status, AuthoritativeTimeStatus.stale);
      expect(provider.nowFreshUtc(), isNull);
      expect(provider.nowReadOnlyUtc(), staleTime);
      expect(
        provider.lastFailure?.code,
        AuthoritativeTimeFailureCode.unavailable,
      );
    },
  );

  test(
    'synchronizing preserves fresh stale and expired capabilities',
    () async {
      Future<void> verifyAge({
        required Duration age,
        required AuthoritativeTimeStatus expectedSnapshotStatus,
        required bool freshAvailable,
        required bool readOnlyAvailable,
      }) async {
        final clock = _FakeMonotonicClock();
        final base = DateTime.utc(2026, 8, 2, 12);
        final completer = Completer<AuthoritativeTimeRemoteResponse>();
        var call = 0;
        final provider = AuthoritativeTimeProvider(
          gateway: _CallbackGateway(() {
            call += 1;
            if (call == 1) {
              return Future.value(response(received: base, sent: base));
            }
            return completer.future;
          }),
          monotonicClock: clock,
        );

        await provider.synchronize();
        clock.advance(age);
        final refresh = provider.synchronize(force: true);

        expect(provider.status, AuthoritativeTimeStatus.synchronizing);
        expect(provider.currentSnapshot?.status, expectedSnapshotStatus);
        expect(provider.nowFreshUtc() != null, freshAvailable);
        expect(provider.nowReadOnlyUtc() != null, readOnlyAvailable);
        expect(
          provider.currentSnapshot?.requestId,
          '00000000-0000-4000-8000-000000000001',
        );

        final sent = base.add(age);
        completer.complete(
          response(
            received: sent,
            sent: sent,
            requestId: '00000000-0000-4000-8000-000000000002',
          ),
        );
        expect(await refresh, isA<AuthoritativeTimeSyncSuccess>());
        expect(provider.status, AuthoritativeTimeStatus.fresh);
        expect(
          provider.currentSnapshot?.requestId,
          '00000000-0000-4000-8000-000000000002',
        );
      }

      await verifyAge(
        age: const Duration(minutes: 1),
        expectedSnapshotStatus: AuthoritativeTimeStatus.fresh,
        freshAvailable: true,
        readOnlyAvailable: true,
      );
      await verifyAge(
        age: const Duration(minutes: 6),
        expectedSnapshotStatus: AuthoritativeTimeStatus.stale,
        freshAvailable: false,
        readOnlyAvailable: true,
      );
      await verifyAge(
        age: const Duration(minutes: 16),
        expectedSnapshotStatus: AuthoritativeTimeStatus.expired,
        freshAvailable: false,
        readOnlyAvailable: false,
      );
    },
  );

  test(
    'new synchronization succeeds after invalidating an in-flight call',
    () async {
      final clock = _FakeMonotonicClock();
      final oldCompleter = Completer<AuthoritativeTimeRemoteResponse>();
      final gateway = _CallbackGateway(() => oldCompleter.future);
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: clock,
      );

      final oldOperation = provider.synchronize();
      provider.invalidate();
      gateway.callback = () async =>
          response(requestId: '00000000-0000-4000-8000-000000000002');

      final replacement = await provider.synchronize();
      expect(replacement, isA<AuthoritativeTimeSyncSuccess>());
      expect(
        provider.currentSnapshot?.requestId,
        '00000000-0000-4000-8000-000000000002',
      );

      oldCompleter.complete(response());
      final oldResult = await oldOperation;
      expect(
        (oldResult as AuthoritativeTimeSyncFailure).failure.code,
        AuthoritativeTimeFailureCode.invalidated,
      );
      expect(
        provider.currentSnapshot?.requestId,
        '00000000-0000-4000-8000-000000000002',
      );
    },
  );

  test(
    'advances only with monotonic elapsed and ignores civil clock changes',
    () async {
      final clock = _FakeMonotonicClock();
      final gateway = _CallbackGateway(() async => response());
      final provider = AuthoritativeTimeProvider(
        gateway: gateway,
        monotonicClock: clock,
      );
      var unrelatedCivilClock = DateTime.utc(2000);

      await provider.synchronize();
      final before = provider.nowFreshUtc()!;
      unrelatedCivilClock = DateTime.utc(2099);
      clock.advance(const Duration(minutes: 2));
      final after = provider.nowFreshUtc()!;

      expect(unrelatedCivilClock.year, 2099);
      expect(after.difference(before), const Duration(minutes: 2));
    },
  );

  test(
    'fresh/stale/expired boundaries and explicit access are fail-closed',
    () async {
      final clock = _FakeMonotonicClock();
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() async => response()),
        monotonicClock: clock,
      );
      await provider.synchronize();

      clock.advance(const Duration(minutes: 5));
      expect(provider.status, AuthoritativeTimeStatus.fresh);
      expect(provider.nowFreshUtc(), isNotNull);

      clock.advance(const Duration(microseconds: 1));
      expect(provider.status, AuthoritativeTimeStatus.stale);
      expect(provider.nowFreshUtc(), isNull);
      expect(provider.nowUtc(), isNull);
      expect(provider.nowReadOnlyUtc(), isNotNull);

      clock.advance(
        const Duration(minutes: 10) - const Duration(microseconds: 1),
      );
      expect(provider.status, AuthoritativeTimeStatus.stale);
      expect(provider.nowReadOnlyUtc(), isNotNull);

      clock.advance(const Duration(microseconds: 1));
      expect(provider.status, AuthoritativeTimeStatus.expired);
      expect(provider.nowReadOnlyUtc(), isNull);
    },
  );

  test('expired snapshot remains expired after failed refresh', () async {
    final clock = _FakeMonotonicClock();
    var fail = false;
    final gateway = _CallbackGateway(() async {
      if (fail) {
        throw const AuthoritativeTimeFailure(
          AuthoritativeTimeFailureCode.unavailable,
          'offline',
        );
      }
      return response();
    });
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );

    await provider.synchronize();
    clock.advance(const Duration(minutes: 16));
    fail = true;
    await provider.synchronize(force: true);

    expect(provider.status, AuthoritativeTimeStatus.expired);
    expect(provider.nowReadOnlyUtc(), isNull);
  });

  test('invalidate and new instance expose no temporal capability', () async {
    final clock = _FakeMonotonicClock();
    final gateway = _CallbackGateway(() async => response());
    final provider = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: clock,
    );
    await provider.synchronize();

    provider.invalidate();

    expect(provider.status, AuthoritativeTimeStatus.neverSynchronized);
    expect(provider.currentSnapshot, isNull);
    expect(provider.nowFreshUtc(), isNull);
    final restarted = AuthoritativeTimeProvider(
      gateway: gateway,
      monotonicClock: _FakeMonotonicClock(),
    );
    expect(restarted.status, AuthoritativeTimeStatus.neverSynchronized);
  });

  test(
    'invalidate prevents an in-flight response from restoring time',
    () async {
      final clock = _FakeMonotonicClock();
      final completer = Completer<AuthoritativeTimeRemoteResponse>();
      final provider = AuthoritativeTimeProvider(
        gateway: _CallbackGateway(() => completer.future),
        monotonicClock: clock,
      );

      final pending = provider.synchronize();
      provider.invalidate();
      clock.advance(const Duration(milliseconds: 10));
      completer.complete(response());
      final result = await pending;

      expect(
        (result as AuthoritativeTimeSyncFailure).failure.code,
        AuthoritativeTimeFailureCode.invalidated,
      );
      expect(provider.status, AuthoritativeTimeStatus.neverSynchronized);
      expect(provider.currentSnapshot, isNull);
      expect(provider.nowReadOnlyUtc(), isNull);
    },
  );
}
