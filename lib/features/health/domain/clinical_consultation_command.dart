import 'package:canil_gcm/features/health/domain/health_v1_enums.dart';
import 'package:canil_gcm/features/health/domain/health_v1_enums_ext.dart';

/// Escore corporal observado na consulta.
enum ConsultationBodyCondition { excelente, bom, regular, ruim }

/// Estado de hidratação observado na consulta.
enum ConsultationHydration {
  normal,
  leveDesidratacao,
  moderada,
  severa,
}

/// Motivo da consulta (chips do mockup aprovado).
enum ConsultationReason {
  preventiva,
  retorno,
  emergencia,
  lesao,
  avaliacaoOperacional,
  outro,
}

/// Conclusão operacional registrada pela consulta.
///
/// **Evidência clínica apenas.** Não emite restrição, não muta readiness e não
/// cria projeção nesta entrega — ver `CLINICAL RECORDS MVP` §11.
enum ConsultationOperationalStatus {
  totalmenteApto,
  restrito,
  temporariamenteInapto,
}

/// Condutas/recomendações marcadas na consulta.
///
/// **Registro apenas.** Não cria `TreatmentProtocol`, `ExamProcess`,
/// `VaccinationRecord` nem `DoseAdministration` nesta entrega (§12).
enum ConsultationConduct {
  medicacaoPrescrita,
  exameLaboratorialSolicitado,
  exameImagemSolicitado,
  repousoNecessario,
  restricaoOperacional,
  vacinacaoIndicada,
  ajusteNutricional,
  outro,
}

extension ConsultationBodyConditionWire on ConsultationBodyCondition {
  String get wireValue => switch (this) {
    ConsultationBodyCondition.excelente => 'excelente',
    ConsultationBodyCondition.bom => 'bom',
    ConsultationBodyCondition.regular => 'regular',
    ConsultationBodyCondition.ruim => 'ruim',
  };

  String get label => switch (this) {
    ConsultationBodyCondition.excelente => 'Excelente',
    ConsultationBodyCondition.bom => 'Bom',
    ConsultationBodyCondition.regular => 'Regular',
    ConsultationBodyCondition.ruim => 'Ruim',
  };
}

extension ConsultationHydrationWire on ConsultationHydration {
  String get wireValue => switch (this) {
    ConsultationHydration.normal => 'normal',
    ConsultationHydration.leveDesidratacao => 'leve_desidratacao',
    ConsultationHydration.moderada => 'moderada',
    ConsultationHydration.severa => 'severa',
  };

  String get label => switch (this) {
    ConsultationHydration.normal => 'Normal',
    ConsultationHydration.leveDesidratacao => 'Leve desidratação',
    ConsultationHydration.moderada => 'Moderada',
    ConsultationHydration.severa => 'Severa',
  };
}

extension ConsultationReasonWire on ConsultationReason {
  String get wireValue => switch (this) {
    ConsultationReason.preventiva => 'preventiva',
    ConsultationReason.retorno => 'retorno',
    ConsultationReason.emergencia => 'emergencia',
    ConsultationReason.lesao => 'lesao',
    ConsultationReason.avaliacaoOperacional => 'avaliacao_operacional',
    ConsultationReason.outro => 'outro',
  };

  String get label => switch (this) {
    ConsultationReason.preventiva => 'Preventiva',
    ConsultationReason.retorno => 'Retorno',
    ConsultationReason.emergencia => 'Emergência',
    ConsultationReason.lesao => 'Lesão',
    ConsultationReason.avaliacaoOperacional => 'Avaliação operacional',
    ConsultationReason.outro => 'Outro',
  };
}

extension ConsultationOperationalStatusWire on ConsultationOperationalStatus {
  String get wireValue => switch (this) {
    ConsultationOperationalStatus.totalmenteApto => 'fully_fit',
    ConsultationOperationalStatus.restrito => 'restricted',
    ConsultationOperationalStatus.temporariamenteInapto => 'temporarily_unfit',
  };

  String get label => switch (this) {
    ConsultationOperationalStatus.totalmenteApto => 'Totalmente apto',
    ConsultationOperationalStatus.restrito => 'Restrito',
    ConsultationOperationalStatus.temporariamenteInapto =>
      'Temporariamente inapto',
  };
}

