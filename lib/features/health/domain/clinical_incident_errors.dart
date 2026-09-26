/// Falhas canônicas da Intercorrência Clínica (F20.INTERCORRENCIA-V1).
sealed class ClinicalIncidentFailure {
  const ClinicalIncidentFailure({required this.message, this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class ClinicalIncidentPermissionDenied extends ClinicalIncidentFailure {
  const ClinicalIncidentPermissionDenied({
    super.message = 'Sem permissão para registrar intercorrência clínica (requer health.record_clinical).',
    super.cause,
  });
}

final class ClinicalIncidentNotFound extends ClinicalIncidentFailure {
  const ClinicalIncidentNotFound({
    super.message = 'Cão ou prontuário clínico não encontrado.',
    super.cause,
  });
}

final class ClinicalIncidentConflict extends ClinicalIncidentFailure {
  const ClinicalIncidentConflict({
    super.message = 'Conflito de concorrência ou caso clínico encerrado.',
    super.cause,
  });
}

final class ClinicalIncidentValidation extends ClinicalIncidentFailure {
  const ClinicalIncidentValidation({
    required super.message,
    super.cause,
  });
}

final class ClinicalIncidentOffline extends ClinicalIncidentFailure {
  const ClinicalIncidentOffline({
    super.message = 'Falha de conexão com o servidor. Tente novamente.',
    super.cause,
  });
}

final class ClinicalIncidentUnexpected extends ClinicalIncidentFailure {
  const ClinicalIncidentUnexpected({
    required super.message,
    super.cause,
  });
}
