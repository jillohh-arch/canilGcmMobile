enum OccurrenceStatus {
  inProgress,
  finalizing,
  awaitingSignatures,
  finalized,
  finalizedWithPending,
  canceled;

  String toMap() => switch (this) {
    inProgress => 'in_progress',
    finalizing => 'finalizing',
    awaitingSignatures => 'awaiting_signatures',
    finalized => 'finalized',
    finalizedWithPending => 'finalized_with_pending',
    canceled => 'canceled',
  };

  static OccurrenceStatus fromMap(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return OccurrenceStatus.inProgress;
    }
    if (normalized == 'in_progress' ||
        normalized.contains('andamento') ||
        normalized == 'aberta' ||
        normalized == 'aberto') {
      return OccurrenceStatus.inProgress;
    }
    if (normalized == 'finalizing' || normalized.contains('finalizando')) {
      return OccurrenceStatus.finalizing;
    }
    if (normalized == 'awaiting_signatures' ||
        normalized.contains('aguardando assinatura')) {
      return OccurrenceStatus.awaitingSignatures;
    }
    if (normalized == 'finalized_with_pending' ||
        normalized.contains('finalizado com pendencia') ||
        normalized.contains('finalizado com pendência')) {
      return OccurrenceStatus.finalizedWithPending;
    }
    if (normalized == 'finalized' ||
        normalized.contains('finaliz') ||
        normalized.contains('conclu')) {
      return OccurrenceStatus.finalized;
    }
    if (normalized == 'canceled' ||
        normalized == 'cancelled' ||
        normalized.contains('cancel')) {
      return OccurrenceStatus.canceled;
    }
    return OccurrenceStatus.inProgress;
  }

  bool get isOpen => this == inProgress || this == finalizing;
  bool get isClosed =>
      this == finalized || this == finalizedWithPending || this == canceled;
}
