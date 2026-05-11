part of 'active_shift_dashboard_screen.dart';

extension _ActiveShiftReadiness on _ActiveShiftDashboardScreenState {
  Dog? _localDogFallback(DogViewModel dogVM, String dogId) {
    for (final dog in dogVM.dogs) {
      if (dog.id == dogId) return dog;
    }
    return dogVM.dogs.isNotEmpty ? dogVM.dogs.first : null;
  }

  Future<void> _checkReadinessStreakTracker(
    Dog dog,
    String currentRa,
    UserViewModel userVM,
    DogViewModel dogVM,
  ) async {
    final score = _calculateOperationalReadiness(dog);
    final today = DateTime.now().toIso8601String().substring(0, 10);

    final streak = dog.readinessStreak != null
        ? Map<String, dynamic>.from(dog.readinessStreak!)
        : <String, dynamic>{'lastCheck': '', 'days90': 0, 'days95': 0};
    if (streak['lastCheck'] == today) return;

    final currentDays90 =
        (streak['days90'] as int?) ?? (streak['days'] as int? ?? 0);
    final currentDays95 = (streak['days95'] as int?) ?? 0;

    if (score >= 90) {
      if (streak['lastCheck'] != '') {
        final last = DateTime.parse(streak['lastCheck'] as String);
        final diff = DateTime.now().difference(last).inDays;
        if (diff == 1) {
          streak['days90'] = currentDays90 + 1;
          streak['days95'] = score >= 95 ? currentDays95 + 1 : 0;
        } else if (diff > 1) {
          streak['days90'] = 1;
          streak['days95'] = score >= 95 ? 1 : 0;
        }
      } else {
        streak['days90'] = 1;
        streak['days95'] = score >= 95 ? 1 : 0;
      }
    } else {
      streak['days90'] = 0;
      streak['days95'] = 0;
    }

    streak['days'] = streak['days90'];
    streak['lastCheck'] = today;

    final updatedDog = Dog(
      id: dog.id,
      name: dog.name,
      breed: dog.breed,
      sex: dog.sex,
      dateOfBirth: dog.dateOfBirth,
      status: dog.status,
      profileImageUrl: dog.profileImageUrl,
      conductorRa: dog.conductorRa,
      lastTrainingDate: dog.lastTrainingDate,
      lastVaccineDate: dog.lastVaccineDate,
      weight: dog.weight,
      registrationNumber: dog.registrationNumber,
      idealWeightMin: dog.idealWeightMin,
      idealWeightMax: dog.idealWeightMax,
      lastBathDate: dog.lastBathDate,
      readinessStreak: streak,
    );
    await dogVM.saveDog(updatedDog);
  }

  int _calculateOperationalReadiness(Dog dog) {
    final healthVM = Provider.of<HealthViewModel>(context, listen: false);
    final dogLogs =
        healthVM.healthLogs.where((log) => log.dogId == dog.id).toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    DateTime? lastBathOverride;
    double? weightOverride;

    for (final log in dogLogs) {
      if (lastBathOverride == null && log.logType == 'Banho') {
        lastBathOverride = log.date;
      }
      if (weightOverride == null && log.weight != null) {
        weightOverride = log.weight;
      }
      if (lastBathOverride != null && weightOverride != null) {
        break;
      }
    }

    return dog.calculateReadiness(
      lastBathOverride: lastBathOverride,
      weightOverride: weightOverride,
    );
  }
}
