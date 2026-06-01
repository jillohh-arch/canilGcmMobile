part of 'health_log_screen.dart';

// ── Shared helpers ─────────────────────────────────────────────────────────────
(IconData, Color) _iconAndColor(String logType) {
  switch (logType) {
    case 'Vacina':
      return (Icons.vaccines_rounded, AppTheme.errorStrong);
    case 'Consulta':
      return (Icons.local_hospital_rounded, AppTheme.successCheck);
    case 'Exame':
      return (Icons.biotech_rounded, AppTheme.healthAccent);
    case 'Medicação':
      return (Icons.medication_rounded, AppTheme.attention);
    case 'Banho':
      return (Icons.water_drop_rounded, AppTheme.info);
    default:
      return (Icons.medical_services_rounded, AppTheme.errorStrong);
  }
}

IconData _logIcon(String logType) => _iconAndColor(logType).$1;
