class WeeklyMissionProgress {
  final String missionId;
  final String title;
  final String description;
  final int current;
  final int target;
  final String unitLabel;
  final int rewardXp;
  final bool claimed;

  const WeeklyMissionProgress({
    required this.missionId,
    required this.title,
    required this.description,
    required this.current,
    required this.target,
    required this.unitLabel,
    required this.rewardXp,
    required this.claimed,
  });

  bool get completed => current >= target;
  int get remaining => completed ? 0 : target - current;
  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();
}
