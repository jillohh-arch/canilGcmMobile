part of 'active_shift_dashboard_screen.dart';

/// Verifica e atualiza o streak de prontidão do cão.
void _checkReadinessStreakTracker(
  Dog dog,
  String currentRa,
  UserViewModel userVM,
  DogViewModel dogVM,
) {
  // Calcula readiness atual
  final readiness = dog.calculateReadiness();

  // Atualiza streak no documento do cão se necessário
  final streak = dog.readinessStreak;
  final today = DateTime.now();
  final todayKey =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  if (streak == null || streak['last_date'] != todayKey) {
    final currentStreak = (streak?['count'] as int?) ?? 0;
    final lastDate = streak?['last_date'] as String?;

    int newStreak;
    if (lastDate != null) {
      final lastParsed = DateTime.tryParse(lastDate);
      if (lastParsed != null &&
          today.difference(lastParsed).inDays == 1 &&
          readiness >= 80) {
        newStreak = currentStreak + 1;
      } else if (readiness >= 80) {
        newStreak = 1;
      } else {
        newStreak = 0;
      }
    } else {
      newStreak = readiness >= 80 ? 1 : 0;
    }

    // Atualiza no Firestore (fire-and-forget)
    DogService().updateDogDates(dog.id).catchError((_) {});
    // Usa newStreak para evitar warning de variável não usada
    debugPrint('Readiness streak: $newStreak');
  }
}
