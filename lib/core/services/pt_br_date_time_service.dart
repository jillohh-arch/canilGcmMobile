class PtBrDateTimeService {
  const PtBrDateTimeService();

  String time(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
  }

  String date(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.year}';
  }

  DateTime withTimeText({required DateTime base, required String timeText}) {
    if (timeText.isEmpty) {
      return base;
    }

    final parts = timeText.split(':');
    if (parts.length != 2) {
      return base;
    }

    return DateTime(
      base.year,
      base.month,
      base.day,
      int.tryParse(parts[0]) ?? base.hour,
      int.tryParse(parts[1]) ?? base.minute,
    );
  }
}
