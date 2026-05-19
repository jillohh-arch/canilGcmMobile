enum OccurrenceStatus {
  inProgress,
  finalizing,
  finalized,
  canceled;

  String toMap() => switch (this) {
        inProgress => 'in_progress',
        finalizing => 'finalizing',
        finalized => 'finalized',
        canceled => 'canceled',
      };

  static OccurrenceStatus fromMap(String? value) => switch (value) {
        'in_progress' => OccurrenceStatus.inProgress,
        'finalizing' => OccurrenceStatus.finalizing,
        'finalized' => OccurrenceStatus.finalized,
        'canceled' => OccurrenceStatus.canceled,
        _ => OccurrenceStatus.inProgress,
      };

  bool get isOpen => this == inProgress || this == finalizing;
  bool get isClosed => this == finalized || this == canceled;
}
