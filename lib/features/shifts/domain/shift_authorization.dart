/// HEALTH-V1-OP-AUTH — contrato de autorização operacional no Mobile.
///
/// O Mobile NÃO decide se uma operação é autorizada. Ele envia a intenção,
/// recebe a decisão do backend e a apresenta. A autoridade é
/// `dogs/{dogId}/operational_restrictions` consultada server-side; nem o badge
/// de Prontidão, nem `health_summary/current`, nem cálculo local participam.
///
/// Este arquivo existe para que a decisão do backend tenha um tipo próprio no
/// Mobile: sem isso, a camada de UI voltaria a interpretar strings de erro, que
/// é exatamente como um bloqueio clínico virava "confira sua conexão".
library;

/// Ação operacional crítica que introduz ou substitui o K9 em turno.
enum ShiftAuthorizedAction {
  startShift('start_shift'),
  switchDog('switch_dog'),
  assumeVehicle('assume_vehicle');

  const ShiftAuthorizedAction(this.wireValue);

  final String wireValue;
}

/// Nível da restrição, no formato de wire canônico.
enum ShiftRestrictionLevel {
  absolute('absolute'),
  partial('partial'),
  attention('attention');

  const ShiftRestrictionLevel(this.wireValue);

  final String wireValue;

  static ShiftRestrictionLevel? tryParse(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final level in ShiftRestrictionLevel.values) {
      if (level.wireValue == value) return level;
    }
    // Nível desconhecido NÃO é rebaixado para `attention`: quem consome trata
    // como desconhecido e o backend já falhou fechado antes de chegar aqui.
    return null;
  }
}

/// Restrição ativa, como o backend a projeta para exibição.
///
/// Não carrega identificação do profissional externo nem o documento-fonte —
/// são PII e o operador não precisa deles para cumprir a restrição.
final class ShiftRestrictionInfo {
  const ShiftRestrictionInfo({
    required this.id,
    required this.level,
    required this.category,
    required this.description,
    required this.activitiesRestricted,
    required this.expectedEnd,
    required this.isOverdue,
  });

  final String id;
  final ShiftRestrictionLevel? level;
  final String category;
  final String description;
  final List<String> activitiesRestricted;
  final DateTime? expectedEnd;

  /// `expected_end` no passado com a restrição ainda ativa.
  ///
  /// Sinaliza reavaliação pendente e NÃO encerra a restrição.
  final bool isOverdue;

  static ShiftRestrictionInfo? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = map['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final activities = map['activitiesRestricted'];
    final expectedEndRaw = map['expectedEndIso'];
    return ShiftRestrictionInfo(
      id: id.trim(),
      level: ShiftRestrictionLevel.tryParse(map['level'] as String?),
      category: (map['category'] as String?)?.trim() ?? 'other',
      description: (map['description'] as String?)?.trim() ?? '',
      activitiesRestricted: activities is List
          ? activities
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      expectedEnd: expectedEndRaw is String
          ? DateTime.tryParse(expectedEndRaw)
          : null,
      isOverdue: map['isOverdue'] == true,
    );
  }
}

/// Decisão do backend para uma ação operacional crítica.
enum ShiftAuthorizationOutcome {
  /// Autorizada, sem restrição ativa relevante.
  allowed,

  /// Autorizada com restrições ativas informativas (`attention`).
  allowedWithNotice,

  /// Autorizada apenas após ciência registrada de restrição parcial.
  allowedWithRestrictions,
}

/// Resultado de uma operação executada pelo backend.
final class ShiftAuthorizationResult {
  const ShiftAuthorizationResult({
    required this.action,
    required this.dogId,
    required this.outcome,
    required this.restrictions,
    required this.acknowledgementRecorded,
    required this.shiftId,
    required this.wasNoOp,
  });

  final ShiftAuthorizedAction action;
  final String dogId;
  final ShiftAuthorizationOutcome outcome;
  final List<ShiftRestrictionInfo> restrictions;
  final bool acknowledgementRecorded;
  final String? shiftId;
  final bool wasNoOp;

  /// Restrições que valem exibir como aviso não bloqueante.
  List<ShiftRestrictionInfo> get noticeRestrictions => restrictions
      .where((restriction) => restriction.level != ShiftRestrictionLevel.absolute)
      .toList(growable: false);
}

/// Natureza de uma negativa. Cada caso exige UX diferente.
enum ShiftAuthorizationFailureKind {
  /// Restrição absoluta ativa. Bloqueio clínico definitivo, sem bypass.
  absoluteRestriction,

  /// Restrição parcial exige ciência explícita do responsável antes de operar.
  acknowledgementRequired,

  /// Atividade solicitada está restrita por uma restrição parcial.
  activityRestricted,

  /// Não foi possível verificar as restrições canônicas.
  ///
  /// FAIL-CLOSED: jamais tratar como "sem restrição". É diferente de falha de
  /// conectividade — aqui o servidor respondeu e disse que não sabe.
  restrictionsUnavailable,

