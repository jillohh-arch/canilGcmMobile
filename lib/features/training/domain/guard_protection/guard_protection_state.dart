/// Estado dos impulsos de Guarda & Proteção do cão.
/// Subcoleção: /dogs/{dogId}/guard_protection_state/{stateId}
class GuardProtectionState {
  final String? id;
  final String
  cacaImpulse; // 'not_started' | 'opening' | 'developing' | 'consolidated'
  final String defesaImpulse;
  final String agressaoImpulse;
  final List<TechnicalCapability> technicalCapabilities;
  final List<SpecialtyCommand> specialtyCommands;

  GuardProtectionState({
    this.id,
    this.cacaImpulse = 'not_started',
    this.defesaImpulse = 'not_started',
    this.agressaoImpulse = 'not_started',
    this.technicalCapabilities = const [],
    this.specialtyCommands = const [],
  });

  factory GuardProtectionState.fromJson(
    Map<String, dynamic> json, {
    String? docId,
  }) {
    return GuardProtectionState(
      id: docId ?? json['id'] as String?,
      cacaImpulse: json['caca_impulse'] as String? ?? 'not_started',
      defesaImpulse: json['defesa_impulse'] as String? ?? 'not_started',
      agressaoImpulse: json['agressao_impulse'] as String? ?? 'not_started',
      technicalCapabilities:
          (json['technical_capabilities'] as List<dynamic>?)
              ?.map(
                (e) => TechnicalCapability.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      specialtyCommands:
          (json['specialty_commands'] as List<dynamic>?)
              ?.map((e) => SpecialtyCommand.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caca_impulse': cacaImpulse,
      'defesa_impulse': defesaImpulse,
      'agressao_impulse': agressaoImpulse,
      'technical_capabilities': technicalCapabilities
          .map((e) => e.toJson())
          .toList(),
      'specialty_commands': specialtyCommands.map((e) => e.toJson()).toList(),
    };
  }

  GuardProtectionState copyWith({
    String? id,
    String? cacaImpulse,
    String? defesaImpulse,
    String? agressaoImpulse,
    List<TechnicalCapability>? technicalCapabilities,
    List<SpecialtyCommand>? specialtyCommands,
  }) {
    return GuardProtectionState(
      id: id ?? this.id,
      cacaImpulse: cacaImpulse ?? this.cacaImpulse,
      defesaImpulse: defesaImpulse ?? this.defesaImpulse,
      agressaoImpulse: agressaoImpulse ?? this.agressaoImpulse,
      technicalCapabilities:
          technicalCapabilities ?? this.technicalCapabilities,
      specialtyCommands: specialtyCommands ?? this.specialtyCommands,
    );
  }

  static const List<String> impulseStages = [
    'not_started',
    'opening',
    'developing',
    'consolidated',
  ];
}

class TechnicalCapability {
  final String name;
  final String state; // 'not_started' | 'developing' | 'consolidated'

  TechnicalCapability({required this.name, this.state = 'not_started'});

  factory TechnicalCapability.fromJson(Map<String, dynamic> json) {
    return TechnicalCapability(
      name: json['name'] as String? ?? '',
      state: json['state'] as String? ?? 'not_started',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'state': state};
}

class SpecialtyCommand {
  final String name;
  final String
  stage; // 'not_trained' | 'introduced' | 'developing' | 'consolidated'

  SpecialtyCommand({required this.name, this.stage = 'not_trained'});

  factory SpecialtyCommand.fromJson(Map<String, dynamic> json) {
    return SpecialtyCommand(
      name: json['name'] as String? ?? '',
      stage: json['stage'] as String? ?? 'not_trained',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'stage': stage};
}
