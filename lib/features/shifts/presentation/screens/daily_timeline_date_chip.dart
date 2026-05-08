part of 'daily_timeline_screen.dart';

class _TimelineDateChip extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final VoidCallback onTap;

  const _TimelineDateChip({
    required this.date,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 55,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00E5FF).withAlpha(34)
              : const Color(0xFF0B1020),
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withAlpha(80),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : [],
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00E5FF)
                : const Color(0x3300E5FF),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _timelineWeekdayLabel(date.weekday),
              style: GoogleFonts.robotoMono(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${date.day}',
              style: GoogleFonts.oxanium(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : Colors.white70,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 18,
              height: 2,
              color: isSelected ? const Color(0xFF00E5FF) : Colors.white12,
            ),
          ],
        ),
      ),
    );
  }
}

String _timelineWeekdayLabel(int weekday) {
  const days = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
  return days[weekday - 1];
}
