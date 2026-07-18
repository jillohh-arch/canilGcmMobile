import 'package:canil_gcm/features/health/domain/health_v1_models.dart';

/// Revisão opaca para optimistic concurrency (neutra de backend).
///
/// Não é `DocumentSnapshot`, nem `Timestamp` Firestore.
/// Backend materializa como contador monotônico; o domínio carrega token string.
final class HealthScheduleRevision {
  const HealthScheduleRevision(this.token);

  /// Token opaco (não vazio em comandos de update).
  final String token;

  /// Atalho: revisão numérica serializada (`0`, `1`, …).
  factory HealthScheduleRevision.numeric(int value) {
    if (value < 0) {
      throw const HealthDomainException(
        'invalid_revision',
        'revisão numérica não pode ser negativa',
      );
    }
    return HealthScheduleRevision('$value');
  }

  /// Próxima revisão após mutação bem-sucedida (helper de teste/engine).
  HealthScheduleRevision nextNumeric() {
    final n = int.tryParse(token);
    if (n == null) {
      throw const HealthDomainException(
        'invalid_revision',
        'nextNumeric exige token numérico',
      );
    }
    return HealthScheduleRevision.numeric(n + 1);
  }

  /// Parse wire numérico (camada data). Retorna null se token não for inteiro ≥ 0.
  int? tryAsNonNegativeInt() {
    final n = int.tryParse(token.trim());
    if (n == null || n < 0) return null;
    return n;
  }

  @override
  bool operator ==(Object other) =>
      other is HealthScheduleRevision && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'HealthScheduleRevision($token)';
}
