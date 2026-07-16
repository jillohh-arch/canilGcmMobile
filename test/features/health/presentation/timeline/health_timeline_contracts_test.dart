import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_cursor.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_entry_view.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_page.dart';
import 'package:canil_gcm/features/health/presentation/timeline/health_timeline_query.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_detail_reference.dart';
import 'package:canil_gcm/features/health/presentation/timeline/models/health_timeline_traceability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'timeline_test_helpers.dart';

void main() {
  group('HealthTimelineEntryView', () {
    test('criação completa com composição', () {
      final e = entry(
        id: 'e1',
        dogId: 'dog-a',
        type: HealthTimelineType.vaccination,
        title: 'Vacina V10',
        subtitle: 'Lote 123',
        caseId: 'case-1',
        caseTitle: 'Caso clínico',
        recordedBy: sampleRecorder(),
        professional: sampleProfessional(),
        operationalImpact: sampleImpact(),
        hasAttachments: true,
        attachmentCount: 2,
        amendments: HealthTimelineAmendmentMetadata(
          hasAmendments: true,
          amendmentCount: 1,
          lastAmendedAt: DateTime(2026, 7, 11),
        ),
        detailReference: const HealthTimelineDetailReference(
          sourceType: 'vaccination',
          sourceId: 'vr-1',
          caseId: 'case-1',
        ),
        traceability: const HealthTimelineTraceability(
          sourceCollection: 'vaccination_records',
          sourceId: 'vr-1',
          legacySource: 'vacinas',
          legacyId: 'old-1',
        ),
      );

      expect(e.id, 'e1');
      expect(e.dogId, 'dog-a');
      expect(e.type.known, HealthTimelineType.vaccination);
      expect(e.type.isKnown, isTrue);
      expect(e.title, 'Vacina V10');
      expect(e.subtitle, 'Lote 123');
      expect(e.status, HealthTimelineEntryStatus.finalised);
      expect(e.caseId, 'case-1');
      expect(e.recordedBy?.uid, 'u1');
      expect(e.professional?.name, 'Dra. Ana');
      expect(e.operationalImpact?.level, OperationalImpactLevel.low);
      expect(e.hasAttachments, isTrue);
      expect(e.attachmentCount, 2);
      expect(e.amendments.hasAmendments, isTrue);
      expect(e.amendments.amendmentCount, 1);
      expect(e.detailReference?.sourceId, 'vr-1');
      expect(e.traceability?.legacySource, 'vacinas');
      expect(e.isFinal, isTrue);
      expect(e.isCancelled, isFalse);
    });

    test('opcionais omitidos', () {
      final e = entry(id: 'e2', title: 'Peso');
      expect(e.subtitle, isNull);
      expect(e.caseId, isNull);
      expect(e.recordedBy, isNull);
      expect(e.professional, isNull);
      expect(e.operationalImpact, isNull);
      expect(e.detailReference, isNull);
      expect(e.traceability, isNull);
      expect(e.amendments.hasAmendments, isFalse);
      expect(e.amendments.amendmentCount, 0);
    });

    test('cancelled é representável', () {
      final e = entry(
        id: 'e3',
        status: HealthTimelineEntryStatus.cancelled,
        title: 'Consulta cancelada',
      );
      expect(e.isCancelled, isTrue);
      expect(e.status.wireName, 'cancelled');
    });

    test('amendments inválidos são rejeitados', () {
      expect(
        () => HealthTimelineAmendmentMetadata(amendmentCount: -1),
        throwsArgumentError,
      );
      expect(
        () => HealthTimelineAmendmentMetadata(
          hasAmendments: true,
          amendmentCount: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => HealthTimelineAmendmentMetadata(
          hasAmendments: false,
          amendmentCount: 2,
        ),
        throwsArgumentError,
      );
    });

    test('id/title/dogId vazios rejeitados', () {
      expect(() => entry(id: '  ', title: 'x'), throwsArgumentError);
      expect(() => entry(id: 'e', dogId: '', title: 'x'), throwsArgumentError);
      expect(() => entry(id: 'e', title: '  '), throwsArgumentError);
    });

    test('recordedBy e professional não colapsam', () {
      final e = entry(
        id: 'e4',
        recordedBy: sampleRecorder(),
        professional: sampleProfessional(),
      );
      expect(e.recordedBy!.name, isNot(e.professional!.name));
      expect(e.recordedBy!.uid, 'u1');
      expect(e.professional!.specialty, 'Clínica');
    });
  });

  group('HealthTimelineTypeView forward-compat', () {
    test('tipo conhecido', () {
      final t = HealthTimelineTypeView.known(HealthTimelineType.meal);
      expect(t.isKnown, isTrue);
      expect(t.raw, 'meal');
      expect(t.known, HealthTimelineType.meal);
    });

    test('tipo desconhecido preserva raw e não lança', () {
      final t = HealthTimelineTypeView.parse('future_procedure_v9');
      expect(t.isUnknown, isTrue);
      expect(t.raw, 'future_procedure_v9');
      expect(t.known, isNull);

      final e = entry(id: 'u1', typeRaw: 'future_procedure_v9', title: 'Novo');
      expect(e.type.isUnknown, isTrue);
      expect(e.type.raw, 'future_procedure_v9');
    });

    test('raw vazio lança', () {
      expect(() => HealthTimelineTypeView.parse(''), throwsArgumentError);
      expect(() => HealthTimelineTypeView.parse('   '), throwsArgumentError);
    });

    test('todos os tipos oficiais ADR-004 parseiam', () {
      for (final type in HealthTimelineType.values) {
        final parsed = HealthTimelineTypeView.parse(type.wireName);
        expect(parsed.known, type, reason: type.wireName);
      }
    });
  });

  group('HealthTimelineEntryStatus', () {
    test('wire names oficiais', () {
      expect(HealthTimelineEntryStatus.finalised.wireName, 'final');
      expect(HealthTimelineEntryStatus.cancelled.wireName, 'cancelled');
    });

    test('tryParse', () {
      expect(
        HealthTimelineEntryStatus.tryParse('final'),
        HealthTimelineEntryStatus.finalised,
      );
      expect(
        HealthTimelineEntryStatus.tryParse('cancelled'),
        HealthTimelineEntryStatus.cancelled,
      );
      expect(HealthTimelineEntryStatus.tryParse('draft'), isNull);
      expect(HealthTimelineEntryStatus.tryParse('unknown'), isNull);
    });
  });

  group('HealthTimelinePage invariants', () {
    test('hasMore false exige nextCursor null', () {
      expect(
        () => HealthTimelinePage(
          items: const [],
          nextCursor: const HealthTimelineCursor('x'),
          hasMore: false,
        ),
        throwsArgumentError,
      );
    });

    test('hasMore true exige nextCursor', () {
      expect(
        () => HealthTimelinePage(
          items: [entry(id: 'a')],
          nextCursor: null,
          hasMore: true,
        ),
        throwsArgumentError,
      );
    });

    test('página válida com hasMore', () {
      final p = pageOf([entry(id: 'a')], nextCursorToken: 'c1');
      expect(p.hasMore, isTrue);
      expect(p.nextCursor?.token, 'c1');
      expect(p.items, hasLength(1));
    });

    test('empty factory', () {
      final p = HealthTimelinePage.empty();
      expect(p.items, isEmpty);
      expect(p.hasMore, isFalse);
      expect(p.nextCursor, isNull);
    });
  });

  group('HealthTimelineQuery', () {
    test('igualdade de filter identity ignora cursor', () {
      final a = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.weight},
        cursor: const HealthTimelineCursor('c1'),
      );
      final b = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.weight},
        cursor: const HealthTimelineCursor('c2'),
      );
      expect(a.filterIdentity, b.filterIdentity);
      expect(a, isNot(b));
    });

    test('query equality inclui cursor', () {
      final a = HealthTimelineQuery(
        dogId: 'dog-a',
        cursor: const HealthTimelineCursor('c1'),
      );
      final b = HealthTimelineQuery(
        dogId: 'dog-a',
        cursor: const HealthTimelineCursor('c1'),
      );
      expect(a, b);
    });

    test('tipos em ordem diferente são iguais na identity', () {
      final a = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.meal, HealthTimelineType.weight},
      );
      final b = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.weight, HealthTimelineType.meal},
      );
      expect(a.filterIdentity, b.filterIdentity);
    });

    test('pageSize inválido', () {
      expect(
        () => HealthTimelineQuery(dogId: 'd', pageSize: 0),
        throwsArgumentError,
      );
      expect(
        () => HealthTimelineQuery(dogId: 'd', pageSize: -1),
        throwsArgumentError,
      );
      expect(
        () => HealthTimelineQuery(
          dogId: 'd',
          pageSize: HealthTimelineQuery.maxPageSize + 1,
        ),
        throwsArgumentError,
      );
    });

    test('pageSize default e max aceitos', () {
      final d = HealthTimelineQuery(dogId: 'd');
      expect(d.pageSize, HealthTimelineQuery.defaultPageSize);
      final m = HealthTimelineQuery(
        dogId: 'd',
        pageSize: HealthTimelineQuery.maxPageSize,
      );
      expect(m.pageSize, HealthTimelineQuery.maxPageSize);
    });

    test('dogId vazio rejeitado', () {
      expect(() => HealthTimelineQuery(dogId: ''), throwsArgumentError);
      expect(() => HealthTimelineQuery(dogId: '  '), throwsArgumentError);
    });

    test('withoutCursor limpa apenas cursor', () {
      final q = HealthTimelineQuery(
        dogId: 'dog-a',
        types: {HealthTimelineType.exam},
        cursor: const HealthTimelineCursor('c'),
      );
      final w = q.withoutCursor();
      expect(w.cursor, isNull);
      expect(w.types, {HealthTimelineType.exam});
      expect(w.filterIdentity, q.filterIdentity);
    });

    test('filtro profissional exige critério', () {
      expect(() => HealthTimelineProfessionalFilter(), throwsArgumentError);
      final f = HealthTimelineProfessionalFilter(name: 'Dra. Ana');
      expect(f.name, 'Dra. Ana');
    });

    test('identidades diferentes por dog/tipos/período/caso/profissional', () {
      final base = HealthTimelineQuery(dogId: 'dog-a');
      expect(
        base.filterIdentity,
        isNot(HealthTimelineQuery(dogId: 'dog-b').filterIdentity),
      );
      expect(
        base.filterIdentity,
        isNot(
          HealthTimelineQuery(
            dogId: 'dog-a',
            types: {HealthTimelineType.dose},
          ).filterIdentity,
        ),
      );
      expect(
        base.filterIdentity,
        isNot(
          HealthTimelineQuery(
            dogId: 'dog-a',
            period: HealthTimelinePeriod(start: DateTime(2026, 1, 1)),
          ).filterIdentity,
        ),
      );
      expect(
        base.filterIdentity,
        isNot(HealthTimelineQuery(dogId: 'dog-a', caseId: 'c1').filterIdentity),
      );
      expect(
        base.filterIdentity,
        isNot(
          HealthTimelineQuery(
            dogId: 'dog-a',
            professional: HealthTimelineProfessionalFilter(
              registrationNumber: '123',
            ),
          ).filterIdentity,
        ),
      );
    });
  });

  group('HealthTimelinePeriod', () {
    test('intervalo válido e unbounded', () {
      final p = HealthTimelinePeriod(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 12, 31),
      );
      expect(p.isUnbounded, isFalse);
      expect(HealthTimelinePeriod().isUnbounded, isTrue);
    });

    test('intervalo invertido rejeitado', () {
      expect(
        () => HealthTimelinePeriod(
          start: DateTime(2026, 12, 31),
          end: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('start == end é válido (inclusivo)', () {
      final day = DateTime(2026, 7, 10);
      final p = HealthTimelinePeriod(start: day, end: day);
      expect(p.start, day);
      expect(p.end, day);
    });
  });

  group('HealthTimelineCursor', () {
    test('opaco e comparável por token', () {
      const a = HealthTimelineCursor('tok-1');
      const b = HealthTimelineCursor('tok-1');
      const c = HealthTimelineCursor('tok-2');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toString(), contains('opaque'));
      expect(a.toString(), isNot(contains('tok-1')));
    });

    test('token vazio rejeitado', () {
      expect(() => HealthTimelineCursor(''), throwsA(anything));
    });
  });

  group('detail reference e traceability', () {
    test('detail reference equality', () {
      const a = HealthTimelineDetailReference(
        sourceType: 'exam',
        sourceId: 'ex-1',
        caseId: 'c1',
      );
      const b = HealthTimelineDetailReference(
        sourceType: 'exam',
        sourceId: 'ex-1',
        caseId: 'c1',
      );
      expect(a, b);
    });

    test('traceability flags', () {
      const t = HealthTimelineTraceability(
        sourceCollection: 'clinical_events',
        sourceId: 'ev-1',
      );
      expect(t.hasCanonicalSource, isTrue);
      expect(t.hasLegacySource, isFalse);

      const legacy = HealthTimelineTraceability(
        legacySource: 'health_events',
        legacyId: 'h1',
      );
      expect(legacy.hasLegacySource, isTrue);
    });
  });
}
