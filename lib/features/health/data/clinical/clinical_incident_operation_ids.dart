import 'dart:math';

final class IncidentOperationIds {
  const IncidentOperationIds({
    required this.createOperationId,
    required this.finalizeOperationId,
  });

  final String createOperationId;
  final String finalizeOperationId;
}

abstract final class IncidentOperationIdFactory {
  IncidentOperationIdFactory._();

  static const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  static IncidentOperationIds forAttempt({
    DateTime? now,
    Random? random,
  }) {
    final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final suffix = _suffix(random ?? Random());
    return IncidentOperationIds(
      createOperationId: 'inc_create_${millis}_$suffix',
      finalizeOperationId: 'inc_final_${millis}_$suffix',
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
