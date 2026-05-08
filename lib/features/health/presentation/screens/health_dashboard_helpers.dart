part of 'health_dashboard_screen.dart';

const _healthDashboardMonthNames = [
  '',
  'JAN',
  'FEV',
  'MAR',
  'ABR',
  'MAI',
  'JUN',
  'JUL',
  'AGO',
  'SET',
  'OUT',
  'NOV',
  'DEZ',
];

String _formatMilitaryDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = _healthDashboardMonthNames[date.month];
  final year = date.year.toString().substring(2);
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day$month$year - $hour:${minute}h';
}

String _formatShortDate(DateTime? date) {
  if (date == null) return '-- ---';
  final day = date.day.toString().padLeft(2, '0');
  return '$day ${_healthDashboardMonthNames[date.month]}';
}

extension _HealthDashboardScaffoldParts on _HealthDashboardScreenState {
  Widget _buildSliverHeader() {
    return SliverAppBar(
      expandedHeight: 0,
      pinned: true,
      backgroundColor: const Color(0xFF030712),
      elevation: 0,
      title: Text(
        'BIO-SURVEILLANCE',
        style: GoogleFonts.oxanium(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
          color: Colors.cyanAccent.withValues(alpha: 0.7),
        ),
      ),
      centerTitle: true,
    );
  }
}