extension ConsultationConductWire on ConsultationConduct {
  String get wireValue => switch (this) {
    ConsultationConduct.medicacaoPrescrita => 'medication_prescribed',
    ConsultationConduct.exameLaboratorialSolicitado => 'lab_exam_requested',
    ConsultationConduct.exameImagemSolicitado => 'imaging_exam_requested',
    ConsultationConduct.repousoNecessario => 'rest_required',
    ConsultationConduct.restricaoOperacional => 'operational_restriction',
    ConsultationConduct.vacinacaoIndicada => 'vaccination_indicated',
    ConsultationConduct.ajusteNutricional => 'nutritional_adjustment',
    ConsultationConduct.outro => 'other',
  };

  String get label => switch (this) {
    ConsultationConduct.medicacaoPrescrita => 'Medicação prescrita',
    ConsultationConduct.exameLaboratorialSolicitado =>
      'Exame laboratorial solicitado',
    ConsultationConduct.exameImagemSolicitado => 'Exame de imagem solicitado',
    ConsultationConduct.repousoNecessario => 'Repouso necessário',
    ConsultationConduct.restricaoOperacional => 'Restrição operacional',
    ConsultationConduct.vacinacaoIndicada => 'Vacinação indicada',
    ConsultationConduct.ajusteNutricional => 'Ajuste nutricional',
    ConsultationConduct.outro => 'Outro',
  };
}

/// Identidade do profissional veterinário EXTERNO responsável pela decisão
/// clínica.
///
/// Deliberadamente distinta de `recorded_by`, que é o usuário interno K9 Ops
/// que digitou o registro. O backend nunca deriva um do outro
/// (`assertProfessional`, "Author != professional").
///
/// `name` é obrigatório quando o mapa é enviado; os demais são opcionais no
/// contrato atual.
final class ConsultationProfessional {
  const ConsultationProfessional({
    required this.name,
    this.registrationType,
    this.registrationNumber,
    this.clinic,
  });

  final String name;

  /// Ex.: `CRMV`. Tipo de registro profissional.
  final String? registrationType;

  /// Número do registro (ex.: `SP 14872`).
  final String? registrationNumber;

  /// Clínica ou local do atendimento.
  final String? clinic;

  bool get isEmpty => name.trim().isEmpty;

  /// Serializa no formato aceito por `assertProfessional`.
  ///
  /// Omite chaves ausentes/vazias: o backend rejeita string vazia e limita
  /// cada campo a `MAX_CASE_TITLE_LEN`.
  Map<String, dynamic> toWire() {
    final wire = <String, dynamic>{'name': name.trim()};
    void put(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        wire[key] = trimmed;
      }
    }

    put('registration_type', registrationType);
    put('registration_number', registrationNumber);
    put('clinic', clinic);
    return wire;
  }
}

/// Sinais vitais e medidas registrados na avaliação clínica.
///
/// Todos opcionais: uma consulta pode ser registrada sem aferição completa.
final class ConsultationVitals {
  const ConsultationVitals({
    this.bodyCondition,
    this.hydration,
    this.temperatureCelsius,
    this.heartRateBpm,
    this.respiratoryRateIrpm,
    this.weightKg,
  });

  final ConsultationBodyCondition? bodyCondition;
  final ConsultationHydration? hydration;
  final double? temperatureCelsius;
  final int? heartRateBpm;
  final int? respiratoryRateIrpm;
  final double? weightKg;

  /// Contribui apenas as chaves efetivamente preenchidas.
  void writeInto(Map<String, dynamic> content) {
    if (bodyCondition != null) {
      content['body_condition'] = bodyCondition!.wireValue;
    }
    if (hydration != null) {
      content['hydration'] = hydration!.wireValue;
    }
    if (temperatureCelsius != null) {
      content['temperature_celsius'] = temperatureCelsius;
    }
    if (heartRateBpm != null) {
      content['heart_rate_bpm'] = heartRateBpm;
    }
    if (respiratoryRateIrpm != null) {
      content['respiratory_rate_irpm'] = respiratoryRateIrpm;
    }
    if (weightKg != null) {
      content['weight_kg'] = weightKg;
    }
  }
}

