// FF-OCC-03 — REGRESSION GUARD for the early occurrence-start precondition.
//
// Field problem: the operator entered the "abrir ocorrência" form without an
// assigned crew and only learned about it at submission, as
// "Erro ao criar ocorrência: StateError...".
//
// The naive fix (`if (!shiftVM.hasVehicle)`) would have introduced a second
// bug. `hasVehicle` is `_session?.hasVehicle ?? false`, so `false` also covers
// "session not loaded yet", "error" and "no active shift" — and the shift load
// window lasts up to 8 seconds. These tests pin the precedence that keeps
// loading from being reported as a missing vehicle.
//
// Pure by construction: no Flutter, no Provider, no Firebase, no I/O.

import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/occurrences/domain/occurrence_start_eligibility.dart';

/// Crew id shaped like the real one (the vehicle document id).
const _crewId = 'vehicle-crew-1075';

OccurrenceStartEligibility evaluate({
  bool isLoading = false,
  String? shiftError,
  bool hasActiveShift = true,
  String? vehicleCrewId = _crewId,
}) {
  return evaluateOccurrenceStartEligibility(
    isLoading: isLoading,
    shiftError: shiftError,
    hasActiveShift: hasActiveShift,
    vehicleCrewId: vehicleCrewId,
  );
}

void main() {
  group('FF-OCC-03 — occurrence start eligibility', () {
    test('ready only when shift is loaded, active and has a crew', () {
      expect(evaluate(), OccurrenceStartEligibility.ready);
      expect(evaluate().canStart, isTrue);
    });

    test('M5: a valid crew is never blocked', () {
      expect(
        evaluate(vehicleCrewId: _crewId).canStart,
        isTrue,
        reason:
            'The guard must not cost the operator a legitimate occurrence. '
            'Blocking a ready shift would be worse than the late error.',
      );
    });

    group('M3: loading must never read as a confirmed missing crew', () {
      test('loading alone is loading', () {
        expect(evaluate(isLoading: true), OccurrenceStartEligibility.loading);
      });

      test('loading with an absent crew is still loading', () {
        // The decisive case. Before the shift snapshot arrives, vehicleCrewId is
        // null simply because _session is null. Reporting "sem viatura" here
        // would block the operator during a normal 8-second load.
        expect(
          evaluate(isLoading: true, vehicleCrewId: null),
          OccurrenceStartEligibility.loading,
          reason:
              'FF-OCC-03 M3 killer: absent crew during loading is UNKNOWN, '
              'not confirmed absence.',
        );
      });

      test('loading outranks every other unresolved state', () {
        expect(
          evaluate(
            isLoading: true,
            shiftError: 'Tempo excedido ao carregar turno ativo.',
            hasActiveShift: false,
            vehicleCrewId: null,
          ),
          OccurrenceStartEligibility.loading,
        );
      });

      test('loading is not startable', () {
        expect(evaluate(isLoading: true).canStart, isFalse);
      });
    });

    group('shift error is distinct from a missing precondition', () {
      test('an error yields shiftError', () {
        expect(
          evaluate(shiftError: 'Tempo excedido ao carregar turno ativo.'),
          OccurrenceStartEligibility.shiftError,
        );
      });

      test('error outranks no-active-shift and absent crew', () {
        expect(
          evaluate(
            shiftError: 'Falha ao sincronizar turno.',
            hasActiveShift: false,
            vehicleCrewId: null,
          ),
          OccurrenceStartEligibility.shiftError,
        );
      });

      test('a blank error string is not an error', () {
        expect(evaluate(shiftError: '   '), OccurrenceStartEligibility.ready);
      });
    });

    group('no active shift', () {
      test('inactive shift yields noActiveShift', () {
        expect(
          evaluate(hasActiveShift: false),
          OccurrenceStartEligibility.noActiveShift,
        );
      });

      test('no active shift outranks absent crew', () {
        expect(
          evaluate(hasActiveShift: false, vehicleCrewId: null),
          OccurrenceStartEligibility.noActiveShift,
          reason:
              'Telling the operator to assume a vehicle while no shift exists '
              'would send them to the wrong action.',
        );
      });
    });

    group('M1/M2/M7: crew presence is the actual precondition', () {
      test('null crew on a loaded active shift is noVehicleCrew', () {
        expect(
          evaluate(vehicleCrewId: null),
          OccurrenceStartEligibility.noVehicleCrew,
        );
      });

      test('blank crew is treated as absent', () {
        expect(
          evaluate(vehicleCrewId: '   '),
          OccurrenceStartEligibility.noVehicleCrew,
          reason: 'Matches the trim() check the final validation performs.',
        );
      });

      test('an empty crew string is treated as absent', () {
        expect(
          evaluate(vehicleCrewId: ''),
          OccurrenceStartEligibility.noVehicleCrew,
        );
      });

      test('M7: vehicleId cannot influence this decision at all', () {
        // The hydrated-session hazard: ActiveShiftSession.fromJson reads
        // vehicleId from `vehicle_id` and vehicleCrewId from
        // `vehicle_crew_id`/`crew_id`, so a document can populate one without
        // the other. hasVehicle would then be true while the final validation
        // still rejects the submit.
        //
        // This decision takes no vehicleId parameter, so that false READY is
        // unrepresentable by construction. If someone adds one, this test's
        // premise breaks and the signature change becomes visible in review.
        expect(
          evaluate(vehicleCrewId: null),
          OccurrenceStartEligibility.noVehicleCrew,
          reason:
              'FF-OCC-03 M7 killer: only vehicleCrewId may produce ready, '
              'mirroring the minimum the authoritative path requires.',
        );
      });
    });

    group('block messages stay consistent across entrypoints', () {
      test('every blocking state carries a message', () {
        for (final state in OccurrenceStartEligibility.values) {
          final message = occurrenceStartBlockMessage(state);
          if (state.canStart) {
            expect(message, isNull, reason: 'ready needs no message.');
          } else {
            expect(
              message,
              isNotNull,
              reason: '$state must explain itself to the operator.',
            );
            expect(message!.trim(), isNotEmpty);
          }
        }
      });

      test(
        'the crew message preserves the established operational wording',
        () {
          expect(
            occurrenceStartBlockMessage(
              OccurrenceStartEligibility.noVehicleCrew,
            ),
            'Assuma uma viatura antes de abrir ocorrência operacional.',
          );
        },
      );

      test('the no-shift message reuses the canonical root-action copy', () {
        expect(
          occurrenceStartBlockMessage(OccurrenceStartEligibility.noActiveShift),
          'Inicie um turno para registrar ocorrência.',
        );
      });

      test('loading never accuses a missing vehicle', () {
        final message = occurrenceStartBlockMessage(
          OccurrenceStartEligibility.loading,
        )!.toLowerCase();

        expect(message, isNot(contains('viatura')));
        expect(message, isNot(contains('guarni')));
      });

      test('the error message never accuses a missing vehicle', () {
        final message = occurrenceStartBlockMessage(
          OccurrenceStartEligibility.shiftError,
        )!.toLowerCase();

        expect(message, isNot(contains('viatura')));
      });

      test('no early message carries the late submit-error prefix', () {
        for (final state in OccurrenceStartEligibility.values) {
          final message = occurrenceStartBlockMessage(state);
          if (message == null) continue;
          expect(
            message,
            isNot(contains('Erro ao criar')),
            reason:
                'The late generic prefix is exactly the symptom FF-OCC-03 '
                'removes.',
          );
          expect(message, isNot(contains('StateError')));
        }
      });
    });
  });
}
