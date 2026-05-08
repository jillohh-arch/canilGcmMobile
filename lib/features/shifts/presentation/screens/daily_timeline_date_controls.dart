// ignore_for_file: invalid_use_of_protected_member

part of 'daily_timeline_screen.dart';

extension _DailyTimelineDateControls on _DailyTimelineScreenState {
  Widget _buildHeaderDate() {
    final monthName = DateFormat('MMMM, y').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            monthName.toUpperCase(),
            style: GoogleFonts.inter(
              color: Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          IconButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: Color(0xFFFBBF24),
                      surface: Color(0xFF1C1C1E),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
            icon: const Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      height: 96,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        reverse: true,
        itemCount: 31,
        itemBuilder: (context, index) {
          final date = DateTime.now().subtract(Duration(days: index));
          final isSelected =
              date.year == _selectedDate.year &&
              date.month == _selectedDate.month &&
              date.day == _selectedDate.day;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedDate = date);
            },
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
                    _getWeekday(date.weekday),
                    style: GoogleFonts.robotoMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? const Color(0xFF00E5FF)
                          : Colors.white38,
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
                    color: isSelected
                        ? const Color(0xFF00E5FF)
                        : Colors.white12,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getWeekday(int weekday) {
    const days = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];
    return days[weekday - 1];
  }
}
