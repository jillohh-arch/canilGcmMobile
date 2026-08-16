import '../../domain/health_v1_enums_ext.dart';
import '../../domain/health_v1_value_objects.dart';

/// Rótulo humano do tipo de registro profissional.
///
/// Os `wireName` são siglas de conselho e já são legíveis; o rótulo só
/// acrescenta a leitura por extenso onde ajuda.
String healthRegistrationTypeLabel(ProfessionalRegistrationType type) {
  return switch (type) {
    ProfessionalRegistrationType.crmv => 'CRMV',
    ProfessionalRegistrationType.crmvZ => 'CRMV-Z',
    ProfessionalRegistrationType.crn => 'CRN',
    ProfessionalRegistrationType.crf => 'CRF',
    ProfessionalRegistrationType.cfmv => 'CFMV',
    ProfessionalRegistrationType.other => 'Outro',
  };
}

/// Ordem de apresentação. CRMV primeiro por frequência — mas **nunca**
/// pré-selecionado: o tipo de conselho é afirmação do operador, não default.
const List<ProfessionalRegistrationType> kHealthRegistrationTypeOrder =
    <ProfessionalRegistrationType>[
      ProfessionalRegistrationType.crmv,
      ProfessionalRegistrationType.crmvZ,
      ProfessionalRegistrationType.cfmv,
      ProfessionalRegistrationType.crn,
      ProfessionalRegistrationType.crf,
      ProfessionalRegistrationType.other,
    ];

/// Rascunho da identidade profissional, como está na tela.
///
/// Separado do widget para que a conversão para o value object canônico seja
/// testável sem bombear a árvore de widgets. Deliberadamente NÃO usa os campos
/// legados (`vetName`, `professionalCrmv`, `professionalClinic`).
final class HealthProfessionalDraft {
  const HealthProfessionalDraft({
    this.name = '',
    this.registrationType,
    this.registrationNumber = '',
    this.clinic = '',
    this.specialty = '',
  });

  final String name;

  /// `null` = nada escolhido ainda. É o estado inicial.
  final ProfessionalRegistrationType? registrationType;
  final String registrationNumber;
  final String clinic;
  final String specialty;

  HealthProfessionalDraft copyWith({
    String? name,
    ProfessionalRegistrationType? registrationType,
    String? registrationNumber,
    String? clinic,
    String? specialty,
  }) {
    return HealthProfessionalDraft(
      name: name ?? this.name,
      registrationType: registrationType ?? this.registrationType,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      clinic: clinic ?? this.clinic,
      specialty: specialty ?? this.specialty,
    );
  }

  /// Primeira mensagem de erro, ou `null` quando válido.
  ///
  /// Ordem de checagem segue a ordem visual dos campos, para que o operador
  /// seja levado ao primeiro problema de cima para baixo.
  String? validationError() {
    if (name.trim().isEmpty) {
      return 'Informe o nome do profissional responsável.';
    }
    if (registrationType == null) {
      return 'Selecione o tipo de registro profissional.';
    }
    if (registrationNumber.trim().isEmpty) {
      return 'Informe o número do registro profissional.';
    }
    if (clinic.trim().isEmpty) {
      return 'Informe a clínica ou instituição.';
    }
    return null;
  }

  bool get isValid => validationError() == null;

  /// Converte para o value object canônico. Só chamar quando [isValid].
  ProfessionalIdentity toProfessionalIdentity() {
    final error = validationError();
    if (error != null) {
      throw StateError('Rascunho profissional inválido: $error');
    }
    final trimmedSpecialty = specialty.trim();
    return ProfessionalIdentity(
      name: name.trim(),
      registrationType: registrationType!,
      registrationNumber: registrationNumber.trim(),
      clinic: clinic.trim(),
      specialty: trimmedSpecialty.isEmpty ? null : trimmedSpecialty,
    );
  }
}
