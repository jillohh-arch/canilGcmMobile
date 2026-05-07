class BadgeProgress {
  final String badgeId;
  final int current;
  final int target;
  final String unitLabel;
  final String summary;

  const BadgeProgress({
    required this.badgeId,
    required this.current,
    required this.target,
    required this.unitLabel,
    required this.summary,
  });

  bool get completed => current >= target;
  double get progress =>
      target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();
  int get remaining => current >= target ? 0 : target - current;
}
