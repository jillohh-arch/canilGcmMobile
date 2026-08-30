import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:canil_gcm/features/health/data/coexistence/summary/readiness_snapshot_parser.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/readiness_snapshot.dart';

/// READINESS-V1 Gate 6 — parser estrito de `health_summary/current`.
///
/// Invariantes sob teste:
/// - enum clínico desconhecido nunca vira `operational`;
/// - `projection_status == unavailable` é indisponibilidade técnica, mesmo com
///   campos clínicos preservados;
/// - `not_evaluated` é estado CLÍNICO, distinto de indisponível.
void main() {
  final now = DateTime.utc(2026, 8, 11, 12);
  Timestamp ts(DateTime d) => Timestamp.fromDate(d);

  Map<String, Object?> readyDoc({
    String status = 'operational',
    String label = 'Operacional',
    Map<String, Object?> overrides = const {},
  }) {
    return {
      'projection_status': 'ready',
      'readiness_status': status,
      'readiness_label': label,
      'readiness_reason': 'Sem restrições ativas e dados de saúde em dia.',
      'readiness_reason_code': 'no_restrictions_evidence_complete',
      'readiness_updated_at': ts(now),
      'projection_attempted_at': ts(now),
      'updated_at': ts(now),
      'evaluated_by': 'function_v1',
      'data_completeness': {
        'has_recent_weight': true,
        'has_vaccination_current': true,
        'has_recent_consultation': true,
        'has_active_nutrition': true,
      },
      'active_restrictions': <Object?>[],
      'restriction_count': {'absolute': 0, 'partial': 0, 'attention': 0},
      'open_alerts': <Object?>[],
      'last_evaluated_at': ts(now.subtract(const Duration(days: 1))),
      'technical_blockers': <Object?>[],
      'schema_version': 1,
      ...overrides,
    };
  }

  ReadinessSnapshot expectSuccess(Map<String, Object?>? doc) {
    final result = ReadinessSnapshotParser.parse(doc);
    expect(
      result,
      isA<ReadinessParseSuccess>(),
      reason: 'esperava snapshot válido, veio $result',
    );
    return (result as ReadinessParseSuccess).snapshot;
  }

  ReadinessParseIncompatible expectIncompatible(Map<String, Object?>? doc) {
    final result = ReadinessSnapshotParser.parse(doc);
    expect(
      result,
      isA<ReadinessParseIncompatible>(),
      reason: 'esperava incompatível, veio $result',
    );
    return result as ReadinessParseIncompatible;
  }

  group('PAR — estados clínicos válidos', () {
    test('PAR-01 operational', () {
      final snap = expectSuccess(readyDoc());
      expect(snap.isReady, isTrue);
      expect(snap.verdict!.status, ReadinessStatus.operational);
      expect(snap.verdict!.label, 'Operacional');
      expect(snap.verdict!.openAlerts, isEmpty);
      expect(snap.verdict!.activeRestrictions, isEmpty);
      expect(snap.technicalBlockers, isEmpty);
    });

    test('PAR-02 operational_attention', () {
      final snap = expectSuccess(
        readyDoc(
          status: 'operational_attention',
          label: 'Operacional com Atenção',
          overrides: {
            'readiness_reason_code': 'significant_incomplete_data',
            'open_alerts': [
              {
                'code': 'consultation_overdue',
                'severity': 'attention',
                'message': 'Consulta vencida.',
              },
            ],
          },
        ),
      );
      expect(snap.verdict!.status, ReadinessStatus.operationalAttention);
      expect(snap.verdict!.label, 'Operacional com Atenção');
      expect(snap.verdict!.openAlerts.single.code, 'consultation_overdue');
    });

    test('PAR-03 fit_with_restrictions', () {
      final snap = expectSuccess(
        readyDoc(
          status: 'fit_with_restrictions',
          label: 'Apto com Restrições',
          overrides: {
            'readiness_reason_code': 'restriction_partial_active',
            'active_restrictions': [
              {
                'id': 'r-1',
                'level': 'partial',
                'category': 'injury',
                'description': 'Lesão leve',
                'activities_restricted': ['patrulha'],
                'since': ts(now.subtract(const Duration(days: 3))),
                'expected_end': null,
                'is_overdue': false,
              },
            ],
            'restriction_count': {
              'absolute': 0,
              'partial': 1,
              'attention': 0,
            },
          },
        ),
      );
      expect(snap.verdict!.status, ReadinessStatus.fitWithRestrictions);
      final r = snap.verdict!.activeRestrictions.single;
      expect(r.level, ReadinessRestrictionLevel.partial);
      expect(r.activitiesRestricted, ['patrulha']);
      expect(r.isOverdue, isFalse);
      expect(snap.verdict!.restrictionCount.partial, 1);
    });

    test('PAR-04 temporarily_unfit', () {
      final snap = expectSuccess(
        readyDoc(
          status: 'temporarily_unfit',
          label: 'Temporariamente Inapto',
          overrides: {
            'readiness_reason_code': 'restriction_absolute_active',
            'active_restrictions': [
              {
                'id': 'r-abs',
                'level': 'absolute',
                'category': 'injury',
                'description': 'Lesão grave',
                'activities_restricted': <Object?>[],
                'since': ts(now.subtract(const Duration(days: 5))),
                'expected_end': ts(now.subtract(const Duration(days: 1))),
                'is_overdue': true,
              },
            ],
            'restriction_count': {
              'absolute': 1,
              'partial': 0,
              'attention': 0,
            },
          },
        ),
      );
      expect(snap.verdict!.status, ReadinessStatus.temporarilyUnfit);
      final r = snap.verdict!.activeRestrictions.single;
      expect(r.level, ReadinessRestrictionLevel.absolute);
      // expected_end no passado NÃO remove a restrição.
      expect(r.isOverdue, isTrue);
      expect(r.expectedEnd, isNotNull);
    });

    test('PAR-05 not_evaluated é estado CLÍNICO, não indisponível', () {
      final snap = expectSuccess(
        readyDoc(
          status: 'not_evaluated',
          label: 'Não Avaliado',
          overrides: {
            'readiness_reason_code': 'no_factual_health_evaluation',
            'readiness_reason':
                'Nenhuma avaliação de saúde registrada para este K9.',
            'last_evaluated_at': null,
            'data_completeness': {
              'has_recent_weight': false,
              'has_vaccination_current': false,
              'has_recent_consultation': false,
              'has_active_nutrition': false,
            },
          },
        ),
      );
      // A distinção obrigatória: projeção READY com veredito notEvaluated.
      expect(snap.isReady, isTrue);
      expect(snap.isUnavailable, isFalse);
      expect(snap.verdict!.status, ReadinessStatus.notEvaluated);
      expect(snap.verdict!.label, 'Não Avaliado');
      expect(snap.verdict!.lastEvaluatedAt, isNull);
    });
  });

  group('PAR — contratos rejeitados', () {
    test('PAR-06 enum clínico desconhecido NUNCA vira operational', () {
      for (final unknown in [
        'indeterminate',
        'error',
        'partial',
        'unavailable',
        'OPERATIONAL',
        'operacional',
        'future_state_v2',
      ]) {
        final result = expectIncompatible(readyDoc(status: unknown));
        expect(
          result.failure,
          ReadinessParseFailure.unknownClinicalStatus,
          reason: '$unknown deve ser incompatível',
        );
      }
    });

    test('PAR-07 projection_status desconhecido é incompatível', () {
      for (final unknown in ['stale', 'loading', 'READY', '']) {
        final result = expectIncompatible(
          readyDoc(overrides: {'projection_status': unknown}),
        );
        expect(
          result.failure,
          ReadinessParseFailure.unknownProjectionStatus,
        );
      }
    });

    test('PAR-08 schema não suportado é incompatível', () {
      expect(
        expectIncompatible(readyDoc(overrides: {'schema_version': 2})).failure,
        ReadinessParseFailure.unsupportedSchema,
      );
      expect(
        expectIncompatible(readyDoc(overrides: {'schema_version': 0})).failure,
        ReadinessParseFailure.unsupportedSchema,
      );
      expect(
        expectIncompatible(
          readyDoc(overrides: {'schema_version': '1'}),
        ).failure,
        ReadinessParseFailure.unsupportedSchema,
      );
    });

    test('PAR-09 timestamp obrigatório ausente é incompatível', () {
      expect(
        expectIncompatible(
          readyDoc(overrides: {'readiness_updated_at': null}),
        ).failure,
        ReadinessParseFailure.malformedClinicalField,
      );
      expect(
        expectIncompatible(
          readyDoc(overrides: {'projection_attempted_at': 'nao-e-data'}),
        ).failure,
        ReadinessParseFailure.malformedClinicalField,
      );
    });

    test('PAR-09b string clínica obrigatória ausente é incompatível', () {
      for (final field in [
        'readiness_label',
        'readiness_reason',
        'readiness_reason_code',
      ]) {
        expect(
          expectIncompatible(readyDoc(overrides: {field: null})).failure,
          ReadinessParseFailure.malformedClinicalField,
          reason: '$field ausente deve rejeitar',
        );
        expect(
          expectIncompatible(readyDoc(overrides: {field: '   '})).failure,
          ReadinessParseFailure.malformedClinicalField,
          reason: '$field vazio deve rejeitar',
        );
      }
    });

    test('PAR-10 restrição malformada é incompatível', () {
      // Nível desconhecido.
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'active_restrictions': [
                {
                  'id': 'r-1',
                  'level': 'severe',
                  'category': 'injury',
                  'description': 'x',
                  'activities_restricted': <Object?>[],
                  'since': ts(now),
                  'is_overdue': false,
                },
              ],
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );

      // is_overdue não booleano.
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'active_restrictions': [
                {
                  'id': 'r-1',
                  'level': 'absolute',
                  'category': 'injury',
                  'description': 'x',
                  'activities_restricted': <Object?>[],
                  'since': ts(now),
                  'is_overdue': 'sim',
                },
              ],
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );

      // since ausente.
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'active_restrictions': [
                {
                  'id': 'r-1',
                  'level': 'absolute',
                  'category': 'injury',
                  'description': 'x',
                  'activities_restricted': <Object?>[],
                  'is_overdue': false,
                },
              ],
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );

      // Não é lista.
      expect(
        expectIncompatible(
          readyDoc(overrides: {'active_restrictions': 'nenhuma'}),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
    });

    test('PAR-11 restriction_count malformado é incompatível', () {
      for (final bad in <Object?>[
        {'absolute': 0, 'partial': 0},
        {'absolute': -1, 'partial': 0, 'attention': 0},
        {'absolute': '0', 'partial': 0, 'attention': 0},
        'zero',
        null,
      ]) {
        expect(
          expectIncompatible(
            readyDoc(overrides: {'restriction_count': bad}),
          ).failure,
          ReadinessParseFailure.malformedStructure,
          reason: 'restriction_count $bad deve rejeitar',
        );
      }
    });

    test('PAR-12 data_completeness malformado é incompatível', () {
      // Chave faltando.
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'data_completeness': {
                'has_recent_weight': true,
                'has_vaccination_current': true,
                'has_recent_consultation': true,
              },
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
      // Tipo errado.
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'data_completeness': {
                'has_recent_weight': 'sim',
                'has_vaccination_current': true,
                'has_recent_consultation': true,
                'has_active_nutrition': true,
              },
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
      // Ausente.
      expect(
        expectIncompatible(
          readyDoc(overrides: {'data_completeness': null}),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
    });

    test('PAR-13 alerta malformado é incompatível', () {
      expect(
        expectIncompatible(
          readyDoc(
            overrides: {
              'open_alerts': [
                {'code': 'x', 'severity': 'attention'},
              ],
            },
          ),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
      expect(
        expectIncompatible(
          readyDoc(overrides: {'open_alerts': 'nenhum'}),
        ).failure,
        ReadinessParseFailure.malformedStructure,
      );
    });

    test('PAR-16 documento ausente/vazio é missing', () {
      expect(
        expectIncompatible(null).failure,
        ReadinessParseFailure.missing,
      );
      expect(
        expectIncompatible(<String, Object?>{}).failure,
        ReadinessParseFailure.missing,
      );
    });
  });

  group('PAR — projeção indisponível (plano técnico)', () {
    test('PAR-14 unavailable só com metadata técnica', () {
      final snap = expectSuccess({
        'projection_status': 'unavailable',
        'projection_attempted_at': ts(now),
        'technical_blockers': ['weight_source_permission_denied'],
        'updated_at': ts(now),
        'schema_version': 1,
      });

      expect(snap.isUnavailable, isTrue);
      expect(snap.isReady, isFalse);
      // Nenhum veredito clínico foi fabricado.
      expect(snap.verdict, isNull);
      expect(snap.lastKnownGood, isNull);
      expect(snap.technicalBlockers, ['weight_source_permission_denied']);
    });

    test('PAR-15 unavailable com last-known-good NÃO produz veredito atual', () {
      final snap = expectSuccess(
        readyDoc(overrides: {
          // Servidor preservou o clínico anterior, mas marcou indisponível.
          'projection_status': 'unavailable',
          'technical_blockers': ['weight_source_inconclusive'],
        }),
      );

      expect(snap.isUnavailable, isTrue);
      // A invariante central do Gate 6: verdict ATUAL é null.
      expect(
        snap.verdict,
        isNull,
        reason: 'unavailable nunca expõe veredito atual',
      );
      // O clínico preservado fica só como diagnóstico/cache.
      expect(snap.lastKnownGood, isNotNull);
      expect(snap.lastKnownGood!.status, ReadinessStatus.operational);
      expect(snap.technicalBlockers, ['weight_source_inconclusive']);
    });

    test(
      'PAR-15b unavailable com clínico preservado incompleto descarta last-known-good',
      () {
        final snap = expectSuccess({
          'projection_status': 'unavailable',
          'projection_attempted_at': ts(now),
          'technical_blockers': ['nutrition_active_plan_conflict'],
          'schema_version': 1,
          // Clínico parcial: status presente, resto ausente.
          'readiness_status': 'operational',
        });

        expect(snap.isUnavailable, isTrue);
        expect(snap.verdict, isNull);
        // Parcial não é aproveitado nem como last-known-good.
        expect(snap.lastKnownGood, isNull);
      },
    );

    test('PAR-17 unavailable sem blockers ainda é indisponível', () {
      final snap = expectSuccess({
        'projection_status': 'unavailable',
        'projection_attempted_at': ts(now),
        'schema_version': 1,
      });
      expect(snap.isUnavailable, isTrue);
      expect(snap.technicalBlockers, isEmpty);
      expect(snap.verdict, isNull);
    });
  });

  group('AGE — frescor usa tempo de projeção, não tempo clínico', () {
    test('ageFrom usa readiness_updated_at quando ready', () {
      final snap = expectSuccess(
        readyDoc(
          overrides: {
            'readiness_updated_at': ts(now.subtract(const Duration(minutes: 3))),
            // Tempo clínico muito antigo — não deve influenciar o frescor.
            'last_evaluated_at': ts(now.subtract(const Duration(days: 40))),
          },
        ),
      );
      final age = snap.ageFrom(now);
      expect(age, const Duration(minutes: 3));
      expect(
        age.inDays,
        0,
        reason: 'last_evaluated_at (40 dias) não pode virar idade da projeção',
      );
    });

    test('ageFrom usa projection_attempted_at quando unavailable', () {
      final snap = expectSuccess({
        'projection_status': 'unavailable',
        'projection_attempted_at': ts(now.subtract(const Duration(minutes: 9))),
        'schema_version': 1,
      });
      expect(snap.ageFrom(now), const Duration(minutes: 9));
    });

    test('ageFrom nunca é negativa (clock skew)', () {
      final snap = expectSuccess(
        readyDoc(
          overrides: {
            'readiness_updated_at': ts(now.add(const Duration(minutes: 5))),
          },
        ),
      );
      expect(snap.ageFrom(now), Duration.zero);
    });
  });

  group('CONTRATO — exame não é gate de prontidão', () {
    test('has_recent_exam no documento é ignorado, não aceito como gate', () {
      final snap = expectSuccess(
        readyDoc(
          overrides: {
            'data_completeness': {
              'has_recent_weight': true,
              'has_vaccination_current': true,
              'has_recent_consultation': true,
              'has_active_nutrition': true,
              // Campo legado de ADR antigo: presente mas irrelevante.
              'has_recent_exam': false,
            },
          },
        ),
      );
      // Snapshot segue válido e operacional apesar de has_recent_exam=false.
      expect(snap.verdict!.status, ReadinessStatus.operational);
      final c = snap.verdict!.completeness;
      expect(c.hasRecentWeight, isTrue);
      expect(c.hasVaccinationCurrent, isTrue);
      expect(c.hasRecentConsultation, isTrue);
      expect(c.hasActiveNutrition, isTrue);
    });
  });
}
