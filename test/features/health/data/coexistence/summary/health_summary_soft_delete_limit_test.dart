import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_recent_records_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_soft_delete.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_vaccination_reader.dart';
import 'package:canil_gcm/features/health/presentation/screens/health_v1_entry_flags.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_user_copy.dart';

void main() {
  group('HealthSummarySoftDelete', () {
    test('isSoftDeleted: null/ausente = ativo; valor presente = deletado', () {
      expect(HealthSummarySoftDelete.isSoftDeleted({}), isFalse);
      expect(
        HealthSummarySoftDelete.isSoftDeleted({'deleted_at': null}),
        isFalse,
      );
      expect(
        HealthSummarySoftDelete.isSoftDeleted({
          'deleted_at': DateTime(2026, 1, 1),
        }),
        isTrue,
      );
      expect(
        HealthSummarySoftDelete.isSoftDeleted({'deleted_at': '2026-01-01'}),
        isTrue,
      );
    });

    test(
      'janela unica so com soft-deleted perde ativos fora da janela (bug classico)',
      () {
        final window = List.generate(
          20,
          (i) => <String, dynamic>{
            'deleted_at': DateTime(2026, 7, 15 - i),
            'date': DateTime(2026, 7, 15 - i).toIso8601String(),
            'type': 'consultation',
          },
        );
        final fromWindowOnly =
            HealthSummarySoftDelete.collectActiveFromSingleWindow(
              window: window,
              tryMap: (data) {
                if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
                return data['type'] as String;
              },
            );
        expect(fromWindowOnly, isEmpty);
      },
    );

    test('paginacao encontra ativos apos pagina dominada por soft-deletes', () {
      final deletedPage = List.generate(
        20,
        (i) => <String, dynamic>{
          'deleted_at': DateTime(2026, 7, 15),
          'date': '2026-07-${15 - i}',
          'type': 'consultation',
          'id': 'del-$i',
        },
      );
      final activePage = [
        <String, dynamic>{
          'deleted_at': null,
          'date': '2026-06-01T10:00:00.000',
          'type': 'consultation',
          'id': 'active-1',
        },
        <String, dynamic>{
          'date': '2026-05-01T10:00:00.000',
          'type': 'exam',
          'id': 'active-2',
        },
      ];

      final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
        pages: [deletedPage, activePage],
        targetActive: 8,
        pageSize: 20,
        maxPages: 6,
        tryMap: (data, page, doc) {
          if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
          final id = data['id'] as String?;
          if (id == null) return null;
          return id;
        },
      );

      expect(result.truncated, isFalse);
      expect(result.exhausted, isTrue); // última página com 2 < pageSize 20
      expect(result.items, ['active-1', 'active-2']);
    });

    test('para ao atingir targetActive sem truncar', () {
      final page = List.generate(
        10,
        (i) => <String, dynamic>{'deleted_at': null, 'id': 'a-$i'},
      );
      final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
        pages: [page],
        targetActive: 3,
        pageSize: 50,
        maxPages: 6,
        tryMap: (data, _, __) {
          if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
          return data['id'] as String;
        },
      );
      expect(result.truncated, isFalse);
      expect(result.items, ['a-0', 'a-1', 'a-2']);
    });
  });

  group('OBRIGATORIO — truncated vs exhausted', () {
    List<Map<String, dynamic>> deletedPage(int size, {String type = 'exam'}) {
      return List.generate(
        size,
        (i) => <String, dynamic>{
          'deleted_at': '2026-07-01',
          'date': '2026-07-01T${i.toString().padLeft(2, '0')}:00:00.000',
          'type': type,
          'id': 'del-$i',
        },
      );
    }

    test(
      'cenario 301: 6 paginas cheias so soft-deleted → truncated, NAO vazio conclusivo',
      () {
        const pageSize = 50;
        const maxPages = 6;
        // 6 × 50 = 300 soft-deleted; “ativo 301” não entra nas páginas.
        final pages = List.generate(maxPages, (_) => deletedPage(pageSize));

        final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
          pages: pages,
          targetActive: 20,
          pageSize: pageSize,
          maxPages: maxPages,
          tryMap: (data, p, i) {
            if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
            return data['id'] as String?;
          },
        );

        expect(result.items, isEmpty);
        expect(result.truncated, isTrue);
        expect(result.exhausted, isFalse);
        expect(result.isConclusiveEmpty, isFalse);
        expect(result.pagesScanned, maxPages);
      },
    );

    test(
      'fim real da colecao: ultima pagina curta + zero ativos → conclusive empty',
      () {
        const pageSize = 50;
        final pages = [
          deletedPage(pageSize),
          deletedPage(pageSize),
          deletedPage(12), // fim real
        ];

        final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
          pages: pages,
          targetActive: 20,
          pageSize: pageSize,
          maxPages: 6,
          tryMap: (data, p, i) {
            if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
            return data['id'] as String?;
          },
        );

        expect(result.items, isEmpty);
        expect(result.truncated, isFalse);
        expect(result.exhausted, isTrue);
        expect(result.isConclusiveEmpty, isTrue);
      },
    );

    test('targetActive atingido antes de maxPages → sucesso normal', () {
      const pageSize = 50;
      final pages = [
        deletedPage(pageSize),
        [
          ...deletedPage(40),
          ...List.generate(
            10,
            (i) => <String, dynamic>{
              'date': '2026-01-0${i + 1}T00:00:00.000',
              'type': 'exam',
              'id': 'active-$i',
            },
          ),
        ],
      ];

      final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
        pages: pages,
        targetActive: 5,
        pageSize: pageSize,
        maxPages: 6,
        tryMap: (data, p, i) {
          if (HealthSummarySoftDelete.isSoftDeleted(data)) return null;
          return data['id'] as String?;
        },
      );

      expect(result.truncated, isFalse);
      expect(result.items.length, 5);
      expect(result.items.first, 'active-0');
    });
  });

  group('Recent health_events map + soft-delete', () {
    test('mapHealthEventDoc ignora soft-deleted e data invalida', () {
      expect(
        HealthSummaryRecentRecordsReader.mapHealthEventDoc('1', {
          'deleted_at': DateTime.now(),
          'date': '2026-07-01',
          'type': 'exam',
        }),
        isNull,
      );
      expect(
        HealthSummaryRecentRecordsReader.mapHealthEventDoc('2', {
          'date': 'not-a-date',
          'type': 'exam',
        }),
        isNull,
      );
      final ok = HealthSummaryRecentRecordsReader.mapHealthEventDoc('3', {
        'date': '2026-07-01T12:00:00.000',
        'type': 'vaccination',
        'subtype': 'V10',
      });
      expect(ok, isNotNull);
      expect(ok!.id, 'he-3');
      expect(ok.title, contains('Vacina'));
    });

    test(
      'muitos soft-deleted + ativos em pagina seguinte → recupera (nao truncated)',
      () {
        final recentDeleted = List.generate(40, (i) {
          final day = 15 - (i % 14);
          return <String, dynamic>{
            'deleted_at': '2026-07-10',
            'date': '2026-07-${day.toString().padLeft(2, '0')}T12:00:00.000',
            'type': 'consultation',
          };
        });
        final olderActive = <String, dynamic>{
          'date': '2026-01-05T08:00:00.000',
          'type': 'exam',
          'subtype': 'Hemograma',
        };

        final result = HealthSummarySoftDelete.collectActiveFromPagesResult(
          pages: [
            recentDeleted,
            [olderActive],
          ],
          targetActive:
              HealthSummaryRecentRecordsReader.healthEventsActiveTarget,
          pageSize: 40,
          maxPages: 6,
          tryMap: (data, page, idx) {
            return HealthSummaryRecentRecordsReader.mapHealthEventDoc(
              'p$page-$idx',
              data,
            );
          },
        );

        expect(result.truncated, isFalse);
        expect(result.items, isNotEmpty);
        expect(result.items.first.title, contains('Exame'));
      },
    );

    test(
      'OBRIGATORIO recentes: health_events truncated → unavailable (nao partial)',
      () async {
        final reader = HealthSummaryRecentRecordsReader(
          loadItems: (_) async {
            // Simula o que _healthEvents faria ao detectar truncamento.
            throw HealthSummaryScanTruncatedException(
              scope: 'health_events/recent',
              pageSize: 50,
              maxPages: 6,
              targetActive: 20,
              pagesScanned: 6,
              itemsFound: 0,
            );
          },
        );

        final section = await reader.read('dog-1');
        expect(section.isUnavailable, isTrue);
        expect(section.isNotRecorded, isFalse);
        expect(section.message, HealthSummaryUserCopy.recentUnavailable);
        expect(section.valueOrNull, isNull);
      },
    );
  });

  group('Vacinacao health_events soft-delete + limit', () {
    test('ativos apos soft-deleted em multi-pagina → items sem truncated', () {
      final deletedWindow = List.generate(
        80,
        (i) => <String, dynamic>{
          'deleted_at': DateTime(2026, 7, 1),
          'date': '2026-07-01T00:00:00.000',
          'type': 'vaccination',
          'subtype': 'OLD-DEL-$i',
        },
      );
      final activeOlder = <String, dynamic>{
        'date': '2025-06-01T00:00:00.000',
        'type': 'vaccination',
        'subtype': 'V10-ATIVA',
        'nextDueDate': '2026-06-01T00:00:00.000',
      };

      final naive = HealthSummaryVaccinationReader.mapHealthEventDocsForTest(
        deletedWindow,
        pageSize: 80,
        maxPages: 1,
      );
      expect(naive.items, isEmpty);
      // 1 página cheia size=80 com pageSize 80 maxPages 1 → truncated
      expect(naive.truncated, isTrue);

      // Duas páginas cheias de soft-deleted + página final curta com ativa.
      final recovered =
          HealthSummaryVaccinationReader.collectVaccinationFromPagesForTest(
            [
              deletedWindow.sublist(0, 50),
              [
                ...deletedWindow.sublist(50),
                ...List.generate(
                  20,
                  (i) => <String, dynamic>{
                    'deleted_at': DateTime(2026, 7, 1),
                    'date': '2026-06-01T00:00:00.000',
                    'type': 'vaccination',
                    'subtype': 'PAD-$i',
                  },
                ),
              ],
              [activeOlder],
            ],
            pageSize: 50,
            maxPages: 6,
          );

      expect(recovered.truncated, isFalse);
      expect(recovered.items, isNotEmpty);
      expect(recovered.items.first.name, 'V10-ATIVA');
    });

    test('nao inventa summaryLabel / nao usa dataVencimento', () async {
      final reader = HealthSummaryVaccinationReader(
        loadFacts: (_) async => [
          HealthSummaryVaccinationFact(
            occurredAt: DateTime(2026, 1, 1),
            name: 'V8',
            nextDueAt: null,
          ),
        ],
      );
      final section = await reader.read('dog-1');
      expect(section.isAvailable, isTrue);
      expect(section.value!.summaryLabel, isNull);
      expect(section.value!.lastRecordLabel, 'V8');
      expect(section.value!.nextDueAt, isNull);
    });

    test(
      'OBRIGATORIO: principal conclusivamente vazia → loadFacts vazio permite notRecorded/fallback path',
      () async {
        // loadFacts vazio = principal conclusiva vazia + vacinas vazias.
        final reader = HealthSummaryVaccinationReader(
          loadFacts: (_) async => [],
        );
        final section = await reader.read('dog-1');
        expect(section.isNotRecorded, isTrue);
        expect(section.isUnavailable, isFalse);
      },
    );

    test(
      'OBRIGATORIO: principal truncated → unavailable e NAO notRecorded',
      () async {
        final reader = HealthSummaryVaccinationReader(
          loadFacts: (_) async {
            throw HealthSummaryScanTruncatedException(
              scope: 'health_events/vaccination',
              pageSize: 50,
              maxPages: 6,
              targetActive: 5,
              pagesScanned: 6,
              itemsFound: 0,
            );
          },
        );
        final section = await reader.read('dog-1');
        expect(section.isUnavailable, isTrue);
        expect(section.isNotRecorded, isFalse);
        expect(section.message, HealthSummaryUserCopy.vaccinationUnavailable);
      },
    );

    test(
      'OBRIGATORIO: 6 paginas cheias so vacinas soft-deleted → truncated (sem fallback semantico)',
      () {
        const pageSize = 50;
        const maxPages = 6;
        final pages = List.generate(
          maxPages,
          (p) => List.generate(
            pageSize,
            (i) => <String, dynamic>{
              'deleted_at': 'x',
              'date': '2026-07-01T00:00:00.000',
              'type': 'vaccination',
              'subtype': 'DEL-$p-$i',
            },
          ),
        );

        final result =
            HealthSummaryVaccinationReader.collectVaccinationFromPagesForTest(
              pages,
              pageSize: pageSize,
              maxPages: maxPages,
            );

        expect(result.truncated, isTrue);
        expect(result.isConclusiveEmpty, isFalse);
        expect(result.items, isEmpty);
        // Caller de producao: if (scan.truncated) throw — sem _fromVacinasRoot.
      },
    );
  });

  group('Feature gate / rollback', () {
    test('producao: gate true; override false seleciona legado', () {
      expect(kHealthV1SummaryEntryEnabled, isTrue);
      expect(shouldUseHealthV1SummaryEntry(), isTrue);
      expect(shouldUseHealthV1SummaryEntry(overrideGate: true), isTrue);
      expect(shouldUseHealthV1SummaryEntry(overrideGate: false), isFalse);
    });
  });
}
