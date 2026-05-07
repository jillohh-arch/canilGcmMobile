class LevelProgress {
  final int level;
  final int currentXp;
  final int currentLevelFloorXp;
  final int nextLevelXp;

  const LevelProgress({
    required this.level,
    required this.currentXp,
    required this.currentLevelFloorXp,
    required this.nextLevelXp,
  });

  int get xpIntoLevel => currentXp - currentLevelFloorXp;
  int get xpRequiredInLevel => nextLevelXp - currentLevelFloorXp;
  int get xpRemaining => nextLevelXp - currentXp;
  double get progress {
    if (xpRequiredInLevel <= 0) return 0;
    return (xpIntoLevel / xpRequiredInLevel).clamp(0, 1).toDouble();
  }
}
