import 'dart:math';

/// Par de identidades de operação de UMA tentativa de salvar consulta.
///
/// Load-bearing: as duas fases (criar + finalizar) precisam de IDs
/// **estáveis por tentativa**. Um retry de transporte reenvia o MESMO ID,
/// para que o backend responda por replay em vez de criar um segundo fato
/// clínico. Gerar um ID novo num retry produziria consulta duplicada.
final class ConsultationOperationIds {
  const ConsultationOperationIds({
    required this.createOperationId,
    required this.finalizeOperationId,
  });

  /// `operationId` de `healthOpenClinicalCase` / `healthAppendClinicalEvent`.
  final String createOperationId;

  /// `operationId` de `healthFinalizeClinicalEvent`.
  ///
  /// Distinto do de criação: os recibos vivem no mesmo
  /// `clinical_cases/{caseId}/operations/{operationId}` e cada comando valida
  /// o `kind` do recibo encontrado. Reutilizar o mesmo ID faria a finalização
  /// colidir com o recibo de criação.
  final String finalizeOperationId;
}

/// Gera identidades de operação compatíveis com o normalizador do backend.
///
/// Formato: `<prefix>_<millis>_<random>` — sempre dentro de
/// `OPERATION_ID_SAFE_PATTERN` (`^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`) e do
/// limite de 128 caracteres.
abstract final class ConsultationOperationIdFactory {
  ConsultationOperationIdFactory._();

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Cria o par para uma nova tentativa de submit.
  ///
  /// Chamar UMA vez por tentativa e reter o resultado enquanto a tentativa
  /// estiver viva.
  static ConsultationOperationIds forAttempt({
    DateTime? now,
    Random? random,
  }) {
    final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final suffix = _suffix(random ?? Random());
    return ConsultationOperationIds(
      createOperationId: 'consult_create_${millis}_$suffix',
      finalizeOperationId: 'consult_final_${millis}_$suffix',
    );
  }

  static String _suffix(Random random) {
    return List<String>.generate(
      8,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
      growable: false,
    ).join();
  }
}
