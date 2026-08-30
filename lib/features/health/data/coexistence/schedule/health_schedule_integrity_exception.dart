/// Documento canônico de agenda estruturalmente inválido.
///
/// Preferível falhar de forma observável a omitir compromisso de saúde.
final class HealthScheduleIntegrityException implements Exception {
  const HealthScheduleIntegrityException({
    required this.documentId,
    required this.reason,
    this.field,
  });

  final String documentId;
  final String reason;
  final String? field;

  @override
  String toString() {
    final f = field == null ? '' : ' field=$field';
    return 'HealthScheduleIntegrityException(doc=$documentId$f): $reason';
  }
}