  /// Estado operacional incompatível (sem turno ativo, guarnição já com K9).
  invalidState,

  /// Chamador não autenticado.
  unauthenticated,

  /// Chamador sem acesso ao K9 ou ao turno.
  permissionDenied,

  /// K9 não encontrado.
  notFound,

  /// Payload inválido.
  invalidArgument,

  /// Conflito de idempotência.
  idempotencyConflict,

  /// Falha real de rede/conectividade.
  network,

  /// Falha interna não classificada.
  internal,
}

/// Falha de uma ação operacional crítica.
final class ShiftAuthorizationFailure implements Exception {
  const ShiftAuthorizationFailure(
    this.kind,
    this.message, {
    this.restrictions = const <ShiftRestrictionInfo>[],
    this.pendingAcknowledgementIds = const <String>[],
    this.reasonCode,
  });

  final ShiftAuthorizationFailureKind kind;
  final String message;
  final List<ShiftRestrictionInfo> restrictions;
  final List<String> pendingAcknowledgementIds;
  final String? reasonCode;

  /// True quando a operação está definitivamente barrada por decisão clínica.
  ///
  /// A UI NÃO pode oferecer "continuar mesmo assim" nesse caso.
  bool get isClinicalBlock =>
      kind == ShiftAuthorizationFailureKind.absoluteRestriction ||
      kind == ShiftAuthorizationFailureKind.activityRestricted;

  /// Restrições parciais que o responsável precisa reconhecer.
  List<ShiftRestrictionInfo> get partialRestrictions => restrictions
      .where((restriction) => restriction.level == ShiftRestrictionLevel.partial)
      .toList(growable: false);

  @override
  String toString() => 'ShiftAuthorizationFailure(${kind.name}): $message';
}

/// Comando enviado ao mutation owner autoritativo.
final class ShiftAuthorizationCommand {
  const ShiftAuthorizationCommand({
    required this.action,
    required this.dogId,
    required this.operationId,
    this.acknowledgedRestrictionIds = const <String>[],
    this.startedAt,
    this.handlerName,
    this.shiftGroupId,
    this.shiftGroupCode,
    this.shiftGroupLabel,
    this.vehicle,
    this.role,
  });

  final ShiftAuthorizedAction action;
  final String dogId;

  /// Chave de idempotência. Estável entre a primeira tentativa e o reenvio com
  /// ciência, para que o aceite não abra um segundo turno.
  final String operationId;

  final List<String> acknowledgedRestrictionIds;
  final DateTime? startedAt;
  final String? handlerName;
  final String? shiftGroupId;
  final String? shiftGroupCode;
  final String? shiftGroupLabel;
  final ShiftAuthorizationVehicle? vehicle;
  final String? role;

  /// Reenvio da MESMA operação, agora com a ciência do responsável.
  ShiftAuthorizationCommand acknowledging(List<String> restrictionIds) {
    return ShiftAuthorizationCommand(
      action: action,
      dogId: dogId,
      operationId: operationId,
      acknowledgedRestrictionIds: restrictionIds,
      startedAt: startedAt,
      handlerName: handlerName,
      shiftGroupId: shiftGroupId,
      shiftGroupCode: shiftGroupCode,
      shiftGroupLabel: shiftGroupLabel,
      vehicle: vehicle,
      role: role,
    );
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'action': action.wireValue,
      'dogId': dogId,
      'operationId': operationId,
      if (acknowledgedRestrictionIds.isNotEmpty)
        'acknowledgedRestrictionIds': acknowledgedRestrictionIds,
      if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
      if (handlerName != null) 'handlerName': handlerName,
      if (shiftGroupId != null) 'shiftGroupId': shiftGroupId,
      if (shiftGroupCode != null) 'shiftGroupCode': shiftGroupCode,
      if (shiftGroupLabel != null) 'shiftGroupLabel': shiftGroupLabel,
      if (role != null) 'role': role,
      if (vehicle != null) 'vehicle': vehicle!.toPayload(),
    };
  }
}

/// Viatura, no shape aceito pelo callable.
final class ShiftAuthorizationVehicle {
  const ShiftAuthorizationVehicle({
    required this.id,
    this.label,
    this.prefix,
    this.modelName,
    this.unit,
    this.crewSize,
  });

  final String id;
  final String? label;
  final String? prefix;
  final String? modelName;
  final String? unit;
  final int? crewSize;

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'id': id,
      if (label != null) 'label': label,
      if (prefix != null) 'prefix': prefix,
      if (modelName != null) 'modelName': modelName,
      if (unit != null) 'unit': unit,
      if (crewSize != null) 'crewSize': crewSize,
    };
  }
}

/// Boundary autoritativa. Implementada pelo gateway de Cloud Functions.
abstract interface class ShiftAuthorizationGateway {
  Future<ShiftAuthorizationResult> execute(ShiftAuthorizationCommand command);
}
