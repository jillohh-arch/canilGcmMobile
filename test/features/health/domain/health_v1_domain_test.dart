import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_transitions.dart';
import 'package:flutter_test/flutter_test.dart';

final class _DomainTimestampLike {
  _DomainTimestampLike(this.value);
  DateTime value;
  DateTime toDate() => value;
}

void main() {
  final actor = RecordedBy(
    uid: ' user-1 ',
    name: ' Condutor Teste ',
    internalRole: ' condutor ',
  );
  final now = DateTime.utc(2026, 7, 14, 12);

  ClinicalCase caseWith(ClinicalCaseStatus status) => ClinicalCase(
    id: 'case-1',
    dogId: 'dog-1',
    title: 'Avaliação clínica',
    status: status,
    openedAt: DateTime.utc(2026, 7, 14),
    openingEventId: 'event-opening',
    openingType: ClinicalCaseOpeningType.incident,
    recordedBy: actor,
    schemaVersion: 1,
  );

  ClinicalEvent eventWith(ClinicalEventStatus status) => ClinicalEvent(
    id: 'event-1',
    caseId: 'case-1',
    type: ClinicalEventType.incident,
    status: status,
    occurredAt: DateTime.utc(2026, 7, 14, 10),
    recordedAt: DateTime.utc(2026, 7, 14, 11),
    recordedBy: actor,
    payloadType: 'incident_v1',
    payloadVersion: 1,
    schemaVersion: 1,
    content: const {'description': 'Claudicação'},
    cancelReason: status == ClinicalEventStatus.cancelled ? 'Duplicado' : null,
    cancelledAt: status == ClinicalEventStatus.cancelled ? now : null,
    cancelledBy: status == ClinicalEventStatus.cancelled ? actor : null,
  );

  group('Value objects', () {
    test('RecordedBy normaliza, valida e possui igualdade', () {
      expect(
        actor,
        RecordedBy(
          uid: 'user-1',
          name: 'Condutor Teste',
          internalRole: 'condutor',
        ),
      );
      for (final values in [
        ['', 'Nome', 'role'],
        ['uid', ' ', 'role'],
        ['uid', 'Nome', ''],
      ]) {
        expect(
          () => RecordedBy(
            uid: values[0],
            name: values[1],
            internalRole: values[2],
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
    });

    test('WeightKg cobre finitude, sinal e igualdade sem arredondar', () {
      expect(WeightKg(23.456), WeightKg(23.456));
      expect(WeightKg(23.456).value, 23.456);
      for (final invalid in [
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(() => WeightKg(invalid), throwsA(isA<HealthDomainException>()));
      }
    });

    test('HealthDomainException possui igualdade previsível', () {
      expect(
        const HealthDomainException('code', 'message'),
        const HealthDomainException('code', 'message'),
      );
    });
  });

  group('ClinicalCase transitions', () {
    test('matriz completa corresponde ao ADR-003', () {
      const expected = <ClinicalCaseStatus, Set<ClinicalCaseStatus>>{
        ClinicalCaseStatus.open: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.underInvestigation: {
          ClinicalCaseStatus.open,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.underTreatment: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.monitoring,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.monitoring: {
          ClinicalCaseStatus.underInvestigation,
          ClinicalCaseStatus.underTreatment,
          ClinicalCaseStatus.discharged,
          ClinicalCaseStatus.cancelled,
        },
        ClinicalCaseStatus.discharged: {},
        ClinicalCaseStatus.cancelled: {},
      };
      for (final origin in ClinicalCaseStatus.values) {
        for (final destination in ClinicalCaseStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          if (allowed) {
            expect(
              ClinicalCaseTransitions.transition(
                caseWith(origin),
                destination,
              ).status,
              destination,
              reason: reason,
            );
          } else {
            expect(
              () => ClinicalCaseTransitions.transition(
                caseWith(origin),
                destination,
              ),
              throwsA(isA<HealthDomainException>()),
              reason: reason,
            );
          }
        }
      }
    });

    test('reopen aceita quatro destinos e produz dados puros do evento', () {
      for (final destination in const [
        ClinicalCaseStatus.open,
        ClinicalCaseStatus.underInvestigation,
        ClinicalCaseStatus.underTreatment,
        ClinicalCaseStatus.monitoring,
      ]) {
        final original = caseWith(ClinicalCaseStatus.discharged);
        final result = ClinicalCaseTransitions.reopen(
          original,
          destination: destination,
          reason: ' Alta prematura ',
          reopenedBy: actor,
          reopenedAt: now,
        );
        expect(result.clinicalCase.status, destination);
        expect(
          result.clinicalCase.previousStatus,
          ClinicalCaseStatus.discharged,
        );
        expect(result.clinicalCase.reopenedAt, now);
        expect(result.clinicalCase.reopenedBy, actor);
        expect(result.clinicalCase.reopenedCount, 1);
        expect(result.event.reason, 'Alta prematura');
        expect(result.event.destination, destination);
        expect(original.reopenedAt, isNull);
      }
    });

    test('reopen rejeita origem, destino e motivo inválidos', () {
      expect(
        () => ClinicalCaseTransitions.reopen(
          caseWith(ClinicalCaseStatus.open),
          destination: ClinicalCaseStatus.monitoring,
          reason: 'Erro',
          reopenedBy: actor,
          reopenedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ClinicalCaseTransitions.reopen(
          caseWith(ClinicalCaseStatus.discharged),
          destination: ClinicalCaseStatus.cancelled,
          reason: 'Erro',
          reopenedBy: actor,
          reopenedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ClinicalCaseTransitions.reopen(
          caseWith(ClinicalCaseStatus.discharged),
          destination: ClinicalCaseStatus.open,
          reason: ' ',
          reopenedBy: actor,
          reopenedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('copyWith permite limpar metadados anuláveis explicitamente', () {
      final reopened = ClinicalCaseTransitions.reopen(
        caseWith(ClinicalCaseStatus.discharged),
        destination: ClinicalCaseStatus.open,
        reason: 'Erro de alta',
        reopenedBy: actor,
        reopenedAt: now,
      ).clinicalCase;
      final cleared = reopened.copyWith(
        reopenedAt: null,
        reopenedBy: null,
        previousStatus: null,
        reopenReason: null,
        reopenedCount: 0,
      );
      expect(cleared.reopenReason, isNull);
      expect(cleared.reopenedAt, isNull);
    });

    test('rejeita schema e metadados de reabertura contraditórios', () {
      ClinicalCase build({
        int schemaVersion = 1,
        ClinicalCaseStatus status = ClinicalCaseStatus.open,
        ClinicalCaseStatus? previousStatus,
        bool reopened = false,
      }) => ClinicalCase(
        id: 'case-direct',
        dogId: 'dog-1',
        title: 'Caso',
        status: status,
        openedAt: now,
        openingEventId: 'event-1',
        openingType: ClinicalCaseOpeningType.preventive,
        recordedBy: actor,
        schemaVersion: schemaVersion,
        reopenedAt: reopened ? now : null,
        reopenedBy: reopened ? actor : null,
        previousStatus: previousStatus,
        reopenReason: reopened ? 'Erro' : null,
        reopenedCount: reopened ? 1 : 0,
      );

      for (final invalidSchema in [0, -1]) {
        expect(
          () => build(schemaVersion: invalidSchema),
          throwsA(isA<HealthDomainException>()),
        );
      }
      expect(build(), isNot(build(schemaVersion: 2)));
      expect(
        () => build(
          status: ClinicalCaseStatus.cancelled,
          previousStatus: ClinicalCaseStatus.discharged,
          reopened: true,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ClinicalCase(
          id: 'case-partial',
          dogId: 'dog-1',
          title: 'Caso',
          status: ClinicalCaseStatus.open,
          openedAt: now,
          openingEventId: 'event-1',
          openingType: ClinicalCaseOpeningType.incident,
          recordedBy: actor,
          schemaVersion: 1,
          reopenedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => build(previousStatus: ClinicalCaseStatus.open, reopened: true),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('ClinicalEvent', () {
    test('congela profundamente content e attachments', () {
      final nested = <String, Object?>{
        'map': <String, Object?>{'value': 'initial'},
        'list': <Object?>[
          <String, Object?>{'inside': true},
        ],
      };
      final attachments = <String>['doc-1'];
      final event = ClinicalEvent(
        id: 'event-1',
        caseId: 'case-1',
        type: ClinicalEventType.incident,
        status: ClinicalEventStatus.draft,
        occurredAt: now,
        recordedAt: now,
        recordedBy: actor,
        payloadType: 'incident_v1',
        payloadVersion: 1,
        schemaVersion: 1,
        content: nested,
        attachmentRefs: attachments,
      );
      (nested['map']! as Map<String, Object?>)['value'] = 'changed';
      (nested['list']! as List<Object?>).add('changed');
      attachments.add('doc-2');

      expect((event.content['map']! as Map)['value'], 'initial');
      expect((event.content['list']! as List), hasLength(1));
      expect(event.attachmentRefs, ['doc-1']);
      expect(
        () => (event.content['map']! as Map)['value'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (event.content['list']! as List).add('changed'),
        throwsUnsupportedError,
      );
    });

    test('rejeita tipo mutável arbitrário no payload', () {
      expect(
        () => ClinicalEvent(
          id: 'event-1',
          caseId: 'case-1',
          type: ClinicalEventType.incident,
          status: ClinicalEventStatus.draft,
          occurredAt: now,
          recordedAt: now,
          recordedBy: actor,
          payloadType: 'incident_v1',
          payloadVersion: 1,
          schemaVersion: 1,
          content: {'object': Object()},
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('rejeita ciclos e timestamp-like fora dos adapters', () {
      final cyclicMap = <String, Object?>{};
      cyclicMap['self'] = cyclicMap;
      final cyclicList = <Object?>[];
      cyclicList.add(cyclicList);
      final indirectMap = <String, Object?>{};
      final indirectList = <Object?>[indirectMap];
      indirectMap['list'] = indirectList;

      ClinicalEvent build(Map<String, Object?> content) => ClinicalEvent(
        id: 'event-cycle',
        caseId: 'case-1',
        type: ClinicalEventType.incident,
        status: ClinicalEventStatus.draft,
        occurredAt: now,
        recordedAt: now,
        recordedBy: actor,
        payloadType: 'incident_v1',
        payloadVersion: 1,
        schemaVersion: 1,
        content: content,
      );

      for (final content in [
        cyclicMap,
        <String, Object?>{'list': cyclicList},
        indirectMap,
        <String, Object?>{'timestamp': _DomainTimestampLike(now)},
      ]) {
        expect(() => build(content), throwsA(isA<HealthDomainException>()));
      }
      expect(() => build({'date': now}), returnsNormally);
    });

    test('rejeita cancelamento preenchido em draft ou final', () {
      for (final status in [
        ClinicalEventStatus.draft,
        ClinicalEventStatus.finalised,
      ]) {
        expect(
          () => ClinicalEvent(
            id: 'event-direct',
            caseId: 'case-1',
            type: ClinicalEventType.incident,
            status: status,
            occurredAt: now,
            recordedAt: now,
            recordedBy: actor,
            payloadType: 'incident_v1',
            payloadVersion: 1,
            schemaVersion: 1,
            content: const {},
            cancelReason: 'Erro',
            cancelledAt: now,
            cancelledBy: actor,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      expect(
        () => ClinicalEvent(
          id: 'event-cancelled',
          caseId: 'case-1',
          type: ClinicalEventType.incident,
          status: ClinicalEventStatus.cancelled,
          occurredAt: now,
          recordedAt: now,
          recordedBy: actor,
          payloadType: 'incident_v1',
          payloadVersion: 1,
          schemaVersion: 1,
          content: const {},
          cancelReason: 'Incompleto',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('validação temporal aceita igualdade e rejeita futuro', () {
      final event = eventWith(ClinicalEventStatus.draft);
      event.validateOccurredAt(referenceTime: event.occurredAt);
      expect(
        () => event.validateOccurredAt(
          referenceTime: event.occurredAt.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('matriz completa e cancelamento com metadados', () {
      const expected = <ClinicalEventStatus, Set<ClinicalEventStatus>>{
        ClinicalEventStatus.draft: {
          ClinicalEventStatus.finalised,
          ClinicalEventStatus.cancelled,
        },
        ClinicalEventStatus.finalised: {ClinicalEventStatus.cancelled},
        ClinicalEventStatus.cancelled: {},
      };
      for (final origin in ClinicalEventStatus.values) {
        for (final destination in ClinicalEventStatus.values) {
          final allowed = expected[origin]!.contains(destination);
          final reason = '${origin.wireName} → ${destination.wireName}';
          if (!allowed) {
            expect(
              () => ClinicalEventTransitions.transition(
                eventWith(origin),
                destination,
              ),
              throwsA(isA<HealthDomainException>()),
              reason: reason,
            );
          } else if (destination == ClinicalEventStatus.cancelled) {
            final original = eventWith(origin);
            final cancelled = ClinicalEventTransitions.transition(
              original,
              destination,
              cancelReason: ' Duplicado ',
              cancelledAt: now,
              cancelledBy: actor,
            );
            expect(cancelled.cancelReason, 'Duplicado');
            expect(cancelled.cancelledAt, now);
            expect(cancelled.cancelledBy, actor);
            expect(cancelled.content, original.content);
          } else {
            expect(
              ClinicalEventTransitions.transition(
                eventWith(origin),
                destination,
              ).status,
              destination,
              reason: reason,
            );
          }
        }
      }
    });

    test('cancelamento exige motivo, instante e autoria', () {
      final event = eventWith(ClinicalEventStatus.draft);
      expect(
        () => ClinicalEventTransitions.transition(
          event,
          ClinicalEventStatus.cancelled,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ClinicalEventTransitions.transition(
          event,
          ClinicalEventStatus.cancelled,
          cancelReason: 'motivo',
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });

  group('WeightAssessment e MealLog', () {
    test('WeightAssessment valida identidade, igualdade e data futura', () {
      final assessment = WeightAssessment(
        id: 'weight-1',
        dogId: 'dog-1',
        weight: WeightKg(25),
        measuredAt: now,
        recordedBy: actor,
        schemaVersion: 1,
      );
      expect(
        assessment,
        WeightAssessment(
          id: 'weight-1',
          dogId: 'dog-1',
          weight: WeightKg(25),
          measuredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
        ),
      );
      expect(
        assessment,
        isNot(
          WeightAssessment(
            id: 'weight-1',
            dogId: 'dog-1',
            weight: WeightKg(25),
            measuredAt: now,
            recordedBy: actor,
            schemaVersion: 2,
          ),
        ),
      );
      assessment.validateMeasuredAt(referenceTime: now);
      expect(
        () => assessment.validateMeasuredAt(
          referenceTime: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => WeightAssessment(
          id: '',
          dogId: 'dog-1',
          weight: WeightKg(25),
          measuredAt: now,
          recordedBy: actor,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      for (final invalidSchema in [0, -1]) {
        expect(
          () => WeightAssessment(
            id: 'weight-1',
            dogId: 'dog-1',
            weight: WeightKg(25),
            measuredAt: now,
            recordedBy: actor,
            schemaVersion: invalidSchema,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
    });

    test('MealLog aceita períodos canônicos e unknown explícito', () {
      for (final period in MealPeriod.values) {
        final meal = MealLog(
          id: 'meal-1',
          dogId: 'dog-1',
          period: MealPeriodWire.parseCanonical(period.wireName),
          amountGrams: 300,
          fedAt: now,
          recordedBy: actor,
          schemaVersion: 1,
        );
        expect(meal.period.value, period);
      }
      final unknown = MealLog(
        id: 'meal-2',
        dogId: 'dog-1',
        period: ParsedHealthEnum.unknown('madrugada'),
        amountGrams: 100,
        fedAt: now,
        recordedBy: actor,
        schemaVersion: 1,
      );
      expect(unknown.period.raw, 'madrugada');
      expect(
        unknown,
        isNot(
          MealLog(
            id: 'meal-2',
            dogId: 'dog-1',
            period: ParsedHealthEnum.unknown('madrugada'),
            amountGrams: 100,
            fedAt: now,
            recordedBy: actor,
            schemaVersion: 2,
          ),
        ),
      );
    });

    test('MealLog rejeita ausência, quantidade inválida e futuro', () {
      for (final invalid in [
        0,
        -1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          () => MealLog(
            id: 'meal-1',
            dogId: 'dog-1',
            period: MealPeriodWire.parseCanonical('morning'),
            amountGrams: invalid,
            fedAt: now,
            recordedBy: actor,
            schemaVersion: 1,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      expect(
        () => MealLog(
          id: 'meal-1',
          dogId: 'dog-1',
          period: const ParsedHealthEnum.absent(),
          amountGrams: 100,
          fedAt: now,
          recordedBy: actor,
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      for (final invalidSchema in [0, -1]) {
        expect(
          () => MealLog(
            id: 'meal-1',
            dogId: 'dog-1',
            period: MealPeriodWire.parseCanonical('morning'),
            amountGrams: 100,
            fedAt: now,
            recordedBy: actor,
            schemaVersion: invalidSchema,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      final meal = MealLog(
        id: 'meal-1',
        dogId: 'dog-1',
        period: MealPeriodWire.parseCanonical('morning'),
        amountGrams: 100,
        fedAt: now,
        recordedBy: actor,
        schemaVersion: 1,
      );
      meal.validateFedAt(referenceTime: now);
      expect(
        () => meal.validateFedAt(
          referenceTime: now.subtract(const Duration(seconds: 1)),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });
  });
}
