import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/schedule/firestore_health_schedule_global_source.dart';
import 'package:canil_gcm/features/health/data/coexistence/schedule/health_schedule_document_mapper.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_global_query.dart';
import 'package:canil_gcm/features/health/presentation/schedule/health_schedule_source.dart';

/// HW-4B — Global Agenda Reader (collection group bounded).
///
/// Invariantes protegidos aqui derivam de findings do HW-4A:
///   1. identidade global vem do campo `dog_id` do documento (não do path);
///   2. a shape aprovada `dog_id in [...] + lifecycle_status == + orderBy
///      scheduled_for` não pode ser alterada silenciosamente;
///   3. nenhuma query irrestrita, em nenhuma circunstância.
void main() {
  late FakeFirebaseFirestore db;

  const dogA = 'dog-a';
  const dogB = 'dog-b';

  setUp(() {
    db = FakeFirebaseFirestore();
  });

  Map<String, dynamic> payload({
    required String? dogId,
    String title = 'Vacina antirrábica',
    String lifecycle = 'open',
    String scheduleType = 'vaccination',
    DateTime? scheduledFor,
    Object? dogIdOverride,
    bool omitDogId = false,
    Map<String, dynamic> extra = const {},
  }) {
    final base = <String, dynamic>{
      'schedule_type': scheduleType,
      'title': title,
      'scheduled_for': Timestamp.fromDate(
        scheduledFor ?? DateTime.utc(2026, 8, 20, 12),
      ),
      'timezone': 'America/Sao_Paulo',
      'lifecycle_status': lifecycle,
      'source_type': 'manual',
      'created_at': Timestamp.fromDate(DateTime.utc(2026, 8, 1, 12)),
      'recorded_by': {
        'uid': 'uid-op',
        'name': 'Operador',
        'internal_role': 'condutor',
      },
      'schema_version': 1,
      ...extra,
    };
    if (omitDogId) return base;
    base['dog_id'] = dogIdOverride ?? dogId;
    return base;
  }

  Future<void> seed({
    required String structuralDogId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await db
        .collection('dogs')
        .doc(structuralDogId)
        .collection('health_schedule')
        .doc(documentId)
        .set(data);
  }

  FirestoreHealthScheduleGlobalSource source() =>
      FirestoreHealthScheduleGlobalSource(firestore: db);

  group('catálogo', () {
    test('catálogo vazio retorna vazio SEM emitir query', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const []),
      );

      expect(result.isEmpty, isTrue);
      expect(result.items, isEmpty);
      expect(result.truncated, isFalse);
      // Prova de que nenhuma leitura ocorreu: zero chunks consultados.
      expect(
        result.queriedChunks,
        0,
        reason: 'catálogo vazio não pode emitir query (nem irrestrita)',
      );
    });

    test('catálogo com 1 K9 lê somente o autorizado', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );
      await seed(
        structuralDogId: dogB,
        documentId: 'b1',
        data: payload(dogId: dogB),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      expect(result.items.map((e) => e.dogId), [dogA]);
      expect(result.queriedChunks, 1);
    });

    test('catálogo de 1 K9 usa whereIn (shape única), não isEqualTo', () async {
      // Prova comportamental do contrato: um único cão continua sendo lido
      // pela MESMA shape de um catálogo grande — `dog_id in ['dog-A']`.
      // O guard de shape cobre o lado estático; aqui provamos que a shape
      // única de fato serve o caso de 1 elemento.
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final query = HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]);
      expect(
        query.chunks,
        [
          [dogA],
        ],
        reason: 'catálogo de 1 produz um chunk de 1 — nunca um valor escalar',
      );

      final result = await source().loadGlobal(query);
      expect(result.items.single.dogId, dogA);
      expect(result.queriedChunks, 1);
    });

    test('catálogo multi-K9 alcança todos os autorizados', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );
      await seed(
        structuralDogId: dogB,
        documentId: 'b1',
        data: payload(dogId: dogB),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA, dogB]),
      );

      expect(result.items.map((e) => e.dogId).toSet(), {dogA, dogB});
    });

    test('duplicados no catálogo são removidos e não duplicam itens', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final query = HealthScheduleGlobalQuery(
        authorizedDogIds: const [dogA, dogA, ' dog-a '],
      );
      expect(query.authorizedDogIds, [dogA]);

      final result = await source().loadGlobal(query);
      expect(result.items, hasLength(1));
    });

    test('dogId vazio no catálogo é rejeitado na construção', () {
      expect(
        () => HealthScheduleGlobalQuery(authorizedDogIds: const [dogA, '']),
        throwsArgumentError,
      );
      expect(
        () => HealthScheduleGlobalQuery(authorizedDogIds: const ['   ']),
        throwsArgumentError,
      );
    });
  });

  group('chunking', () {
    test('catálogo maior que o chunk é dividido deterministicamente', () {
      final query = HealthScheduleGlobalQuery(
        authorizedDogIds: List.generate(12, (i) => 'dog-$i'),
        chunkSize: 5,
      );

      expect(query.chunks, hasLength(3));
      expect(query.chunks[0], ['dog-0', 'dog-1', 'dog-2', 'dog-3', 'dog-4']);
      expect(query.chunks[1], ['dog-5', 'dog-6', 'dog-7', 'dog-8', 'dog-9']);
      expect(query.chunks[2], ['dog-10', 'dog-11']);
      // Determinismo: mesma entrada, mesmos chunks.
      expect(
        query.chunks,
        HealthScheduleGlobalQuery(
          authorizedDogIds: List.generate(12, (i) => 'dog-$i'),
          chunkSize: 5,
        ).chunks,
      );
    });

    test('chunk default respeita o contrato medido (HW-4A.2D.1)', () {
      expect(HealthScheduleGlobalQuery.defaultChunkSize, 5);
      expect(HealthScheduleGlobalQuery.maxChunkSize, 30);
    });

    test('chunkSize acima do teto do operador `in` é rejeitado', () {
      expect(
        () => HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA],
          chunkSize: 31,
        ),
        throwsArgumentError,
      );
      expect(
        () => HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA],
          chunkSize: 0,
        ),
        throwsArgumentError,
      );
    });

    test('merge entre chunks cobre o catálogo inteiro', () async {
      for (var i = 0; i < 7; i++) {
        await seed(
          structuralDogId: 'dog-$i',
          documentId: 'doc-$i',
          data: payload(
            dogId: 'dog-$i',
            scheduledFor: DateTime.utc(2026, 8, 20 - i, 12),
          ),
        );
      }

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(
          authorizedDogIds: List.generate(7, (i) => 'dog-$i'),
          chunkSize: 3,
        ),
      );

      expect(result.queriedChunks, 3);
      expect(result.items, hasLength(7));
      expect(
        result.items.map((e) => e.dogId).toSet(),
        List.generate(7, (i) => 'dog-$i').toSet(),
      );
    });
  });

  group('ordenação global', () {
    test('ordena por scheduled_for entre chunks distintos', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a-late',
        data: payload(dogId: dogA, scheduledFor: DateTime.utc(2026, 8, 25, 12)),
      );
      await seed(
        structuralDogId: dogB,
        documentId: 'b-early',
        data: payload(dogId: dogB, scheduledFor: DateTime.utc(2026, 8, 18, 12)),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA, dogB],
          chunkSize: 1,
        ),
      );

      expect(result.queriedChunks, 2);
      expect(result.items.map((e) => e.id), ['b-early', 'a-late']);
    });

    test('empate de scheduled_for tem desempate local estável', () async {
      final tie = DateTime.utc(2026, 8, 20, 12);
      await seed(
        structuralDogId: dogB,
        documentId: 'z-doc',
        data: payload(dogId: dogB, scheduledFor: tie),
      );
      await seed(
        structuralDogId: dogA,
        documentId: 'a-doc',
        data: payload(dogId: dogA, scheduledFor: tie),
      );

      final query = HealthScheduleGlobalQuery(
        authorizedDogIds: const [dogB, dogA],
        chunkSize: 1,
      );

      final first = await source().loadGlobal(query);
      final second = await source().loadGlobal(query);

      // Desempate por (dogId, id): dog-a antes de dog-b.
      expect(first.items.map((e) => '${e.dogId}/${e.id}'), [
        'dog-a/a-doc',
        'dog-b/z-doc',
      ]);
      // Estabilidade: repetição produz exatamente a mesma ordem.
      expect(
        second.items.map((e) => '${e.dogId}/${e.id}'),
        first.items.map((e) => '${e.dogId}/${e.id}'),
      );
    });
  });

  group('identidade canônica (dog_id do documento)', () {
    test('documento válido usa o dog_id declarado como identidade', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      expect(result.items.single.dogId, dogA);
    });

    test('dog_id ausente falha fechado (não vira item válido)', () async {
      // Documento alcançável pelo path, mas sem identidade global canônica.
      await seed(
        structuralDogId: dogA,
        documentId: 'sem-dog-id',
        data: payload(dogId: null, omitDogId: true),
      );

      // A query bounded exige dog_id, então o doc não é retornado pela query.
      // Este teste protege o mapper: se algum dia o doc chegar, falha fechado.
      expect(
        () => _mapDirect(
          documentId: 'sem-dog-id',
          data: payload(dogId: null, omitDogId: true),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('aliases não substituem dog_id canônico', () async {
      for (final alias in ['dogId', 'caoId', 'k9_id']) {
        expect(
          () => _mapDirect(
            documentId: 'alias-$alias',
            data: payload(dogId: null, omitDogId: true, extra: {alias: dogB}),
          ),
          throwsA(isA<Exception>()),
          reason: '$alias não é identidade global válida',
        );
      }
    });

    test('dog_id vazio, null e numérico falham fechado', () async {
      expect(
        () => _mapDirect(
          documentId: 'vazio',
          data: payload(dogId: null, dogIdOverride: ''),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => _mapDirect(
          documentId: 'nulo',
          data: payload(dogId: null, omitDogId: true, extra: {'dog_id': null}),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => _mapDirect(
          documentId: 'numerico',
          data: payload(dogId: null, dogIdOverride: 12345),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('dog_id divergente do path: campo declarado é a autoridade', () async {
      // Documento fisicamente sob dogA, declarando dogB.
      // Contrato: identidade global = campo. Nunca corrigir dado no cliente.
      final item = _mapDirect(
        documentId: 'mismatch',
        data: payload(dogId: dogB),
      );
      expect(item, dogB);
    });
  });

  group('lifecycle persistido vs temporal derivado', () {
    test('consulta open não traz completed', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a-open',
        data: payload(dogId: dogA),
      );
      await seed(
        structuralDogId: dogA,
        documentId: 'a-done',
        data: payload(
          dogId: dogA,
          lifecycle: 'completed',
          extra: {
            'completed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 19, 12)),
            'completed_by': {
              'uid': 'uid-op',
              'name': 'Operador',
              'internal_role': 'condutor',
            },
          },
        ),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      expect(result.items.map((e) => e.id), ['a-open']);
      expect(result.items.single.lifecycleStatus, ScheduleLifecycleStatus.open);
    });

    test('consulta completed traz apenas terminais completed', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a-open',
        data: payload(dogId: dogA),
      );
      await seed(
        structuralDogId: dogA,
        documentId: 'a-done',
        data: payload(
          dogId: dogA,
          lifecycle: 'completed',
          extra: {
            'completed_at': Timestamp.fromDate(DateTime.utc(2026, 8, 19, 12)),
            'completed_by': {
              'uid': 'uid-op',
              'name': 'Operador',
              'internal_role': 'condutor',
            },
          },
        ),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA],
          lifecycleStatus: ScheduleLifecycleStatus.completed,
        ),
      );

      expect(result.items.map((e) => e.id), ['a-done']);
    });

    test('nenhum estado temporal é lido ou persistido pelo source', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA, extra: {'temporal_status': 'overdue'}),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      // O agregado não carrega estado temporal: a derivação é da policy.
      final item = result.items.single;
      expect(item.lifecycleStatus, ScheduleLifecycleStatus.open);
      expect(
        (item as Object).toString().contains('overdue'),
        isFalse,
        reason: 'source não deve materializar estado temporal',
      );
    });
  });

  group('limite explícito (foundation sem paginação)', () {
    test('maxItems corta e marca truncated', () async {
      for (var i = 0; i < 5; i++) {
        await seed(
          structuralDogId: dogA,
          documentId: 'doc-$i',
          data: payload(
            dogId: dogA,
            scheduledFor: DateTime.utc(2026, 8, 20, 12 + i),
          ),
        );
      }

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA], maxItems: 3),
      );

      expect(result.items, hasLength(3));
      expect(result.truncated, isTrue);
      // Corta mantendo os mais antigos primeiro (ordem global).
      expect(result.items.map((e) => e.id), ['doc-0', 'doc-1', 'doc-2']);
    });

    test('dentro do limite não marca truncated', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA], maxItems: 10),
      );

      expect(result.truncated, isFalse);
    });

    test('maxItems inválido é rejeitado', () {
      expect(
        () => HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA],
          maxItems: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('filtro de tipo local', () {
    test('filtra por schedule_type sem índice novo', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'vac',
        data: payload(dogId: dogA, scheduleType: 'vaccination'),
      );
      await seed(
        structuralDogId: dogA,
        documentId: 'pes',
        data: payload(dogId: dogA, scheduleType: 'weighing'),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(
          authorizedDogIds: const [dogA],
          types: const {ScheduleType.weighing},
        ),
      );

      expect(result.items.map((e) => e.id), ['pes']);
    });
  });

  group('fail-closed de erros', () {
    test('documento estruturalmente inválido não vira lista vazia', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'ruim',
        data: payload(dogId: dogA, extra: {'lifecycle_status': 'open'})
          ..['schedule_type'] = 'tipo_inexistente',
      );

      await expectLater(
        source().loadGlobal(
          HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
        ),
        throwsA(isA<HealthScheduleSourceException>()),
      );
    });

    test('scheduled_for inválido falha em vez de omitir compromisso', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'sem-data',
        data: payload(dogId: dogA)..remove('scheduled_for'),
      );

      await expectLater(
        source().loadGlobal(
          HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
        ),
        throwsA(isA<HealthScheduleSourceException>()),
      );
    });

    test('due_until null é válido e preservado', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      expect(result.items.single.dueUntil, isNull);
    });

    test('timezone é preservado do documento', () async {
      await seed(
        structuralDogId: dogA,
        documentId: 'a1',
        data: payload(dogId: dogA),
      );

      final result = await source().loadGlobal(
        HealthScheduleGlobalQuery(authorizedDogIds: const [dogA]),
      );

      expect(result.items.single.timezone, 'America/Sao_Paulo');
    });
  });
}

/// Extrai a identidade global pelo contrato de collection group, isolando o
/// comportamento de identidade do transporte Firestore.
String _mapDirect({
  required String documentId,
  required Map<String, dynamic> data,
}) {
  return HealthScheduleDocumentMapper.requireCollectionGroupDogId(
    documentId: documentId,
    data: data,
  );
}
