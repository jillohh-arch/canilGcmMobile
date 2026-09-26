import 'package:canil_gcm/features/health/data/clinical/clinical_incident_operation_ids.dart';
import 'package:canil_gcm/features/health/domain/clinical_incident_command.dart';

final class ClinicalIncidentFormState {
  ClinicalIncidentFormState({DateTime? occurredAt})
      : occurredAt = occurredAt ?? DateTime.now();

  DateTime occurredAt;

  IncidentCategory? category;
  IncidentSeverity severity = IncidentSeverity.mild;
  String description = '';
  String initialConductNotes = '';
  final Set<IncidentConductAction> conductActions = <IncidentConductAction>{};
  bool hasOperationalImpact = false;

  String? selectedCaseId;
  bool openNewCase = true;
  String caseTitle = '';

  String veterinarianName = '';
  String clinicOrLocation = '';
  String professionalRegistrationType = 'CRMV';
  String professionalRegistrationNumber = '';

  IncidentOperationIds? _activeAttempt;

  IncidentOperationIds beginAttempt({DateTime? now}) {
    return _activeAttempt ??= IncidentOperationIdFactory.forAttempt(
      now: now,
    );
  }

  void completeAttempt() => _activeAttempt = null;

  IncidentOperationIds? get activeAttempt => _activeAttempt;

  bool get hasCaseTarget => openNewCase || selectedCaseId != null;

  String? validate() {
    if (!hasCaseTarget) {
      return 'Selecione o caso clínico ou escolha abrir um novo caso.';
    }
    if (category == null) {
      return 'Selecione a categoria/natureza da intercorrência.';
    }
    if (description.trim().isEmpty) {
      return 'Descreva o que ocorreu na intercorrência.';
    }
    if (description.trim().length > 2000) {
      return 'A descrição não pode exceder 2000 caracteres.';
    }
    if (initialConductNotes.trim().length > 2000) {
      return 'A conduta inicial não pode exceder 2000 caracteres.';
    }
    if (occurredAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return 'A data e hora da intercorrência não podem estar no futuro.';
    }
    return null;
  }

  ClinicalIncidentCommand toCommand({required String dogId, DateTime? now}) {
    final ids = beginAttempt(now: now);
    final vetName = veterinarianName.trim();
    return ClinicalIncidentCommand(
      dogId: dogId,
      operationId: ids.createOperationId,
      finalizeOperationId: ids.finalizeOperationId,
      occurredAt: occurredAt,
      category: category!,
      severity: severity,
      description: description.trim(),
      initialConductNotes: initialConductNotes.trim().isNotEmpty
          ? initialConductNotes.trim()
          : null,
      conductActions: Set<IncidentConductAction>.of(conductActions),
      hasOperationalImpact: hasOperationalImpact,
      caseId: openNewCase ? null : selectedCaseId,
      caseTitle: openNewCase
          ? (caseTitle.trim().isNotEmpty ? caseTitle.trim() : null)
          : null,
      professional: vetName.isEmpty
          ? null
          : IncidentProfessional(
              name: vetName,
              registrationType: _nullIfEmpty(professionalRegistrationType),
              registrationNumber: _nullIfEmpty(
                professionalRegistrationNumber,
              ),
              clinic: _nullIfEmpty(clinicOrLocation),
            ),
    );
  }

  static String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
