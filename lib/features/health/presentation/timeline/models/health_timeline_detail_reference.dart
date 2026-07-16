/// Referência pura para resolução futura de detalhe (Fase 3D).
///
/// Não navega, não importa telas e não resolve rotas.
final class HealthTimelineDetailReference {
  const HealthTimelineDetailReference({
    required this.sourceType,
    required this.sourceId,
    this.caseId,
  }) : assert(sourceType != '', 'sourceType não pode ser vazio'),
       assert(sourceId != '', 'sourceId não pode ser vazio');

  /// Tipo da fonte canônica / projeção (wire ou tipo conhecido).
  final String sourceType;

  /// ID do documento fonte.
  final String sourceId;

  /// Caso clínico associado, quando aplicável.
  final String? caseId;

  @override
  bool operator ==(Object other) =>
      other is HealthTimelineDetailReference &&
      other.sourceType == sourceType &&
      other.sourceId == sourceId &&
      other.caseId == caseId;

  @override
  int get hashCode => Object.hash(sourceType, sourceId, caseId);

  @override
  String toString() =>
      'HealthTimelineDetailReference($sourceType/$sourceId'
      '${caseId == null ? '' : ', caseId=$caseId'})';
}
