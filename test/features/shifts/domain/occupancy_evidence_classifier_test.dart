import 'package:flutter_test/flutter_test.dart';
import 'package:canil_gcm/features/shifts/domain/occupancy_evidence_classifier.dart';

void main() {
  group('classifyEvidence', () {
    test('evidência autoritativa atual retorna authoritativeCurrent', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: true,
        isComplete: true,
        hasContradictions: false,
        isLegacyDocumentary: false,
      );

      expect(classifyEvidence(input), EvidenceClassification.authoritativeCurrent);
    });

    test('evidência documental legada retorna legacyDocumentaryOnly', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: true,
        isComplete: true,
        hasContradictions: false,
        isLegacyDocumentary: true,
      );

      expect(classifyEvidence(input), EvidenceClassification.legacyDocumentaryOnly);
    });

    test('evidência contraditória retorna contradictory', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: true,
        isComplete: true,
        hasContradictions: true,
        isLegacyDocumentary: false,
      );

      expect(classifyEvidence(input), EvidenceClassification.contradictory);
    });

    test('contradição tem prioridade sobre outros fatores', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: false,
        isCurrent: false,
        isComplete: false,
        hasContradictions: true,
        isLegacyDocumentary: true,
      );

      expect(classifyEvidence(input), EvidenceClassification.contradictory);
    });

    test('evidência incompleta retorna incomplete', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: true,
        isComplete: false,
        hasContradictions: false,
        isLegacyDocumentary: false,
      );

      expect(classifyEvidence(input), EvidenceClassification.incomplete);
    });

    test('proveniência insuficiente retorna insufficientProvenance', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: false,
        isCurrent: true,
        isComplete: true,
        hasContradictions: false,
        isLegacyDocumentary: false,
      );

      expect(classifyEvidence(input), EvidenceClassification.insufficientProvenance);
    });

    test('evidência não atual com proveniência retorna insufficientProvenance', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: false,
        isComplete: true,
        hasContradictions: false,
        isLegacyDocumentary: false,
      );

      expect(classifyEvidence(input), EvidenceClassification.insufficientProvenance);
    });

    test('legado tem prioridade sobre proveniência verificada', () {
      // Mesmo com proveniência verificada, se for legado → legacyDocumentaryOnly.
      const input = EvidenceInput(
        hasVerifiedProvenance: true,
        isCurrent: true,
        isComplete: true,
        hasContradictions: false,
        isLegacyDocumentary: true,
      );

      expect(classifyEvidence(input), EvidenceClassification.legacyDocumentaryOnly);
    });

    test('incompleta tem prioridade sobre proveniência', () {
      const input = EvidenceInput(
        hasVerifiedProvenance: false,
        isCurrent: true,
        isComplete: false,
        hasContradictions: false,
        isLegacyDocumentary: false,
      );

      // Incompleta vem antes de proveniência insuficiente.
      expect(classifyEvidence(input), EvidenceClassification.incomplete);
    });
  });
}