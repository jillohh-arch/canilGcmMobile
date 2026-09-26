import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_errors.dart';

/// Caso clínico utilizável como destino de uma nova consulta.
///
/// Projeção mínima de leitura: apenas o necessário para o seletor inline e
/// para a chamada de Append. Não é o agregado completo de `ClinicalCase`.
final class ClinicalCaseOption {
  const ClinicalCaseOption({
    required this.caseId,
    required this.title,
    required this.statusWireName,
    required this.revision,
    this.openedAt,
  });

  final String caseId;
  final String title;

  /// `clinical_status` cru, na forma wire (`open`, `under_investigation`, ...).
  final String statusWireName;

  /// Token de concorrência otimista do caso.
  final int revision;

  final DateTime? openedAt;
}

/// Resultado tipado do registro de uma consulta canônica.
sealed class ConsultationSaveResult {
  const ConsultationSaveResult();
}

/// Consulta registrada abrindo um novo caso (`healthOpenClinicalCase`).
///
/// Open é atômico: caso + evento de abertura + receipt + audit. O evento de
/// abertura **é** a consulta, por isso nenhum Append é emitido depois.
final class ConsultationOpenedCase extends ConsultationSaveResult {
  const ConsultationOpenedCase({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.wasNoOp,
    required this.operationId,
  });

  final String dogId;
  final String caseId;

  /// `opening_event_id` — identidade do evento de consulta criado.
  final String eventId;

  /// `true` em replay idempotente do mesmo `operationId`.
  final bool wasNoOp;

  final String operationId;
}

/// Consulta anexada a um caso existente (`healthAppendClinicalEvent`).
final class ConsultationAppendedToCase extends ConsultationSaveResult {
  const ConsultationAppendedToCase({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.wasNoOp,
    required this.operationId,
  });

  final String dogId;
  final String caseId;
  final String eventId;
  final bool wasNoOp;
  final String operationId;
}

/// O fato clínico FOI criado, mas a finalização não foi confirmada.
///
/// **NÃO é sucesso.** O evento existe em `draft`, que não representa uma
/// consulta concluída. A UI deve informar isso factualmente e permitir
/// retentar SOMENTE a finalização — nunca criar outra consulta.
///
/// Carrega a identidade exata necessária para o retry.
final class ConsultationPendingFinalization extends ConsultationSaveResult {
  const ConsultationPendingFinalization({
    required this.dogId,
    required this.caseId,
    required this.eventId,
    required this.finalizeOperationId,
    required this.expectedRevision,
    required this.failure,
    required this.openedNewCase,
  });

  final String dogId;
  final String caseId;

  /// Evento criado em `draft` que precisa ser finalizado.
  final String eventId;

  /// Mesmo `operationId` de finalização a reusar no retry.
  final String finalizeOperationId;

  /// Revisão a enviar no retry de `Finalize`.
  final int expectedRevision;

  /// Motivo da falha de finalização.
  final ClinicalConsultationFailure failure;

  /// `true` se a fase de criação abriu um caso novo.
  final bool openedNewCase;
}

final class ConsultationSaveFailure extends ConsultationSaveResult {
  const ConsultationSaveFailure(this.failure);

  final ClinicalConsultationFailure failure;
}

/// Porta canônica de escrita/leitura da Consulta Veterinária.
///
/// Produção: `FirebaseFunctionsClinicalConsultationGateway`.
/// Testes: fakes locais.
///
/// **Sem fallback legado.** Se o callable falhar, a falha é propagada; a
/// consulta nunca é desviada para `HealthLogModel`.
abstract interface class ClinicalConsultationGateway {
  /// Casos do K9 que podem receber uma nova consulta.
  ///
  /// Ordenados do mais recente para o mais antigo. Lista vazia significa que
  /// a UI deve oferecer "Abrir novo caso".
  Future<List<ClinicalCaseOption>> loadUsableCases(String dogId);

  /// Registra a consulta.
  ///
  /// - `command.caseId == null` → `healthOpenClinicalCase` (Open ONLY).
  /// - `command.caseId != null` → `healthAppendClinicalEvent` (Append ONLY).
  ///
  /// Só devolve sucesso depois de `healthFinalizeClinicalEvent` confirmar
  /// `status = final`. Se a criação funcionar e a finalização falhar, devolve
  /// [ConsultationPendingFinalization].
  Future<ConsultationSaveResult> saveConsultation(ConsultationCommand command);

  /// Retenta SOMENTE a finalização de um evento já criado.
  ///
  /// Nunca cria uma nova consulta. Reusa o `finalizeOperationId` original, de
  /// modo que o backend responda por replay se a finalização anterior tiver
  /// chegado sem que a resposta voltasse.
  Future<ConsultationSaveResult> retryFinalization(
    ConsultationPendingFinalization pending,
  );

  /// Consultas CONCLUÍDAS de um caso, lidas do caminho canônico.
  ///
  /// Escopo deliberadamente por CASO: `clinical_events` é subcoleção de
  /// `clinical_cases`, e a leitura cross-case exigiria `collectionGroup`, que
  /// as Rules vigentes não autorizam. Ver
  /// `GLOBAL CLINICAL TIMELINE = DEFERRED`.
  ///
  /// Somente `status == final`. Um `draft` deixado por falha parcial NÃO é
  /// uma consulta concluída.
  Future<List<ClinicalConsultationRecordView>> loadCaseConsultations({
    required String dogId,
    required String caseId,
  });
}

/// Projeção de leitura de uma consulta concluída.
///
/// Vive no domínio para que a UI e os testes não dependam da camada Firestore.
final class ClinicalConsultationRecordView {
  const ClinicalConsultationRecordView({
    required this.caseId,
    required this.eventId,
    required this.occurredAt,
    required this.reasonLabel,
    this.veterinarianName,
    this.clinicOrLocation,
    this.findings,
    this.diagnosis,
    this.operationalStatusLabel,
    this.professionalName,
    this.professionalRegistration,
    this.recordedByName,
  });

  final String caseId;
  final String eventId;
  final DateTime occurredAt;
  final String reasonLabel;
  final String? veterinarianName;
  final String? clinicOrLocation;
  final String? findings;
  final String? diagnosis;
  final String? operationalStatusLabel;
  final String? professionalName;
  final String? professionalRegistration;

  /// Usuário interno K9 Ops que registrou. NUNCA exibido como o profissional.
  final String? recordedByName;

  String get title => 'Consulta Veterinária';
}
