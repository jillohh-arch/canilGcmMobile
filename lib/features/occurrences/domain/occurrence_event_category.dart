enum OccurrenceEventCategory {
  opening,
  arrival,
  approach,
  dogWork,
  positiveIndication,
  seizure,
  closure,
  other;

  String toMap() => switch (this) {
    opening => 'opening',
    arrival => 'arrival',
    approach => 'approach',
    dogWork => 'dog_work',
    positiveIndication => 'positive_indication',
    seizure => 'seizure',
    closure => 'closure',
    other => 'other',
  };

  static OccurrenceEventCategory fromMap(String? value) => switch (value) {
    'opening' => OccurrenceEventCategory.opening,
    'arrival' => OccurrenceEventCategory.arrival,
    'approach' => OccurrenceEventCategory.approach,
    'dog_work' => OccurrenceEventCategory.dogWork,
    'positive_indication' => OccurrenceEventCategory.positiveIndication,
    'seizure' => OccurrenceEventCategory.seizure,
    'closure' => OccurrenceEventCategory.closure,
    _ => OccurrenceEventCategory.other,
  };

  String get label => switch (this) {
    opening => 'Abertura do registro',
    arrival => 'Chegada à cena',
    approach => 'Abordagem',
    dogWork => 'Trabalho do Cão',
    positiveIndication => 'Indicação Positiva',
    seizure => 'Apreensão',
    closure => 'Encerramento',
    other => 'Outro',
  };
}
