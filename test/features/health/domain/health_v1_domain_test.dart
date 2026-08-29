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
      // CLIN-WRITER-1.W6.P0.D1 — esta combinação passou a ser LEGÍTIMA. Um caso
      // reaberto e depois cancelado preserva a história da última reabertura; a
      // asserção anterior exigia o inverso e tornava irrepresentável a história
      // lícita `discharge → reopen → cancel`. Ver o grupo dedicado abaixo.
      expect(
        build(
          status: ClinicalCaseStatus.cancelled,
          previousStatus: ClinicalCaseStatus.discharged,
          reopened: true,
        ).reopenedCount,
        1,
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

    // ── História de reabertura at-rest (CLIN-WRITER-1.W6.P0.D1) ──────────────
    //
    // `reopened_*` é HISTÓRICO: descreve a última reabertura bem-sucedida mais a
    // contagem acumulada. Sua validade NÃO depende do status atual do caso, senão
    // a história lícita `discharge → reopen → discharge` seria irrepresentável.

    ClinicalCase historyCase({
      required ClinicalCaseStatus status,
      required int reopenedCount,
      bool tuple = true,
      ClinicalCaseStatus? previousStatus = ClinicalCaseStatus.discharged,
      String? reopenReason = 'Alta prematura',
    }) => ClinicalCase(
      id: 'case-history',
      dogId: 'dog-1',
      title: 'Caso',
      status: status,
      openedAt: now,
      openingEventId: 'event-1',
      openingType: ClinicalCaseOpeningType.consultation,
      recordedBy: actor,
      schemaVersion: 1,
      reopenedAt: tuple ? now : null,
      reopenedBy: tuple ? actor : null,
      previousStatus: tuple ? previousStatus : null,
      reopenReason: tuple ? reopenReason : null,
      reopenedCount: reopenedCount,
    );

    test('história de reabertura é válida sob QUALQUER status atual', () {
      // A: nunca reaberto.
      expect(
        historyCase(
          status: ClinicalCaseStatus.open,
          reopenedCount: 0,
          tuple: false,
        ).reopenedCount,
        0,
      );
      // B..F: reaberto, sob todos os seis status canônicos — incluindo os
      // terminais `discharged` (D) e `cancelled` (E).
      for (final status in ClinicalCaseStatus.values) {
        final subject = historyCase(status: status, reopenedCount: 1);
        expect(subject.status, status);
        expect(subject.reopenedCount, 1);
        expect(subject.previousStatus, ClinicalCaseStatus.discharged);
        expect(subject.reopenedAt, now);
        expect(subject.reopenedBy, actor);
        expect(subject.reopenReason, 'Alta prematura');
      }
      // F: contagem cumulativa preservada.
      expect(
        historyCase(
          status: ClinicalCaseStatus.monitoring,
          reopenedCount: 2,
        ).reopenedCount,
        2,
      );
    });

    test(
      'discharge → reopen → discharge/cancel é representável de ponta a ponta',
      () {
        final discharged = caseWith(ClinicalCaseStatus.discharged);
        final reopened = ClinicalCaseTransitions.reopen(
          discharged,
          destination: ClinicalCaseStatus.underTreatment,
          reason: 'Alta prematura',
          reopenedBy: actor,
          reopenedAt: now,
        ).clinicalCase;
        expect(reopened.reopenedCount, 1);

        // Nova alta: antes de D1 esta transição era bloqueada, deixando o caso
        // preso para sempre em estados ativos.
        final rediscarged = ClinicalCaseTransitions.transition(
          reopened,
          ClinicalCaseStatus.discharged,
        );
        expect(rediscarged.status, ClinicalCaseStatus.discharged);
        expect(rediscarged.reopenedCount, 1);
        expect(rediscarged.reopenedAt, now);

        // Cancelamento de um caso previamente reaberto.
        final cancelled = ClinicalCaseTransitions.transition(
          reopened,
          ClinicalCaseStatus.cancelled,
        );
        expect(cancelled.status, ClinicalCaseStatus.cancelled);
        expect(cancelled.reopenedCount, 1);

        // Segunda reabertura a partir da nova alta: contagem acumula, nunca reseta.
        final second = ClinicalCaseTransitions.reopen(
          rediscarged,
          destination: ClinicalCaseStatus.monitoring,
          reason: 'Recidiva',
          reopenedBy: actor,
          reopenedAt: now,
        ).clinicalCase;
        expect(second.reopenedCount, 2);
        expect(second.reopenReason, 'Recidiva');
        expect(second.previousStatus, ClinicalCaseStatus.discharged);
      },
    );

    Matcher throwsDomainCode(String code) => throwsA(
      isA<HealthDomainException>().having((e) => e.code, 'code', code),
    );

    test('história de reabertura inválida continua fail-closed', () {
      // G: contagem negativa. O código é asserido: outras invariantes também
      // recusariam a contagem negativa, mas com códigos diferentes, e este guard
      // precisa ser o responsável.
      for (final invalid in [-1, -7]) {
        expect(
          () => historyCase(
            status: ClinicalCaseStatus.open,
            reopenedCount: invalid,
          ),
          throwsDomainCode('invalid_reopened_count'),
        );
        // Também sem tupla e com tupla parcial: a contagem negativa é recusada
        // por ESTE guard em qualquer configuração.
        expect(
          () => historyCase(
            status: ClinicalCaseStatus.open,
            reopenedCount: invalid,
            tuple: false,
          ),
          throwsDomainCode('invalid_reopened_count'),
        );
      }
      // L: autoria malformada é recusada pelo próprio value object.
      for (final blank in ['', '   ']) {
        expect(
          () => RecordedBy(uid: blank, name: 'N', internalRole: 'condutor'),
          throwsA(isA<HealthDomainException>()),
        );
        expect(
          () => RecordedBy(uid: 'u', name: blank, internalRole: 'condutor'),
          throwsA(isA<HealthDomainException>()),
        );
        expect(
          () => RecordedBy(uid: 'u', name: 'N', internalRole: blank),
          throwsA(isA<HealthDomainException>()),
        );
      }
      // H: contagem 0 com tupla completa.
      expect(
        () => historyCase(status: ClinicalCaseStatus.open, reopenedCount: 0),
        throwsA(isA<HealthDomainException>()),
      );
      // I: contagem > 0 sem tupla alguma.
      expect(
        () => historyCase(
          status: ClinicalCaseStatus.open,
          reopenedCount: 1,
          tuple: false,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      // J: previous_status diferente de discharged.
      for (final invalid in ClinicalCaseStatus.values) {
        if (invalid == ClinicalCaseStatus.discharged) continue;
        expect(
          () => historyCase(
            status: ClinicalCaseStatus.open,
            reopenedCount: 1,
            previousStatus: invalid,
          ),
          throwsA(isA<HealthDomainException>()),
          reason: 'previous_status ${invalid.wireName} deve ser recusado',
        );
      }
      // K: motivo em branco.
      for (final blank in ['', '   ']) {
        expect(
          () => historyCase(
            status: ClinicalCaseStatus.open,
            reopenedCount: 1,
            reopenReason: blank,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      // Também sob status terminal: afrouxar o status não afrouxou a tupla.
      expect(
        () => historyCase(
          status: ClinicalCaseStatus.cancelled,
          reopenedCount: 1,
          previousStatus: ClinicalCaseStatus.open,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => historyCase(
          status: ClinicalCaseStatus.discharged,
          reopenedCount: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('consistência at-rest NÃO é permissão para reabrir', () {
      // Um caso cancelado pode legitimamente carregar história de reabertura…
      expect(
        historyCase(
          status: ClinicalCaseStatus.cancelled,
          reopenedCount: 1,
        ).reopenedCount,
        1,
      );
      // …e ainda assim a AÇÃO de reabertura permanece negada a partir dele.
      expect(
        () => ClinicalCaseTransitions.reopen(
          historyCase(status: ClinicalCaseStatus.cancelled, reopenedCount: 1),
          destination: ClinicalCaseStatus.open,
          reason: 'Erro de alta',
          reopenedBy: actor,
          reopenedAt: now,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      // Origem continua sendo discharged apenas. O código é asserido: sem o
      // guard de origem, a construção do agregado ainda falharia, mas com
      // `inconsistent_reopen_metadata` — um erro de integridade at-rest, não a
      // recusa de autorização da AÇÃO. Os dois não são intercambiáveis.
      for (final from in ClinicalCaseStatus.values) {
        if (from == ClinicalCaseStatus.discharged) continue;
        expect(
          () => ClinicalCaseTransitions.reopen(
            caseWith(from),
            destination: ClinicalCaseStatus.open,
            reason: 'Erro de alta',
            reopenedBy: actor,
            reopenedAt: now,
          ),
          throwsDomainCode('invalid_case_reopen'),
          reason: 'reopen a partir de ${from.wireName} deve ser negado',
        );
      }
      // Destinos terminais continuam negados.
      for (final destination in const [
        ClinicalCaseStatus.discharged,
        ClinicalCaseStatus.cancelled,
      ]) {
        expect(
          () => ClinicalCaseTransitions.reopen(
            caseWith(ClinicalCaseStatus.discharged),
            destination: destination,
            reason: 'Erro de alta',
            reopenedBy: actor,
            reopenedAt: now,
          ),
          throwsDomainCode('invalid_case_reopen'),
        );
      }
      // E a reabertura legítima continua permitida para os quatro destinos.
      for (final destination in ClinicalCaseTransitions.reopenDestinations) {
        final result = ClinicalCaseTransitions.reopen(
          caseWith(ClinicalCaseStatus.discharged),
          destination: destination,
          reason: 'Erro de alta',
          reopenedBy: actor,
          reopenedAt: now,
        ).clinicalCase;
        expect(result.status, destination);
        expect(result.reopenedCount, 1);
      }
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
          offeredGrams: 300,
          acceptance: MealAcceptanceWire.parse('full'),
          fedAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 1,
        );
        expect(meal.period.value, period);
      }
      final unknown = MealLog(
        id: 'meal-2',
        dogId: 'dog-1',
        period: ParsedHealthEnum.unknown('madrugada'),
        offeredGrams: 100,
        acceptance: MealAcceptanceWire.parse('unknown'),
        fedAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
      );
      expect(unknown.period.raw, 'madrugada');
      expect(
        unknown,
        isNot(
          MealLog(
            id: 'meal-2',
            dogId: 'dog-1',
            period: ParsedHealthEnum.unknown('madrugada'),
            offeredGrams: 100,
            acceptance: MealAcceptanceWire.parse('unknown'),
            fedAt: now,
            recordedBy: actor,
            schemaVersion: 2,
            revision: 1,
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
            offeredGrams: invalid,
            acceptance: MealAcceptanceWire.parse('unknown'),
            fedAt: now,
            recordedBy: actor,
            schemaVersion: 1,
            revision: 1,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      expect(
        () => MealLog(
          id: 'meal-1',
          dogId: 'dog-1',
          period: const ParsedHealthEnum.absent(),
          offeredGrams: 100,
          acceptance: MealAcceptanceWire.parse('unknown'),
          fedAt: now,
          recordedBy: actor,
          schemaVersion: 1,
          revision: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
      for (final invalidSchema in [0, -1]) {
        expect(
          () => MealLog(
            id: 'meal-1',
            dogId: 'dog-1',
            period: MealPeriodWire.parseCanonical('morning'),
            offeredGrams: 100,
            acceptance: MealAcceptanceWire.parse('unknown'),
            fedAt: now,
            recordedBy: actor,
            schemaVersion: invalidSchema,
            revision: 1,
          ),
          throwsA(isA<HealthDomainException>()),
        );
      }
      final meal = MealLog(
        id: 'meal-1',
        dogId: 'dog-1',
        period: MealPeriodWire.parseCanonical('morning'),
        offeredGrams: 100,
        acceptance: MealAcceptanceWire.parse('unknown'),
        fedAt: now,
        recordedBy: actor,
        schemaVersion: 1,
        revision: 1,
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
