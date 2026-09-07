import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Categorias/naturezas canônicas de intercorrência clínica (F20.INTERCORRENCIA-V1).
enum IncidentCategory {
  trauma,
  intoxication,
  heatstroke,
  respiratory,
  digestive,
  allergic,
  behavioral,
  neurological,
  musculoskeletal,
  dermatological,
  other,
}

extension IncidentCategoryWire on IncidentCategory {
  String get wireValue => switch (this) {
    IncidentCategory.trauma => 'trauma',
    IncidentCategory.intoxication => 'intoxication',
    IncidentCategory.heatstroke => 'heatstroke',
    IncidentCategory.respiratory => 'respiratory',
    IncidentCategory.digestive => 'digestive',
    IncidentCategory.allergic => 'allergic',
    IncidentCategory.behavioral => 'behavioral',
    IncidentCategory.neurological => 'neurological',
    IncidentCategory.musculoskeletal => 'musculoskeletal',
    IncidentCategory.dermatological => 'dermatological',
    IncidentCategory.other => 'other',
  };

  String get label => switch (this) {
    IncidentCategory.trauma => 'Trauma / Lesão',
    IncidentCategory.intoxication => 'Intoxicação / Envenenamento',
    IncidentCategory.heatstroke => 'Intermação / Hipertermia',
    IncidentCategory.respiratory => 'Respiratória',
    IncidentCategory.digestive => 'Digestiva / Gastrointestinal',
    IncidentCategory.allergic => 'Alergia / Picada',
    IncidentCategory.behavioral => 'Comportamental',
    IncidentCategory.neurological => 'Neurológica',
    IncidentCategory.musculoskeletal => 'Musculoesquelética',
    IncidentCategory.dermatological => 'Dermatológica',
    IncidentCategory.other => 'Outra',
  };

  static IncidentCategory fromWire(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final cat in IncidentCategory.values) {
      if (cat.wireValue == normalized) return cat;
    }
    return IncidentCategory.other;
  }
}

/// Níveis de gravidade canônicos de intercorrência clínica (F20.INTERCORRENCIA-V1).
enum IncidentSeverity {
  mild,
  moderate,
  severe,
  critical,
}

extension IncidentSeverityWire on IncidentSeverity {
  String get wireValue => switch (this) {
    IncidentSeverity.mild => 'mild',
    IncidentSeverity.moderate => 'moderate',
    IncidentSeverity.severe => 'severe',
    IncidentSeverity.critical => 'critical',
  };

  String get label => switch (this) {
    IncidentSeverity.mild => 'Leve',
    IncidentSeverity.moderate => 'Moderada',
    IncidentSeverity.severe => 'Grave',
    IncidentSeverity.critical => 'Crítica / Emergência',
  };

  static IncidentSeverity fromWire(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final sev in IncidentSeverity.values) {
      if (sev.wireValue == normalized) return sev;
    }
    return IncidentSeverity.mild;
  }
}

/// Ações de conduta inicial estruturadas (F20.INTERCORRENCIA-V1).
enum IncidentConductAction {
  firstAidApplied,
  veterinaryReferral,
  isolationRest,
  medicationGiven,
  monitoring,
  operationalPause,
  other,
}

extension IncidentConductActionWire on IncidentConductAction {
  String get wireValue => switch (this) {
    IncidentConductAction.firstAidApplied => 'first_aid_applied',
    IncidentConductAction.veterinaryReferral => 'veterinary_referral',
    IncidentConductAction.isolationRest => 'isolation_rest',
    IncidentConductAction.medicationGiven => 'medication_given',
    IncidentConductAction.monitoring => 'monitoring',
    IncidentConductAction.operationalPause => 'operational_pause',
    IncidentConductAction.other => 'other',
  };

  String get label => switch (this) {
    IncidentConductAction.firstAidApplied => 'Primeiros socorros aplicados',
    IncidentConductAction.veterinaryReferral => 'Encaminhamento veterinário',
    IncidentConductAction.isolationRest => 'Isolamento / Repouso',
    IncidentConductAction.medicationGiven => 'Medicação emergencial',
    IncidentConductAction.monitoring => 'Monitoramento contínuo',
    IncidentConductAction.operationalPause => 'Suspensão de atividade operacional',
    IncidentConductAction.other => 'Outra conduta',
  };

  static IncidentConductAction? tryFromWire(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final act in IncidentConductAction.values) {
      if (act.wireValue == normalized) return act;
    }
    return null;
  }
}

/// Profissional externo responsável ou referenciado na intercorrência.
final class IncidentProfessional {
  const IncidentProfessional({
    required this.name,
    this.registrationType,
    this.registrationNumber,
    this.clinic,
  });

  final String name;
  final String? registrationType;
  final String? registrationNumber;
  final String? clinic;

  bool get isEmpty => name.trim().isEmpty;

  Map<String, dynamic> toWire() {
    final wire = <String, dynamic>{'name': name.trim()};
    final regType = registrationType?.trim();
    if (regType != null && regType.isNotEmpty) {
      wire['registration_type'] = regType;
    }
    final regNum = registrationNumber?.trim();
    if (regNum != null && regNum.isNotEmpty) {
      wire['registration_number'] = regNum;
    }
    final c = clinic?.trim();
    if (c != null && c.isNotEmpty) {
      wire['clinic'] = c;
    }
    return wire;
  }
}

/// Comando tipado para registro de Intercorrência Clínica (F20.INTERCORRENCIA-V1).
final class ClinicalIncidentCommand {
  const ClinicalIncidentCommand({
    required this.dogId,
    required this.operationId,
    required this.finalizeOperationId,
    required this.occurredAt,
    required this.category,
    required this.severity,
    required this.description,
    this.initialConductNotes,
    this.conductActions = const <IncidentConductAction>{},
    this.hasOperationalImpact = false,
    this.caseId,
    this.caseTitle,
    this.professional,
  });

  final String dogId;
  final String operationId;
  final String finalizeOperationId;
  final DateTime occurredAt;
  final IncidentCategory category;
  final IncidentSeverity severity;
  final String description;
  final String? initialConductNotes;
  final Set<IncidentConductAction> conductActions;
  final bool hasOperationalImpact;
  final String? caseId;
  final String? caseTitle;
  final IncidentProfessional? professional;

  bool get opensNewCase => caseId == null;

  ClinicalEventType get eventType => ClinicalEventType.incident;
  PayloadType get payloadType => PayloadType.incidentV1;
  ClinicalCaseOpeningType get openingType => ClinicalCaseOpeningType.incident;

  Map<String, dynamic> buildContent() {
    final map = <String, dynamic>{
      'category': category.wireValue,
      'severity': severity.wireValue,
      'description': description.trim(),
      'has_operational_impact': hasOperationalImpact,
      'operational_impact_flag': hasOperationalImpact,
    };

    final conduct = initialConductNotes?.trim();
    if (conduct != null && conduct.isNotEmpty) {
      map['initial_conduct'] = conduct;
    }

    if (conductActions.isNotEmpty) {
      map['conduct_actions'] =
          conductActions.map((a) => a.wireValue).toList();
    }

    return map;
  }
}
