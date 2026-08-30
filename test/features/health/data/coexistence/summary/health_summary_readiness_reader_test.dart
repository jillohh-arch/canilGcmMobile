import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/health_summary_readiness_reader.dart';
import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_callable.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/presentation/summary/health_summary_block_models.dart';

/// READINESS-V1 Gate 6 — leitor de `health_summary/current`.
///
/// Cobre: primeiro snapshot, frescor, guarda de refresh, estados técnicos,
/// atenções e o contrato de payload do callable.
void main() {
  const dogId = 'dog-bono';
  final now = DateTime.utc(2026, 8, 11, 12);

  /// Registra cada invocação de callable para asserção de contrato.
  late List<({String name, Map<String, dynamic> payload})> calls;

  ReadinessRefreshGateway gateway({
    required bool ok,
    void Function()? onCall,
    FirebaseFirestore? seedInto,
    Map<String, Object?>? writeOnRefresh,
  }) {
    return ReadinessRefreshGateway(
      invoke: (name, payload) async {
        calls.add((name: name, payload: payload));
        onCall?.call();
        // Emula o backend projetando o documento.
        if (ok && seedInto != null && writeOnRefresh != null) {
          await seedInto
              .collection('dogs')
              .doc(dogId)
              .collection('health_summary')
              .doc('current')
              .set(writeOnRefresh);
        }
        return {'ok': ok};
      },
    );
  }

  Map<String, Object?> readyDoc({
    String status = 'operational',
    String label = 'Operacional',
    DateTime? updatedAt,
    List<Object?> alerts = const [],
    List<Object?> restrictions = const [],
    Map<String, Object?> count = const {
      'absolute': 0,
      'partial': 0,
      'attention': 0,
    },
    Map<String, Object?> overrides = const {},
  }) {
    final at = updatedAt ?? now;
    return {
      'projection_status': 'ready',
      'readiness_status': status,
      'readiness_label': label,
      'readiness_reason': 'Sem restrições ativas e dados de saúde em dia.',
      'readiness_reason_code': 'no_restrictions_evidence_complete',
      'readiness_updated_at': Timestamp.fromDate(at),
      'projection_attempted_at': Timestamp.fromDate(at),
      'updated_at': Timestamp.fromDate(at),
      'evaluated_by': 'function_v1',
      'data_completeness': {
        'has_recent_weight': true,
        'has_vaccination_current': true,
        'has_recent_consultation': true,
        'has_active_nutrition': true,
      },
      'active_restrictions': restrictions,
      'restriction_count': count,
      'open_alerts': alerts,
      'last_evaluated_at': Timestamp.fromDate(
        at.subtract(const Duration(days: 1)),
      ),
      'technical_blockers': <Object?>[],
      'schema_version': 1,
      ...overrides,
    };
  }

  Future<FakeFirebaseFirestore> seeded(Map<String, Object?>? doc) async {
    final db = FakeFirebaseFirestore();
    if (doc != null) {
      await db
          .collection('dogs')
          .doc(dogId)
          .collection('health_summary')
          .doc('current')
          .set(doc);
    }
    return db;
  }

  HealthSummaryReadinessReader reader(
    FirebaseFirestore db, {
    ReadinessRefreshGateway? refresh,
    DateTime? clock,
  }) {
    return HealthSummaryReadinessReader(
      firestore: db,
      refreshGateway: refresh ?? gateway(ok: false),
      now: () => clock ?? now,
    );
  }

  setUp(() => calls = []);

  group('BONO — fixture homologado', () {
    test('snapshot operational rende PRONTIDÃO Operacional e sem atenções', () async {
      final db = await seeded(readyDoc());
      final sections = await reader(db).read(dogId);

      expect(sections.readiness.isAvailable, isTrue);
      final view = sections.readiness.value!;
      expect(view.status, ReadinessStatus.operational);
      expect(view.reason, 'Sem restrições ativas e dados de saúde em dia.');

      // Atenções: vazio VERIFICADO é available, não unavailable.
      expect(sections.attention.isAvailable, isTrue);
      expect(sections.attention.value!.items, isEmpty);
      expect(sections.attention.isUnavailable, isFalse);

      // Nenhum callable: snapshot fresco.
      expect(calls, isEmpty);
    });
  });

  group('CLÍNICO — os cinco estados', () {
    test('cada estado usa rótulo e motivo do servidor', () async {
      final cases = <String, ReadinessStatus>{
        'operational': ReadinessStatus.operational,
        'operational_attention': ReadinessStatus.operationalAttention,
        'fit_with_restrictions': ReadinessStatus.fitWithRestrictions,
        'temporarily_unfit': ReadinessStatus.temporarilyUnfit,
        'not_evaluated': ReadinessStatus.notEvaluated,
      };

      for (final entry in cases.entries) {
        final db = await seeded(
          readyDoc(
            status: entry.key,
            label: 'RÓTULO SERVIDOR ${entry.key}',
            overrides: {'readiness_reason': 'MOTIVO SERVIDOR ${entry.key}'},
          ),
        );
        final sections = await reader(db).read(dogId);
        expect(sections.readiness.isAvailable, isTrue, reason: entry.key);
        expect(sections.readiness.value!.status, entry.value);
        // Motivo é propriedade do servidor — não reconstruído localmente.
        expect(
          sections.readiness.value!.reason,
          'MOTIVO SERVIDOR ${entry.key}',
        );
      }
    });

    test('not_evaluated é estado CLÍNICO disponível, nunca indisponível', () async {
      final db = await seeded(
        readyDoc(status: 'not_evaluated', label: 'Não Avaliado'),
      );
      final sections = await reader(db).read(dogId);

      // A distinção obrigatória do Gate 6.
      expect(sections.readiness.isAvailable, isTrue);
      expect(sections.readiness.isUnavailable, isFalse);
      expect(sections.readiness.value!.status, ReadinessStatus.notEvaluated);
    });
  });

  group('T — falhas técnicas nunca viram clínico', () {
    test('T1 snapshot ausente + refresh falho → indisponível', () async {
      final db = await seeded(null);
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.attention.isUnavailable, isTrue);
      // Tentou o refresh antes de desistir.
      expect(calls.single.name, ReadinessCallableNames.refresh);
    });

    test('T2 unavailable sem clínico anterior → indisponível', () async {
      final db = await seeded({
        'projection_status': 'unavailable',
        'projection_attempted_at': Timestamp.fromDate(now),
        'technical_blockers': ['weight_source_permission_denied'],
        'schema_version': 1,
      });
      final sections = await reader(db).read(dogId);

      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.attention.isUnavailable, isTrue);
      expect(sections.readiness.valueOrNull, isNull);
    });

    test(
      'T3 unavailable com last-known-good operational NÃO mostra Operacional',
      () async {
        final db = await seeded(
          readyDoc(overrides: {
            'projection_status': 'unavailable',
            'technical_blockers': ['weight_source_inconclusive'],
          }),
        );
        final sections = await reader(db).read(dogId);

        // O caso que motivou o Gate 6: stale operational não pode aparecer
        // como confirmação clínica atual.
        expect(sections.readiness.isUnavailable, isTrue);
        expect(sections.readiness.valueOrNull, isNull);
        expect(sections.attention.isUnavailable, isTrue);
      },
    );

    test('T4 ready com readiness_status desconhecido → indisponível', () async {
      final db = await seeded(readyDoc(status: 'indeterminate'));
      final sections = await reader(db).read(dogId);

      expect(sections.readiness.isUnavailable, isTrue);
      // Nunca degrada para operational.
      expect(sections.readiness.valueOrNull, isNull);
    });

    test('T5 completude malformada → indisponível', () async {
      final db = await seeded(
        readyDoc(overrides: {'data_completeness': {'has_recent_weight': true}}),
      );
      final sections = await reader(db).read(dogId);
      expect(sections.readiness.isUnavailable, isTrue);
    });

    test('T6 restrição malformada → indisponível', () async {
      final db = await seeded(
        readyDoc(
          restrictions: [
            {
              'id': 'r-1',
              'level': 'severe',
              'category': 'injury',
              'description': 'x',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
          ],
        ),
      );
      final sections = await reader(db).read(dogId);
      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.attention.isUnavailable, isTrue);
    });

    test('T7 alerta malformado → indisponível', () async {
      final db = await seeded(
        readyDoc(alerts: [
          {'code': 'x', 'severity': 'attention'},
        ]),
      );
      final sections = await reader(db).read(dogId);
      expect(sections.readiness.isUnavailable, isTrue);
    });

    test('T8 schema futuro → indisponível, não adivinha', () async {
      final db = await seeded(readyDoc(overrides: {'schema_version': 2}));
      final sections = await reader(db).read(dogId);
      expect(sections.readiness.isUnavailable, isTrue);
    });

    test('dogId vazio → indisponível sem I/O', () async {
      final db = await seeded(readyDoc());
      final sections = await reader(db).read('   ');
      expect(sections.readiness.isUnavailable, isTrue);
      expect(calls, isEmpty);
    });
  });

  group('FRESH — frescor por tempo de projeção', () {
    test('FRESH-01 idade < 5 min → nenhum callable', () async {
      final db = await seeded(
        readyDoc(updatedAt: now.subtract(const Duration(minutes: 4))),
      );
      await reader(db).read(dogId);
      expect(calls, isEmpty);
    });

    test('FRESH-02 exatamente 5 min ainda é fresco (fronteira congelada)', () async {
      final db = await seeded(
        readyDoc(updatedAt: now.subtract(const Duration(minutes: 5))),
      );
      await reader(db).read(dogId);
      expect(calls, isEmpty, reason: 'idade == janela é fresca');
    });

    test('FRESH-02b 5 min + 1 ms refresca', () async {
      final db = await seeded(
        readyDoc(
          updatedAt: now.subtract(
            const Duration(minutes: 5, milliseconds: 1),
          ),
        ),
      );
      await reader(db, refresh: gateway(ok: false)).read(dogId);
      expect(calls, hasLength(1));
    });

    test('FRESH-03 idade > 5 min → exatamente um refresh', () async {
      final db = await seeded(
        readyDoc(updatedAt: now.subtract(const Duration(minutes: 30))),
      );
      await reader(db, refresh: gateway(ok: false)).read(dogId);
      expect(calls, hasLength(1));
      expect(calls.single.name, ReadinessCallableNames.refresh);
    });

    test('FRESH-03b refresh bem-sucedido reflete o snapshot novo', () async {
      final db = await seeded(
        readyDoc(
          status: 'temporarily_unfit',
          label: 'Temporariamente Inapto',
          updatedAt: now.subtract(const Duration(hours: 2)),
        ),
      );
      // Backend reprojeta para operational com timestamp atual.
      final r = reader(
        db,
        refresh: gateway(
          ok: true,
          seedInto: db,
          writeOnRefresh: readyDoc(updatedAt: now),
        ),
      );
      final sections = await r.read(dogId);

      expect(calls, hasLength(1));
      expect(sections.readiness.value!.status, ReadinessStatus.operational);
    });

    test(
      'FRESH-06 refresh falho em snapshot velho não apresenta clínico como atual',
      () async {
        // Servidor marca indisponível ao falhar, preservando o clínico.
        final db = await seeded(
          readyDoc(updatedAt: now.subtract(const Duration(hours: 3))),
        );
        final r = reader(
          db,
          refresh: gateway(
            ok: true,
            seedInto: db,
            writeOnRefresh: readyDoc(
              updatedAt: now.subtract(const Duration(hours: 3)),
              overrides: {
                'projection_status': 'unavailable',
                'technical_blockers': ['weight_source_failed'],
              },
            ),
          ),
        );
        final sections = await r.read(dogId);

        expect(sections.readiness.isUnavailable, isTrue);
        expect(sections.attention.isUnavailable, isTrue);
      },
    );

    test('frescor ignora last_evaluated_at antigo', () async {
      // Projeção recente, tempo clínico de 40 dias atrás.
      final db = await seeded(
        readyDoc(
          updatedAt: now.subtract(const Duration(minutes: 1)),
          overrides: {
            'last_evaluated_at': Timestamp.fromDate(
              now.subtract(const Duration(days: 40)),
            ),
          },
        ),
      );
      await reader(db).read(dogId);
      // Se usasse tempo clínico, dispararia refresh indevidamente.
      expect(calls, isEmpty);
    });
  });

  group('LOOP — guarda de tempestade de refresh', () {
    test('FRESH-04 leituras concorrentes emitem um único callable', () async {
      final db = await seeded(null);
      final r = reader(db, refresh: gateway(ok: false));

      // Três rebuilds simultâneos sobre o mesmo cão.
      await Future.wait([r.read(dogId), r.read(dogId), r.read(dogId)]);

      expect(
        calls,
        hasLength(1),
        reason: 'refresh em voo deve ser compartilhado',
      );
    });

    test('cães distintos não compartilham a guarda', () async {
      final db = FakeFirebaseFirestore();
      final r = reader(db, refresh: gateway(ok: false));
      await Future.wait([r.read('dog-a'), r.read('dog-b')]);
      expect(calls, hasLength(2));
    });

    test('guarda é liberada após concluir', () async {
      final db = await seeded(null);
      final r = reader(db, refresh: gateway(ok: false));

      await r.read(dogId);
      expect(r.hasInFlightRefresh(dogId), isFalse);
      await r.read(dogId);
      // Duas leituras sequenciais legitimamente pedem duas projeções.
      expect(calls, hasLength(2));
    });

    test('FRESH-05 snapshot fresco não dispara refresh algum', () async {
      final db = await seeded(readyDoc());
      final r = reader(db, refresh: gateway(ok: false));
      await r.read(dogId);
      await r.read(dogId);
      await r.read(dogId);
      expect(calls, isEmpty);
    });
  });

  group('CALLABLE — contrato de payload', () {
    test('envia apenas dogId, sem nenhum campo clínico', () async {
      final db = await seeded(null);
      await reader(db, refresh: gateway(ok: false)).read(dogId);

      expect(calls, hasLength(1));
      final payload = calls.single.payload;

      // Forma exata congelada.
      expect(payload.keys.toList(), ['dogId']);
      expect(payload['dogId'], dogId);

      // Nenhum veredito clínico pode vazar do cliente.
      for (final forbidden in [
        'readinessStatus',
        'readiness_status',
        'readinessReason',
        'readinessLabel',
        'completeness',
        'data_completeness',
        'alerts',
        'open_alerts',
        'restrictions',
        'active_restrictions',
        'projectionStatus',
      ]) {
        expect(
          payload.containsKey(forbidden),
          isFalse,
          reason: 'Mobile não pode enviar $forbidden',
        );
      }
    });

    test('usa o nome e a região canônicos do callable', () async {
      final db = await seeded(null);
      await reader(db, refresh: gateway(ok: false)).read(dogId);
      expect(calls.single.name, 'healthReadinessRefresh');
      expect(ReadinessCallableNames.region, 'southamerica-east1');
    });
  });

  group('ATT — atenções derivadas só do snapshot', () {
    HealthSummaryAttentionView attentionOf(
      List<HealthSummaryAttentionItem> items,
    ) => HealthSummaryAttentionView(items: items);

    test('ATT-01 ready sem alertas nem restrições → available vazio', () async {
      final db = await seeded(readyDoc());
      final sections = await reader(db).read(dogId);
      expect(sections.attention.isAvailable, isTrue);
      expect(sections.attention.value!.items, isEmpty);
      expect(sections.attention.value!.count, 0);
    });

    test('ATT-02 alerta de nutrição ausente aparece', () async {
      final db = await seeded(
        readyDoc(
          status: 'operational_attention',
          label: 'Operacional com Atenção',
          alerts: [
            {
              'code': 'nutrition_plan_missing',
              'severity': 'attention',
              'message': 'Nenhum plano alimentar ativo.',
            },
          ],
        ),
      );
      final sections = await reader(db).read(dogId);
      final items = sections.attention.value!.items;
      expect(items, hasLength(1));
      expect(items.single.title, 'Nenhum plano alimentar ativo.');
      expect(items.single.id, 'alert:nutrition_plan_missing');
    });

    test('ATT-03 alerta de consulta vencida aparece', () async {
      final db = await seeded(
        readyDoc(
          status: 'operational_attention',
          label: 'Operacional com Atenção',
          alerts: [
            {
              'code': 'consultation_overdue',
              'severity': 'attention',
              'message': 'Consulta com mais de 180 dias.',
            },
          ],
        ),
      );
      final sections = await reader(db).read(dogId);
      expect(
        sections.attention.value!.items.single.title,
        'Consulta com mais de 180 dias.',
      );
    });

    test('ATT-04 restrição de atenção aparece', () async {
      final db = await seeded(
        readyDoc(
          status: 'operational_attention',
          label: 'Operacional com Atenção',
          restrictions: [
            {
              'id': 'r-att',
              'level': 'attention',
              'category': 'behavior',
              'description': 'Observação comportamental',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
          ],
          count: {'absolute': 0, 'partial': 0, 'attention': 1},
        ),
      );
      final sections = await reader(db).read(dogId);
      final item = sections.attention.value!.items.single;
      expect(item.id, 'restriction:r-att');
      expect(item.title, 'Observação comportamental');
    });

    test('ATT-05 restrição parcial precede alerta comum', () async {
      final db = await seeded(
        readyDoc(
          status: 'fit_with_restrictions',
          label: 'Apto com Restrições',
          restrictions: [
            {
              'id': 'r-par',
              'level': 'partial',
              'category': 'injury',
              'description': 'Restrição parcial',
              'activities_restricted': ['patrulha'],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
          ],
          count: {'absolute': 0, 'partial': 1, 'attention': 0},
          alerts: [
            {
              'code': 'weight_overdue',
              'severity': 'attention',
              'message': 'Pesagem vencida.',
            },
          ],
        ),
      );
      final sections = await reader(db).read(dogId);
      final items = sections.attention.value!.items;
      expect(items, hasLength(2));
      // Restrição primeiro.
      expect(items.first.id, 'restriction:r-par');
      expect(items.last.id, 'alert:weight_overdue');
      // Atividade restrita aparece no subtítulo.
      expect(items.first.subtitle, contains('patrulha'));
    });

    test('ATT-06 absoluta precede parcial e atenção', () async {
      final db = await seeded(
        readyDoc(
          status: 'temporarily_unfit',
          label: 'Temporariamente Inapto',
          restrictions: [
            // Ordem do servidor deliberadamente NÃO severa-primeiro.
            {
              'id': 'r-att',
              'level': 'attention',
              'category': 'other',
              'description': 'Atenção',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
            {
              'id': 'r-abs',
              'level': 'absolute',
              'category': 'injury',
              'description': 'Absoluta',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
            {
              'id': 'r-par',
              'level': 'partial',
              'category': 'injury',
              'description': 'Parcial',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
          ],
          count: {'absolute': 1, 'partial': 1, 'attention': 1},
        ),
      );
      final sections = await reader(db).read(dogId);
      final ids = sections.attention.value!.items
          .map((i) => i.id)
          .toList(growable: false);

      // A mais severa nunca é escondida.
      expect(ids, [
        'restriction:r-abs',
        'restriction:r-par',
        'restriction:r-att',
      ]);
    });

    test('ATT-08 projeção indisponível → atenções indisponíveis', () async {
      final db = await seeded({
        'projection_status': 'unavailable',
        'projection_attempted_at': Timestamp.fromDate(now),
        'technical_blockers': ['restrictions_source_malformed_status'],
        'schema_version': 1,
      });
      final sections = await reader(db).read(dogId);
      // Nunca "sem atenções" quando não foi possível determinar.
      expect(sections.attention.isUnavailable, isTrue);
      expect(sections.attention.valueOrNull, isNull);
    });

    test('restrição com prazo expirado marca subtítulo', () async {
      final db = await seeded(
        readyDoc(
          status: 'temporarily_unfit',
          label: 'Temporariamente Inapto',
          restrictions: [
            {
              'id': 'r-abs',
              'level': 'absolute',
              'category': 'injury',
              'description': 'Lesão',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(
                now.subtract(const Duration(days: 10)),
              ),
              'expected_end': Timestamp.fromDate(
                now.subtract(const Duration(days: 2)),
              ),
              'is_overdue': true,
            },
          ],
          count: {'absolute': 1, 'partial': 0, 'attention': 0},
        ),
      );
      final sections = await reader(db).read(dogId);
      expect(
        sections.attention.value!.items.single.subtitle,
        contains('Prazo expirado'),
      );
    });

    test('atenções e prontidão vêm do MESMO snapshot (nunca discordam)', () async {
      final db = await seeded(
        readyDoc(
          status: 'temporarily_unfit',
          label: 'Temporariamente Inapto',
          restrictions: [
            {
              'id': 'r-abs',
              'level': 'absolute',
              'category': 'injury',
              'description': 'Lesão grave',
              'activities_restricted': <Object?>[],
              'since': Timestamp.fromDate(now),
              'is_overdue': false,
            },
          ],
          count: {'absolute': 1, 'partial': 0, 'attention': 0},
        ),
      );
      final sections = await reader(db).read(dogId);

      // Ambas disponíveis e coerentes.
      expect(sections.readiness.value!.status, ReadinessStatus.temporarilyUnfit);
      expect(sections.attention.value!.items, hasLength(1));
      // A restrição também alimenta o resumo da prontidão.
      expect(
        sections.readiness.value!.restrictionSummaries,
        contains('Lesão grave'),
      );
      // Sanidade do helper local.
      expect(attentionOf(const []).count, 0);
    });
  });

  group('PRIMEIRA PROJEÇÃO — fluxo de primeiro uso', () {
    test(
      'documento ausente → callable → backend projeta → clínico renderiza',
      () async {
        final db = await seeded(null);
        final r = reader(
          db,
          refresh: gateway(
            ok: true,
            seedInto: db,
            writeOnRefresh: readyDoc(updatedAt: now),
          ),
        );

        final sections = await r.read(dogId);

        // Exatamente uma solicitação de projeção.
        expect(calls, hasLength(1));
        expect(calls.single.payload, {'dogId': dogId});
        // E o veredito do servidor foi renderizado.
        expect(sections.readiness.isAvailable, isTrue);
        expect(sections.readiness.value!.status, ReadinessStatus.operational);
        expect(sections.attention.isAvailable, isTrue);
      },
    );

    test('callable retorna ok:false → indisponível, sem cálculo local', () async {
      final db = await seeded(null);
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.readiness.valueOrNull, isNull);
    });

    test('callable ok mas documento continua ausente → indisponível', () async {
      final db = await seeded(null);
      // ok:true sem escrever nada (backend disse ok mas não projetou).
      final sections = await reader(
        db,
        refresh: ReadinessRefreshGateway(
          invoke: (name, payload) async {
            calls.add((name: name, payload: payload));
            return {'ok': true};
          },
        ),
      ).read(dogId);

      expect(sections.readiness.isUnavailable, isTrue);
      expect(calls, hasLength(1));
    });
  });

  // ==========================================================================
  // UR — RECUPERAÇÃO DE `unavailable`
  //
  // Um bloqueio técnico corrigido no servidor não pode congelar o app em
  // INDISPONÍVEL até que alguém grave um registro clínico. Snapshot
  // `unavailable` velho pede reprojeção; recém-gerado não martela a Function.
  //
  // Tempo de referência: `projection_attempted_at` (em `unavailable` não existe
  // `readiness_updated_at`). NUNCA `last_evaluated_at`, que é tempo clínico.
  // ==========================================================================
  group('UR — recuperação de snapshot unavailable', () {
    /// Snapshot `unavailable` com `projection_attempted_at` = [attemptedAt].
    ///
    /// `last_evaluated_at` fica deliberadamente ANTIGO em todos os casos: se a
    /// idade fosse medida por tempo clínico, UR-01/UR-02 refresacariam e
    /// falhariam.
    Map<String, Object?> unavailableDoc({
      required DateTime attemptedAt,
      List<Object?> blockers = const ['weight_source_inconclusive'],
    }) {
      return {
        'projection_status': 'unavailable',
        'projection_attempted_at': Timestamp.fromDate(attemptedAt),
        'updated_at': Timestamp.fromDate(attemptedAt),
        'last_evaluated_at': Timestamp.fromDate(
          attemptedAt.subtract(const Duration(days: 30)),
        ),
        'technical_blockers': blockers,
        'schema_version': 1,
      };
    }

    test('UR-01 unavailable com 4min59s → não refresh', () async {
      final db = await seeded(
        unavailableDoc(
          attemptedAt: now.subtract(const Duration(minutes: 4, seconds: 59)),
        ),
      );
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      expect(calls, isEmpty);
      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.attention.isUnavailable, isTrue);
    });

    test('UR-02 unavailable com exatamente 5min → não refresh', () async {
      final db = await seeded(
        unavailableDoc(attemptedAt: now.subtract(const Duration(minutes: 5))),
      );
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      // Fronteira congelada: `<=` janela é fresco.
      expect(calls, isEmpty);
      expect(sections.readiness.isUnavailable, isTrue);
    });

    test('UR-03 unavailable com 5min + 1ms → exatamente 1 refresh', () async {
      final db = await seeded(
        unavailableDoc(
          attemptedAt: now.subtract(
            const Duration(minutes: 5, milliseconds: 1),
          ),
        ),
      );
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      expect(calls, hasLength(1));
      expect(calls.single.name, ReadinessCallableNames.refresh);
      expect(calls.single.payload, {'dogId': dogId});
      // Callable falhou: segue indisponível, sem cálculo local.
      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.readiness.valueOrNull, isNull);
    });

    test('UR-04 unavailable velho → callable ok → re-read READY', () async {
      final db = await seeded(
        unavailableDoc(attemptedAt: now.subtract(const Duration(hours: 6))),
      );
      final sections = await reader(
        db,
        refresh: gateway(
          ok: true,
          seedInto: db,
          writeOnRefresh: readyDoc(updatedAt: now),
        ),
      ).read(dogId);

      expect(calls, hasLength(1));
      expect(sections.readiness.isAvailable, isTrue);
      expect(sections.readiness.value!.status, ReadinessStatus.operational);
      expect(sections.attention.isAvailable, isTrue);
    });

    test(
      'UR-05 unavailable velho → callable ok → segue unavailable → sem 2ª chamada',
      () async {
        final db = await seeded(
          unavailableDoc(attemptedAt: now.subtract(const Duration(hours: 6))),
        );
        // Backend tentou de novo e falhou de novo: novo attempted_at, mesmo
        // status técnico.
        final sections = await reader(
          db,
          refresh: gateway(
            ok: true,
            seedInto: db,
            writeOnRefresh: unavailableDoc(attemptedAt: now),
          ),
        ).read(dogId);

        // Uma tentativa por leitura: nada de read→refresh→read→refresh.
        expect(calls, hasLength(1));
        expect(sections.readiness.isUnavailable, isTrue);
        expect(sections.readiness.valueOrNull, isNull);
      },
    );

    test('UR-06 unavailable velho → callable falha → indisponível', () async {
      final db = await seeded(
        unavailableDoc(attemptedAt: now.subtract(const Duration(days: 2))),
      );
      final sections = await reader(
        db,
        refresh: gateway(ok: false),
      ).read(dogId);

      expect(calls, hasLength(1));
      expect(sections.readiness.isUnavailable, isTrue);
      expect(sections.attention.isUnavailable, isTrue);
    });

    test('UR-07 3 leituras concorrentes do mesmo velho → 1 callable', () async {
      final db = await seeded(
        unavailableDoc(attemptedAt: now.subtract(const Duration(hours: 6))),
      );
      final r = reader(db, refresh: gateway(ok: false));

      await Future.wait([r.read(dogId), r.read(dogId), r.read(dogId)]);

      expect(calls, hasLength(1));
      expect(r.hasInFlightRefresh(dogId), isFalse);
    });

    test(
      'UR-08 not_evaluated READY fresco segue clínico, não técnico',
      () async {
        final db = await seeded(
          readyDoc(
            status: 'not_evaluated',
            label: 'Não avaliado',
            updatedAt: now,
          ),
        );
        final sections = await reader(
          db,
          refresh: gateway(ok: false),
        ).read(dogId);

        // "Nunca foi avaliado" é estado CLÍNICO disponível, não
        // indisponibilidade.
        expect(sections.readiness.isAvailable, isTrue);
        expect(sections.readiness.value!.status, ReadinessStatus.notEvaluated);
        expect(sections.readiness.isUnavailable, isFalse);
        expect(calls, isEmpty);
      },
    );

    test(
      'UR-09 cenário Bono: blocker legacy antigo → refresh → Prontidão real',
      () async {
        // Estado exato deixado em produção antes da correção do adapter legacy
        // de Weight no backend.
        final db = await seeded(
          unavailableDoc(
            attemptedAt: now.subtract(const Duration(hours: 14)),
            blockers: const ['weight_source_inconclusive'],
          ),
        );
        final r = reader(
          db,
          refresh: gateway(
            ok: true,
            seedInto: db,
            // Backend já corrigido: agora reconhece o peso legacy e projeta.
            writeOnRefresh: readyDoc(updatedAt: now),
          ),
        );

        final sections = await r.read(dogId);

        expect(calls, hasLength(1));
        expect(calls.single.name, ReadinessCallableNames.refresh);
        expect(sections.readiness.isAvailable, isTrue);
        expect(sections.readiness.value!.status, ReadinessStatus.operational);
        expect(
          sections.readiness.value!.reason,
          'Sem restrições ativas e dados de saúde em dia.',
        );
        expect(sections.attention.isAvailable, isTrue);
      },
    );
  });
}
