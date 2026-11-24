import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_coverage.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_evidence_classifier.dart';

void main() {
  group('evaluateCoverage', () {
    test('engajamento bloqueante retorna blocking', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: true,
        ),
      ];
      const engagements = [
        Engagement(engagementId: 'eng-1', isBlocking: true),
      ];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.blocking,
      );
    });

    test('engajamento bloqueante tem prioridade sobre evidência completa', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: true,
        ),
      ];
      const engagements = [
        Engagement(engagementId: 'eng-ok', isBlocking: false),
        Engagement(engagementId: 'eng-block', isBlocking: true),
      ];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.blocking,
      );
    });

    test('consulta vazia sem evidência retorna indeterminate', () {
      const engagements = <Engagement>[];
      const evidence = <CoverageEvidence>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('evidência autoritativa completa e específica retorna provenClear', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: true,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.provenClear,
      );
    });

    test('evidência sem correspondência de sessão/geração retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: false,
          isAuthoritativeAndSufficient: true,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('evidência legado retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.legacyDocumentaryOnly,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: true,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('evidência incompleta retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.incomplete,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: false,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('evidência contraditória retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.contradictory,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: false,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('proveniência insuficiente retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.insufficientProvenance,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: false,
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('lista parcial sem evidência autoritativa suficiente retorna indeterminate', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: false, // não suficiente
        ),
      ];
      const engagements = <Engagement>[];

      expect(
        evaluateCoverage(evidence: evidence, engagements: engagements),
        CoverageVerdict.indeterminate,
      );
    });

    test('sem engajamentos e evidência válida retorna provenClear', () {
      const evidence = [
        CoverageEvidence(
          classification: EvidenceClassification.authoritativeCurrent,
          matchesSessionAndGeneration: true,
          isAuthoritativeAndSufficient: true,
        ),
      ];

      expect(
        evaluateCoverage(evidence: evidence, engagements: const []),
        CoverageVerdict.provenClear,
      );
    });
  });
}