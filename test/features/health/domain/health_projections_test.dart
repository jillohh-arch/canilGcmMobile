import 'package:canil_gcm/features/health/domain/health_projections.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';
import 'package:canil_gcm/features/health/domain/health_v1_models.dart';
import 'package:canil_gcm/features/health/domain/health_v1_value_objects.dart';
import 'package:canil_gcm/features/health/domain/operational_restriction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 14);
  final earlier = DateTime.utc(2026, 7, 14, 9);

  group('HealthTimelineItem', () {
    test('é imutável em listas e mapas', () {
      final item = HealthTimelineItem(
        id: 't1',
        timelineType: HealthTimelineType.vaccination,
        occurredAt: now,
        recordedAt: now,
        title: 'Vacina V10',
        sourceCollection: 'vaccination_records',
        sourceId: 'vr-1',
      );
      expect(item.title, 'Vacina V10');
      expect(item.amendmentCount, 0);
    });

    test('amendment_count não pode ser negativo', () {
      expect(
        () => HealthTimelineItem(
          id: 't1',
          timelineType: HealthTimelineType.vaccination,
          occurredAt: now,
          recordedAt: now,
          title: 'x',
          sourceCollection: 'c',
          sourceId: 'i',
          amendmentCount: -1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ReadinessSnapshot', () {
    test('construção válida pelo caminho canônico', () {
      final snap = ReadinessSnapshot(
        status: ReadinessStatus.operational,
        readinessLabel: 'Operacional',
        readinessReason: 'Sem restrições e dados completos',
        readinessUpdatedAt: now,
        lastEvaluatedAt: earlier,
        evaluatedBy: 'function_v1',
        schemaVersion: 1,
      );
      expect(snap.status, ReadinessStatus.operational);
      expect(snap.readinessLabel, 'Operacional');
      expect(snap.readinessReason, 'Sem restrições e dados completos');
      expect(snap.readinessUpdatedAt, isNot(snap.lastEvaluatedAt));
      expect(snap.evaluatedBy, 'function_v1');
      expect(snap.restrictionCount.absolute, 0);
    });

    test('evaluatedBy system é aceito (ADR-005 §12)', () {
      final snap = ReadinessSnapshot(
        status: ReadinessStatus.notEvaluated,
        readinessLabel: 'Não Avaliado',
        readinessReason: 'Sem avaliação',
        readinessUpdatedAt: now,
        lastEvaluatedAt: now,
        evaluatedBy: 'system',
        schemaVersion: 1,
      );
      expect(snap.evaluatedBy, 'system');
    });

    test('evaluatedBy arbitrário é rejeitado', () {
      expect(
        () => ReadinessSnapshot(
          status: ReadinessStatus.operational,
          readinessLabel: 'Operacional',
          readinessReason: 'ok',
          readinessUpdatedAt: now,
          lastEvaluatedAt: now,
          evaluatedBy: 'banana',
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('schemaVersion <= 0 é rejeitado', () {
      expect(
        () => ReadinessSnapshot(
          status: ReadinessStatus.operational,
          readinessLabel: 'Operacional',
          readinessReason: 'ok',
          readinessUpdatedAt: now,
          lastEvaluatedAt: now,
          evaluatedBy: 'function_v1',
          schemaVersion: 0,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('readinessLabel vazio é rejeitado', () {
      expect(
        () => ReadinessSnapshot(
          status: ReadinessStatus.operational,
          readinessLabel: '   ',
          readinessReason: 'ok',
          readinessUpdatedAt: now,
          lastEvaluatedAt: now,
          evaluatedBy: 'function_v1',
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('readinessReason vazio é rejeitado', () {
      expect(
        () => ReadinessSnapshot(
          status: ReadinessStatus.operational,
          readinessLabel: 'Operacional',
          readinessReason: '',
          readinessUpdatedAt: now,
          lastEvaluatedAt: now,
          evaluatedBy: 'function_v1',
          schemaVersion: 1,
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('restrictionCount negativo é rejeitado', () {
      expect(
        () => ReadinessRestrictionCount(absolute: -1),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ReadinessRestrictionCount(partial: -2),
        throwsA(isA<HealthDomainException>()),
      );
      expect(
        () => ReadinessRestrictionCount(attention: -3),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('restrictionCount divergente das restrições é rejeitado', () {
      final summary = ActiveRestrictionSummary(
        id: 'r1',
        level: RestrictionLevel.absolute,
        category: RestrictionCategory.injury,
        since: now,
      );
      expect(
        () => ReadinessSnapshot(
          status: ReadinessStatus.temporarilyUnfit,
          readinessLabel: 'Temporariamente Inapto',
          readinessReason: 'abs',
          readinessUpdatedAt: now,
          lastEvaluatedAt: now,
          evaluatedBy: 'function_v1',
          schemaVersion: 1,
          activeRestrictionsSummary: [summary],
          restrictionCount: ReadinessRestrictionCount(
            absolute: 0,
            partial: 0,
            attention: 0,
          ),
        ),
        throwsA(isA<HealthDomainException>()),
      );
    });

    test('contagem é derivada quando não informada', () {
      final summaries = [
        ActiveRestrictionSummary(
          id: 'a',
          level: RestrictionLevel.absolute,
          category: RestrictionCategory.injury,
          since: now,
        ),
        ActiveRestrictionSummary(
          id: 'p',
          level: RestrictionLevel.partial,
          category: RestrictionCategory.injury,
          since: now,
          activitiesRestricted: const ['busca'],
        ),
      ];
      final snap = ReadinessSnapshot(
        status: ReadinessStatus.temporarilyUnfit,
        readinessLabel: 'Temporariamente Inapto',
        readinessReason: 'abs',
        readinessUpdatedAt: now,
        lastEvaluatedAt: now,
        evaluatedBy: 'function_v1',
        schemaVersion: 1,
        activeRestrictionsSummary: summaries,
      );
      expect(snap.restrictionCount.absolute, 1);
      expect(snap.restrictionCount.partial, 1);
      expect(snap.restrictionCount.attention, 0);
    });

    test('activeRestrictionsSummary é imutável por alias', () {
      final source = <ActiveRestrictionSummary>[
        ActiveRestrictionSummary(
          id: 'r1',
          level: RestrictionLevel.attention,
          category: RestrictionCategory.chronic,
          since: now,
        ),
      ];
      final snap = ReadinessSnapshot(
        status: ReadinessStatus.operationalAttention,
        readinessLabel: 'Operacional com Atenção',
        readinessReason: 'atenção',
        readinessUpdatedAt: now,
        lastEvaluatedAt: now,
        evaluatedBy: 'function_v1',
        schemaVersion: 1,
        activeRestrictionsSummary: source,
      );
      source.add(
        ActiveRestrictionSummary(
          id: 'r2',
          level: RestrictionLevel.partial,
          category: RestrictionCategory.injury,
          since: now,
          activitiesRestricted: const ['faro'],
        ),
      );
      expect(snap.activeRestrictionsSummary, hasLength(1));
      expect(
        () => snap.activeRestrictionsSummary.add(
          ActiveRestrictionSummary(
            id: 'x',
            level: RestrictionLevel.attention,
            category: RestrictionCategory.other,
            since: now,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'ActiveRestrictionSummary.activitiesRestricted imutável por alias',
      () {
        final activities = <String>['busca'];
        final summary = ActiveRestrictionSummary(
          id: 'r1',
          level: RestrictionLevel.partial,
          category: RestrictionCategory.injury,
          since: now,
          activitiesRestricted: activities,
        );
        activities.add('faro');
        expect(summary.activitiesRestricted, ['busca']);
        expect(
          () => summary.activitiesRestricted.add('guarda'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );

    test('fromActiveRestrictions preenche contagem e activities', () {
      final actor = RecordedBy(
        uid: 'u1',
        name: 'Condutor',
        internalRole: 'condutor',
      );
      final professional = ProfessionalIdentity(
        name: 'Dra. Vet',
        registrationType: ProfessionalRegistrationType.crmv,
        registrationNumber: 'CRMV-1',
        clinic: 'Clínica',
      );
      final r1 = OperationalRestriction(
        id: 'abs-1',
        dogId: 'dog-1',
        level: RestrictionLevel.absolute,
        category: RestrictionCategory.injury,
        description: 'fratura',
        issuedAt: now,
        recordedBy: actor,
        professional: professional,
        sourceDocument: const HealthDocumentRef(healthDocumentId: 'd1'),
        status: RestrictionStatus.active,
        schemaVersion: 1,
      );
      final r2 = OperationalRestriction(
        id: 'par-1',
        dogId: 'dog-1',
        level: RestrictionLevel.partial,
        category: RestrictionCategory.injury,
        description: 'limitado',
        issuedAt: now,
        recordedBy: actor,
        professional: professional,
        sourceDocument: const HealthDocumentRef(healthDocumentId: 'd1'),
        status: RestrictionStatus.active,
        schemaVersion: 1,
        activitiesRestricted: const ['busca'],
      );
      final snap = ReadinessSnapshot.fromActiveRestrictions(
        status: ReadinessStatus.temporarilyUnfit,
        readinessLabel: 'Temporariamente Inapto',
        readinessReason: 'Restrição absoluta ativa',
        readinessUpdatedAt: now,
        lastEvaluatedAt: now,
        evaluatedBy: 'function_v1',
        schemaVersion: 1,
        activeRestrictions: [r1, r2],
      );
      expect(snap.restrictionCount.absolute, 1);
      expect(snap.restrictionCount.partial, 1);
      expect(
        snap.activeRestrictionsSummary
            .firstWhere((s) => s.id == 'par-1')
            .activitiesRestricted,
        ['busca'],
      );
    });
  });

  group('OperationalImpact imutabilidade', () {
    test('restrictionsIssued não sofre aliasing', () {
      final issued = <String>['rest-1'];
      final impact = OperationalImpact(
        level: OperationalImpactLevel.high,
        description: 'limitação',
        restrictionsIssued: issued,
      );
      issued.add('rest-2');
      expect(impact.restrictionsIssued, ['rest-1']);
      expect(
        () => impact.restrictionsIssued.add('rest-3'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
