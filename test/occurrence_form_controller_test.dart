import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/incidents/presentation/controllers/occurrence_form_controller.dart';

void main() {
  late OccurrenceFormController ctrl;

  setUp(() {
    ctrl = OccurrenceFormController();
  });

  group('OccurrenceFormController', () {
    group('startNewOccurrence', () {
      test('sets status to Em andamento', () {
        ctrl.startNewOccurrence();
        expect(ctrl.status, OccurrenceFormController.statusInProgress);
      });

      test('clears outcomes', () {
        ctrl.outcomes.add('Apoio prestado');
        ctrl.startNewOccurrence();
        expect(ctrl.outcomes, isEmpty);
      });

      test('sets successful to null', () {
        ctrl.successful = true;
        ctrl.startNewOccurrence();
        expect(ctrl.successful, isNull);
      });

      test('resets step to 0', () {
        ctrl.step = 3;
        ctrl.startNewOccurrence();
        expect(ctrl.step, 0);
      });
    });

    group('setStatus', () {
      test('sets status to given value', () {
        ctrl.setStatus(OccurrenceFormController.statusCompleted);
        expect(ctrl.status, OccurrenceFormController.statusCompleted);
      });

      test('sets successful to null when in progress', () {
        ctrl.successful = true;
        ctrl.setStatus(OccurrenceFormController.statusInProgress);
        expect(ctrl.successful, isNull);
      });

      test('defaults successful to true when finalizing', () {
        ctrl.successful = null;
        ctrl.setStatus(OccurrenceFormController.statusCompleted);
        expect(ctrl.successful, isTrue);
      });
    });

    group('selectNature', () {
      test('clears previous outcomes for detection (no defaults)', () {
        ctrl.outcomes.add('Apoio prestado');
        ctrl.selectNature(OccurrenceFormController.natureDetection);
        // Detection has no default outcomes
        expect(ctrl.outcomes, isEmpty);
      });

      test('sets default outcomes for support vehicle', () {
        ctrl.selectNature(OccurrenceFormController.natureSupportVehicle);
        expect(ctrl.outcomes, contains('Apoio prestado'));
      });
    });

    group('toggleOutcome', () {
      test('adds outcome and returns true', () {
        final added = ctrl.toggleOutcome('BO elaborado');
        expect(added, isTrue);
        expect(ctrl.outcomes, contains('BO elaborado'));
      });

      test('removes outcome and returns false', () {
        ctrl.outcomes.add('BO elaborado');
        final added = ctrl.toggleOutcome('BO elaborado');
        expect(added, isFalse);
        expect(ctrl.outcomes, isNot(contains('BO elaborado')));
      });
    });

    group('isFinalizing', () {
      test('returns false when in progress', () {
        ctrl.status = OccurrenceFormController.statusInProgress;
        expect(ctrl.isFinalizing, isFalse);
      });

      test('returns true when completed', () {
        ctrl.status = OccurrenceFormController.statusCompleted;
        expect(ctrl.isFinalizing, isTrue);
      });

      test('returns true when canceled', () {
        ctrl.status = OccurrenceFormController.statusCanceled;
        expect(ctrl.isFinalizing, isTrue);
      });
    });

    group('resultSummary', () {
      test('returns Em andamento when in progress', () {
        ctrl.status = OccurrenceFormController.statusInProgress;
        final result = ctrl.resultSummary(nature: null, fallback: 'Fallback');
        expect(result, OccurrenceFormController.statusInProgress);
      });

      test('returns Cancelada when canceled', () {
        ctrl.status = OccurrenceFormController.statusCanceled;
        final result = ctrl.resultSummary(nature: null, fallback: 'Fallback');
        expect(result, OccurrenceFormController.statusCanceled);
      });

      test('returns Exito when successful with no outcomes', () {
        ctrl.status = OccurrenceFormController.statusCompleted;
        ctrl.successful = true;
        final result = ctrl.resultSummary(nature: null, fallback: 'Fallback');
        expect(result, 'Êxito');
      });

      test('returns Sem exito when not successful with no outcomes', () {
        ctrl.status = OccurrenceFormController.statusCompleted;
        ctrl.successful = false;
        final result = ctrl.resultSummary(nature: null, fallback: 'Fallback');
        expect(result, 'Sem êxito');
      });

      test('returns fallback when successful is null and no outcomes', () {
        ctrl.status = OccurrenceFormController.statusCompleted;
        ctrl.successful = null;
        final result = ctrl.resultSummary(nature: null, fallback: 'Fallback');
        expect(result, 'Fallback');
      });
    });

    group('hasOutcomeContaining', () {
      test('finds outcome by partial text', () {
        ctrl.outcomes.add('Droga apreendida');
        expect(ctrl.hasDrugOutcome(), isTrue);
      });

      test('returns false when no match', () {
        ctrl.outcomes.add('Apoio prestado');
        expect(ctrl.hasDrugOutcome(), isFalse);
      });

      test('detects detained individual', () {
        ctrl.outcomes.add('Indivíduo detido');
        expect(ctrl.hasDetainedIndividualOutcome(), isTrue);
      });

      test('detects vehicle outcome', () {
        ctrl.outcomes.add('Veículo apreendido');
        expect(ctrl.hasVehicleOutcome(), isTrue);
      });
    });

    group('normalizeStatus', () {
      test('normalizes known statuses', () {
        expect(
          OccurrenceFormController.normalizeStatus('em andamento'),
          OccurrenceFormController.statusInProgress,
        );
        expect(
          OccurrenceFormController.normalizeStatus('cancelada'),
          OccurrenceFormController.statusCanceled,
        );
        expect(
          OccurrenceFormController.normalizeStatus('concluida'),
          OccurrenceFormController.statusCompleted,
        );
      });

      test('returns raw value for unrecognized status', () {
        expect(
          OccurrenceFormController.normalizeStatus('xyz'),
          'xyz',
        );
      });

      test('returns Concluida for empty status', () {
        expect(
          OccurrenceFormController.normalizeStatus(''),
          OccurrenceFormController.statusCompleted,
        );
      });
    });
  });
}
