import 'package:canil_gcm/features/health/data/clinical/clinical_consultation_operation_ids.dart';
import 'package:canil_gcm/features/health/domain/clinical_consultation_command.dart';

/// Estado puro do formulário de Consulta Veterinária.
///
/// Separado do widget para que a validação e o mapeamento para
/// [ConsultationCommand] sejam testáveis sem bombear frames.
final class ConsultationFormState {
  ConsultationFormState({DateTime? occurredAt})
    : occurredAt = occurredAt ?? DateTime.now();

  /// Data + hora do atendimento, combinadas num único instante.
  DateTime occurredAt;

  /// Caso alvo. `null` = abrir novo caso.
  String? selectedCaseId;

  /// `true` quando o usuário escolheu explicitamente "Abrir novo caso".
  bool openNewCase = false;

  ConsultationReason? reason;
  String veterinarianName = '';
  String clinicOrLocation = '';
  String findings = '';
  String diagnosis = '';
  String conductNotes = '';

  ConsultationBodyCondition? bodyCondition;
  ConsultationHydration? hydration;
  String temperatureCelsius = '';
  String heartRateBpm = '';
  String respiratoryRateIrpm = '';
  String weightKg = '';

  final Set<ConsultationConduct> conducts = <ConsultationConduct>{};
  ConsultationOperationalStatus? operationalStatus;

  String professionalRegistrationType = 'CRMV';
  String professionalRegistrationNumber = '';

  /// Identidades de operação da tentativa de submit ATIVA.
  ///
  /// Criadas uma única vez por tentativa e retidas: um retry de transporte
  /// precisa reenviar os MESMOS ids para não duplicar a consulta.
  ConsultationOperationIds? _activeAttempt;

  ConsultationOperationIds beginAttempt({DateTime? now}) {
    return _activeAttempt ??= ConsultationOperationIdFactory.forAttempt(
      now: now,
    );
  }

  /// Encerra a tentativa ativa após sucesso confirmado.
  void completeAttempt() => _activeAttempt = null;

  ConsultationOperationIds? get activeAttempt => _activeAttempt;

  /// Uma consulta precisa de um destino inequívoco.
  ///
  /// Regra de produto: com múltiplos casos utilizáveis, exigir escolha
  /// explícita; sem casos, "Abrir novo caso" é o caminho natural.
  bool get hasCaseTarget => openNewCase || selectedCaseId != null;

  /// Mensagem de validação, ou `null` quando o formulário pode ser enviado.
  ///
  /// Mantida deliberadamente enxuta: o backend é a autoridade final de
  /// contrato. Aqui só barramos o que tornaria a chamada inútil.
  String? validate() {
    if (!hasCaseTarget) {
      return 'Selecione o caso clínico ou escolha abrir um novo caso.';
    }
    if (reason == null) {
      return 'Informe o motivo da consulta.';
    }
    // `occurred_at` não pode estar no futuro (assertOccurredAt, 5 min de
    // tolerância de clock no servidor). Barrar aqui evita uma ida perdida.
    if (occurredAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return 'A data e hora da consulta não podem estar no futuro.';
    }
    final temperature = _optionalDouble(temperatureCelsius);
    if (temperature == false) {
      return 'Temperatura inválida.';
    }
    final heart = _optionalInt(heartRateBpm);
    if (heart == false) {
      return 'Frequência cardíaca inválida.';
    }
    final respiratory = _optionalInt(respiratoryRateIrpm);
    if (respiratory == false) {
      return 'Frequência respiratória inválida.';
    }
    final weight = _optionalDouble(weightKg);
    if (weight == false) {
      return 'Peso inválido.';
    }
    return null;
  }

  /// Monta o comando canônico.
  ///
  /// Só chamar depois de [validate] retornar `null`.
  ConsultationCommand toCommand({required String dogId, DateTime? now}) {
    final ids = beginAttempt(now: now);
    final vetName = veterinarianName.trim();
    return ConsultationCommand(
      dogId: dogId,
      operationId: ids.createOperationId,
      finalizeOperationId: ids.finalizeOperationId,
      occurredAt: occurredAt,
      reason: reason!,
      vitals: ConsultationVitals(
        bodyCondition: bodyCondition,
        hydration: hydration,
        temperatureCelsius: _parseDouble(temperatureCelsius),
        heartRateBpm: _parseInt(heartRateBpm),
        respiratoryRateIrpm: _parseInt(respiratoryRateIrpm),
        weightKg: _parseDouble(weightKg),
      ),
      conducts: Set<ConsultationConduct>.of(conducts),
      caseId: openNewCase ? null : selectedCaseId,
      veterinarianName: vetName.isEmpty ? null : vetName,
      clinicOrLocation: _nullIfEmpty(clinicOrLocation),
      findings: _nullIfEmpty(findings),
      diagnosis: _nullIfEmpty(diagnosis),
      conductNotes: _nullIfEmpty(conductNotes),
      operationalStatus: operationalStatus,
      // ProfessionalIdentity só é enviada quando há um nome real: o contrato
      // exige `professional.name`, e não inventamos um profissional a partir
      // do usuário interno que digitou.
      professional: vetName.isEmpty
          ? null
          : ConsultationProfessional(
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

  static double? _parseDouble(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  static int? _parseInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  /// `null` = ausente (ok), `false` = presente e inválido.
  static Object? _optionalDouble(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed) ?? false;
  }

  static Object? _optionalInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed) ?? false;
  }
}
