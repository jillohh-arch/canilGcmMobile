class Dog {
  final String id;
  final String name;
  final String breed;
  final String sex; // 'M' = Macho, 'F' = Fêmea
  final DateTime dateOfBirth;
  final String status; // 'Ativo', 'Licença', 'Aposentado'
  final String? profileImageUrl;
  final String? conductorRa;
  final DateTime? lastTrainingDate;
  final DateTime? lastVaccineDate;
  final double? weight;
  final String? registrationNumber; // Matrícula / N° de Patrimônio
  final double? idealWeightMin;
  final double? idealWeightMax;
  final DateTime? lastBathDate;
  final Map<String, dynamic>? readinessStreak;
  final List<String>? specialties;
  final String? cor;
  final String? microchip;
  final String? observacoes;
  final String? condicaoCorporal;

  Dog({
    required this.id,
    required this.name,
    required this.breed,
    this.sex = 'M',
    required this.dateOfBirth,
    this.status = 'Ativo',
    this.profileImageUrl,
    this.conductorRa,
    this.lastTrainingDate,
    this.lastVaccineDate,
    this.weight,
    this.registrationNumber,
    this.idealWeightMin,
    this.idealWeightMax,
    this.lastBathDate,
    this.readinessStreak,
    this.specialties,
    this.cor,
    this.microchip,
    this.observacoes,
    this.condicaoCorporal,
  });

  factory Dog.fromJson(Map<String, dynamic> json) {
    return Dog(
      id: json['id'],
      name: json['name'],
      breed: json['breed'],
      sex: json['sex'] ?? 'M',
      dateOfBirth: DateTime.parse(json['dateOfBirth']),
      status: json['status'] ?? 'Ativo',
      profileImageUrl: json['profileImageUrl'],
      conductorRa: json['conductorRa'],
      lastTrainingDate: json['lastTrainingDate'] != null
          ? DateTime.parse(json['lastTrainingDate'])
          : null,
      lastVaccineDate: json['lastVaccineDate'] != null
          ? DateTime.parse(json['lastVaccineDate'])
          : null,
      weight: json['weight'] != null
          ? (json['weight'] as num).toDouble()
          : null,
      registrationNumber: json['registrationNumber'],
      idealWeightMin: json['idealWeightMin'] != null
          ? (json['idealWeightMin'] as num).toDouble()
          : null,
      idealWeightMax: json['idealWeightMax'] != null
          ? (json['idealWeightMax'] as num).toDouble()
          : null,
      lastBathDate: json['lastBathDate'] != null
          ? DateTime.parse(json['lastBathDate'])
          : null,
      readinessStreak: json['readinessStreak'],
      specialties: json['specialties'] != null
          ? List<String>.from(json['specialties'] as List)
          : null,
      cor: json['cor'],
      microchip: json['microchip'],
      observacoes: json['observacoes'],
      condicaoCorporal: json['condicaoCorporal'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'breed': breed,
      'sex': sex,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'status': status,
      'profileImageUrl': profileImageUrl,
      'conductorRa': conductorRa,
      if (lastTrainingDate != null)
        'lastTrainingDate': lastTrainingDate!.toIso8601String(),
      if (lastVaccineDate != null)
        'lastVaccineDate': lastVaccineDate!.toIso8601String(),
      if (weight != null) 'weight': weight,
      if (registrationNumber != null) 'registrationNumber': registrationNumber,
      if (idealWeightMin != null) 'idealWeightMin': idealWeightMin,
      if (idealWeightMax != null) 'idealWeightMax': idealWeightMax,
      if (lastBathDate != null) 'lastBathDate': lastBathDate!.toIso8601String(),
      if (readinessStreak != null) 'readinessStreak': readinessStreak,
      if (specialties != null) 'specialties': specialties,
      if (cor != null) 'cor': cor,
      if (microchip != null) 'microchip': microchip,
      if (observacoes != null) 'observacoes': observacoes,
      if (condicaoCorporal != null) 'condicaoCorporal': condicaoCorporal,
    };
  }

  Dog copyWith({
    String? id,
    String? name,
    String? breed,
    String? sex,
    DateTime? dateOfBirth,
    String? status,
    String? profileImageUrl,
    String? conductorRa,
    DateTime? lastTrainingDate,
    DateTime? lastVaccineDate,
    double? weight,
    String? registrationNumber,
    double? idealWeightMin,
    double? idealWeightMax,
    DateTime? lastBathDate,
    Map<String, dynamic>? readinessStreak,
    List<String>? specialties,
    String? cor,
    String? microchip,
    String? observacoes,
    String? condicaoCorporal,
  }) {
    return Dog(
      id: id ?? this.id,
      name: name ?? this.name,
      breed: breed ?? this.breed,
      sex: sex ?? this.sex,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      status: status ?? this.status,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      conductorRa: conductorRa ?? this.conductorRa,
      lastTrainingDate: lastTrainingDate ?? this.lastTrainingDate,
      lastVaccineDate: lastVaccineDate ?? this.lastVaccineDate,
      weight: weight ?? this.weight,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      idealWeightMin: idealWeightMin ?? this.idealWeightMin,
      idealWeightMax: idealWeightMax ?? this.idealWeightMax,
      lastBathDate: lastBathDate ?? this.lastBathDate,
      readinessStreak: readinessStreak ?? this.readinessStreak,
      specialties: specialties ?? this.specialties,
      cor: cor ?? this.cor,
      microchip: microchip ?? this.microchip,
      observacoes: observacoes ?? this.observacoes,
      condicaoCorporal: condicaoCorporal ?? this.condicaoCorporal,
    );
  }

  int get age {
    final today = DateTime.now();
    var yearDiff = today.year - dateOfBirth.year;
    if (today.month < dateOfBirth.month ||
        (today.month == dateOfBirth.month && today.day < dateOfBirth.day)) {
      yearDiff--;
    }
    return yearDiff;
  }

  String get operationalStatus {
    if (status != 'Ativo') return status;
    final now = DateTime.now();
    if (lastTrainingDate != null) {
      final diff = now.difference(lastTrainingDate!).inHours;
      if (diff < 8) return 'Em treino';
    }
    return 'Ativo';
  }

  /// Readiness 0-100 com base em saúde e trabalho recente.
  ///
  /// Pesos:
  /// - Vacinação em dia: até 30
  /// - Peso dentro da faixa ideal: até 25
  /// - Higiene recente: até 15
  /// - Treino recente: até 30
  ({int total, int vacinacao, int peso, int higiene, int treino})
  calculateReadinessBreakdown({
    DateTime? lastBathOverride,
    double? weightOverride,
  }) {
    final now = DateTime.now();
    final effectiveBathDate = lastBathOverride ?? lastBathDate;
    final effectiveWeight = weightOverride ?? weight;
    var vaccineScore = 0;
    var weightScore = 0;
    var hygieneScore = 0;
    var trainingScore = 0;

    if (lastVaccineDate != null) {
      final daysSinceVaccine = now.difference(lastVaccineDate!).inDays;
      if (daysSinceVaccine <= 300) {
        vaccineScore = 30;
      } else if (daysSinceVaccine <= 335) {
        vaccineScore = 24;
      } else if (daysSinceVaccine <= 365) {
        vaccineScore = 12;
      }
    }

    if (effectiveWeight != null &&
        idealWeightMin != null &&
        idealWeightMax != null) {
      if (effectiveWeight >= idealWeightMin! &&
          effectiveWeight <= idealWeightMax!) {
        weightScore = 25;
      } else {
        final distanceToRange = effectiveWeight < idealWeightMin!
            ? idealWeightMin! - effectiveWeight
            : effectiveWeight - idealWeightMax!;
        if (distanceToRange <= 1.0) {
          weightScore = 15;
        } else if (distanceToRange <= 2.0) {
          weightScore = 8;
        }
      }
    }

    if (effectiveBathDate != null) {
      final daysSinceBath = now.difference(effectiveBathDate).inDays;
      if (daysSinceBath <= 7) {
        hygieneScore = 15;
      } else if (daysSinceBath <= 14) {
        hygieneScore = 10;
      } else if (daysSinceBath <= 21) {
        hygieneScore = 5;
      }
    }

    if (lastTrainingDate != null) {
      final daysSinceTraining = now.difference(lastTrainingDate!).inDays;
      if (daysSinceTraining <= 2) {
        trainingScore = 30;
      } else if (daysSinceTraining <= 5) {
        trainingScore = 22;
      } else if (daysSinceTraining <= 7) {
        trainingScore = 14;
      } else if (daysSinceTraining <= 10) {
        trainingScore = 8;
      }
    }

    final total = (vaccineScore + weightScore + hygieneScore + trainingScore)
        .clamp(0, 100);

    return (
      total: total,
      vacinacao: vaccineScore,
      peso: weightScore,
      higiene: hygieneScore,
      treino: trainingScore,
    );
  }

  int calculateReadiness({DateTime? lastBathOverride, double? weightOverride}) {
    return calculateReadinessBreakdown(
      lastBathOverride: lastBathOverride,
      weightOverride: weightOverride,
    ).total;
  }
}