/// Comando tipado de Consulta Veterinária canônica.
///
/// Substitui o `HealthLogModel` legado para `event_type = consultation`.
///
/// Intenção do usuário: **registrar uma consulta concluída**. Uma única ação
/// de salvar.
///
/// O transporte é deliberadamente invisível aqui. O source força
/// `CLINICAL_EVENT_INITIAL_STATUS = "draft"`, então o gateway orquestra duas
/// fases — criar (`Open`/`Append`) e finalizar (`Finalize`) — até o evento
/// atingir `status = final`. Esse detalhe pertence ao gateway, não ao domínio:
/// a UI não expõe rascunho.
final class ConsultationCommand {
  const ConsultationCommand({
    required this.dogId,
    required this.operationId,
    required this.finalizeOperationId,
    required this.occurredAt,
    required this.reason,
    required this.vitals,
    required this.conducts,
    this.caseId,
    this.caseTitle,
    this.veterinarianName,
    this.clinicOrLocation,
    this.reasonDetail,
    this.findings,
    this.diagnosis,
    this.conductNotes,
    this.operationalStatus,
    this.professional,
  });

  final String dogId;

  /// Token de idempotência da FASE DE CRIAÇÃO (`Open`/`Append`).
  ///
  /// Estável por tentativa de submit: um retry de transporte reenvia o mesmo
  /// valor para que o backend responda por replay em vez de criar um segundo
  /// fato clínico.
  final String operationId;

  /// Token de idempotência da FASE DE FINALIZAÇÃO (`Finalize`).
  ///
  /// Distinto do de criação: os recibos coexistem em
  /// `clinical_cases/{caseId}/operations/{operationId}` e cada comando valida
  /// o `kind` do recibo encontrado.
  final String finalizeOperationId;

  /// Instante clínico (data + hora da UI combinadas).
  ///
  /// O backend rejeita futuro além de 5 min de tolerância de clock
  /// (`assertOccurredAt`); nenhuma tolerância nova é inventada aqui.
  final DateTime occurredAt;

  final ConsultationReason reason;
  final ConsultationVitals vitals;
  final Set<ConsultationConduct> conducts;

  /// Caso alvo quando a consulta é anexada a um caso existente.
  ///
  /// `null` significa abrir um caso novo via `healthOpenClinicalCase`.
  final String? caseId;

  /// Título do caso, exigido apenas na abertura.
  final String? caseTitle;

  final String? veterinarianName;
  final String? clinicOrLocation;
  final String? reasonDetail;
  final String? findings;
  final String? diagnosis;
  final String? conductNotes;
  final ConsultationOperationalStatus? operationalStatus;
  final ConsultationProfessional? professional;

  /// `true` quando o comando abre um caso novo (Open-only).
  bool get opensNewCase => caseId == null;

  /// Tipo de evento canônico. Sempre `consultation`.
  ClinicalEventType get eventType => ClinicalEventType.consultation;

  /// Contrato do `content`. Sempre `consultation_v1`.
  PayloadType get payloadType => PayloadType.consultationV1;

  /// Motivo de abertura do caso quando aplicável.
  ClinicalCaseOpeningType get openingType =>
      ClinicalCaseOpeningType.consultation;

  /// Constrói o mapa `content` de `consultation_v1`.
  ///
  /// Somente chaves preenchidas são incluídas. O backend exige `content` não
  /// vazio, com no máximo 100 chaves e 64 KiB — o motivo garante que nunca
  /// enviamos um mapa vazio.
  Map<String, dynamic> buildContent() {
    final content = <String, dynamic>{'reason': reason.wireValue};

    void put(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        content[key] = trimmed;
      }
    }

    put('reason_detail', reasonDetail);
    put('veterinarian_name', veterinarianName);
    put('clinic_or_location', clinicOrLocation);
    put('findings', findings);
    put('diagnosis', diagnosis);
    put('conduct_notes', conductNotes);

    vitals.writeInto(content);

    if (conducts.isNotEmpty) {
      final ordered = ConsultationConduct.values
          .where(conducts.contains)
          .map((c) => c.wireValue)
          .toList(growable: false);
      content['conducts'] = ordered;
    }

    if (operationalStatus != null) {
      // Evidência clínica. Nenhum efeito automático em readiness (§11).
      content['operational_status'] = operationalStatus!.wireValue;
    }

    return content;
  }
}
