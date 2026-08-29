import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:canil_gcm/features/health/domain/readiness_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final actor = RecordedBy(
    uid: 'u1',
    name: 'Condutor',
    internalRole: 'condutor',
  );
  final professional = ProfessionalIdentity(
    name: 'Dra. Vet',
    registrationType: ProfessionalRegistrationType.crmv,
    registrationNumber: 'CRMV-123',
    clinic: 'Clínica Norte',
  );
  final sourceDoc = const HealthDocumentRef(healthDocumentId: 'doc-1');
  final now = DateTime.utc(2026, 7, 14);

  OperationalRestriction restriction({
    required String id,
    RestrictionLevel level = RestrictionLevel.absolute,
    List<String> activities = const ['busca'],
  }) => OperationalRestriction(
    id: id,
    dogId: 'dog-1',
    level: level,
    category: RestrictionCategory.injury,
    description: 'desc',
    issuedAt: now,
    recordedBy: actor,
    professional: professional,
    sourceDocument: sourceDoc,
    status: RestrictionStatus.active,
    schemaVersion: 1,
    activitiesRestricted: activities,
  );

  final policy = const ReadinessPolicy();

  /// Matriz de precedência documentada (Readiness Policy §3) — declarada no
  /// teste de forma independente da implementação.
  /// Ordem: 1 absolute > 2 partial > 3 attention > 4 not_evaluated >
  /// 5 incomplete > 6 operational.
  ReadinessEvaluationInput input({
    List<OperationalRestriction> restrictions = const [],
    bool hasAnyHealthEvaluation = true,
    bool hasRecentWeight = true,
    bool hasVaccinationCurrent = true,
    bool hasRecentExam = true,
    bool hasActiveNutritionPlan = true,
  }) => ReadinessEvaluationInput(
    activeRestrictions: restrictions,
    hasAnyHealthEvaluation: hasAnyHealthEvaluation,
    hasRecentWeight: hasRecentWeight,
    hasVaccinationCurrent: hasVaccinationCurrent,
    hasRecentExam: hasRecentExam,
    hasActiveNutritionPlan: hasActiveNutritionPlan,
  );

  group('ReadinessPolicy — precedência documentada', () {
    test('1 absolute vence partial, attention e dados incompletos', () {
      final decision = policy.evaluate(
        input(
          restrictions: [
            restriction(id: 'att', level: RestrictionLevel.attention),
            restriction(id: 'par', level: RestrictionLevel.partial),
            restriction(id: 'abs', level: RestrictionLevel.absolute),
          ],
          hasRecentWeight: false,
        ),
      );
      expect(decision.status, ReadinessStatus.temporarilyUnfit);
      expect(
        decision.contributingRestrictions.every(
          (r) => r.level == RestrictionLevel.absolute,
        ),
        isTrue,
      );
    });

    test('2 partial vence attention e dados incompletos', () {
      final decision = policy.evaluate(
        input(
          restrictions: [
            restriction(id: 'att', level: RestrictionLevel.attention),
            restriction(id: 'par', level: RestrictionLevel.partial),
          ],
          hasVaccinationCurrent: false,
        ),
      );
      expect(decision.status, ReadinessStatus.fitWithRestrictions);
    });

    test('3 attention vence dados incompletos', () {
      final decision = policy.evaluate(
        input(
          restrictions: [
            restriction(id: 'att', level: RestrictionLevel.attention),
          ],
          hasRecentExam: false,
        ),
      );
      expect(decision.status, ReadinessStatus.operationalAttention);
      expect(decision.contributingRestrictions, isNotEmpty);
    });

    test(
      '4 not_evaluated vence dados incompletos (prioridade 4 antes de 5)',
      () {
        final decision = policy.evaluate(
          input(
            hasAnyHealthEvaluation: false,
            hasRecentWeight: false,
            hasVaccinationCurrent: false,
            hasRecentExam: false,
            hasActiveNutritionPlan: false,
          ),
        );
        expect(decision.status, ReadinessStatus.notEvaluated);
        expect(decision.contributingRestrictions, isEmpty);
      },
    );

    test(
      '5 dados incompletos com avaliação prévia → operational_attention',
      () {
        final decision = policy.evaluate(
          input(hasRecentWeight: false, hasVaccinationCurrent: false),
        );
        expect(decision.status, ReadinessStatus.operationalAttention);
        expect(decision.contributingRestrictions, isEmpty);
      },
    );

    test('6 caso completo sem restrições → operational', () {
      final decision = policy.evaluate(input());
      expect(decision.status, ReadinessStatus.operational);
      expect(decision.contributingRestrictions, isEmpty);
    });

    test('qualquer indicador de completude falso aciona prioridade 5', () {
      final cases = <ReadinessEvaluationInput>[
        input(hasRecentWeight: false),
        input(hasVaccinationCurrent: false),
        input(hasRecentExam: false),
        input(hasActiveNutritionPlan: false),
      ];
      for (final c in cases) {
        expect(policy.evaluate(c).status, ReadinessStatus.operationalAttention);
      }
    });

    test('decision não expõe catálogo de strings de pendência', () {
      final decision = policy.evaluate(
        input(hasRecentWeight: false, hasActiveNutritionPlan: false),
      );
      // API pública mínima: status + contributingRestrictions apenas.
      expect(decision.status, ReadinessStatus.operationalAttention);
      expect(decision.contributingRestrictions, isEmpty);
    });

    test('fatos de completude permanecem na entrada', () {
      final facts = input(
        hasRecentWeight: false,
        hasVaccinationCurrent: true,
        hasRecentExam: false,
        hasActiveNutritionPlan: true,
      );
      expect(facts.hasSignificantIncompleteData, isTrue);
      expect(facts.hasRecentWeight, isFalse);
      expect(facts.hasVaccinationCurrent, isTrue);
      policy.evaluate(facts);
    });

    test('activeRestrictions é imutável por alias', () {
      final source = <OperationalRestriction>[
        restriction(id: 'r1', level: RestrictionLevel.partial),
      ];
      final facts = input(restrictions: source);
      source.add(restriction(id: 'r2', level: RestrictionLevel.absolute));
      expect(facts.activeRestrictions, hasLength(1));
      expect(
        () => facts.activeRestrictions.add(
          restriction(id: 'r3', level: RestrictionLevel.attention),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('decision.contributingRestrictions é imutável por alias', () {
      final decision = policy.evaluate(
        input(
          restrictions: [
            restriction(id: 'abs', level: RestrictionLevel.absolute),
          ],
        ),
      );
      expect(decision.contributingRestrictions, hasLength(1));
      expect(
        () => decision.contributingRestrictions.add(
          restriction(id: 'x', level: RestrictionLevel.absolute),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
