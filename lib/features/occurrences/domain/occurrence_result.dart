enum OccurrenceResult {
  drugSeized,
  weaponSeized,
  personDetained,
  boCreated,
  noOccurrence,
  supportProvided;

  String toMap() => switch (this) {
    drugSeized => 'drug_seized',
    weaponSeized => 'weapon_seized',
    personDetained => 'person_detained',
    boCreated => 'bo_created',
    noOccurrence => 'no_occurrence',
    supportProvided => 'support_provided',
  };

  static OccurrenceResult fromMap(String? value) => switch (value) {
    'drug_seized' => OccurrenceResult.drugSeized,
    'weapon_seized' => OccurrenceResult.weaponSeized,
    'person_detained' => OccurrenceResult.personDetained,
    'bo_created' => OccurrenceResult.boCreated,
    'no_occurrence' => OccurrenceResult.noOccurrence,
    'support_provided' => OccurrenceResult.supportProvided,
    _ => OccurrenceResult.noOccurrence,
  };

  String get label => switch (this) {
    drugSeized => 'Droga apreendida',
    weaponSeized => 'Arma apreendida',
    personDetained => 'Pessoa detida',
    boCreated => 'BO registrado',
    noOccurrence => 'Sem constatação',
    supportProvided => 'Apoio prestado',
  };
}
