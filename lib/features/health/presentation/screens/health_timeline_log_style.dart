part of 'health_dashboard_screen.dart';

Color _healthLogColor(String type) {
  switch (type) {
    case 'Vacina':
      return AppTheme.healthAccent;
    case 'Exame':
      return AppTheme.primary;
    case 'Banho':
      return AppTheme.info;
    case 'Consulta':
      return AppTheme.attention;
    default:
      return AppTheme.primary;
  }
}

IconData _healthLogIcon(String type) {
  switch (type) {
    case 'Vacina':
      return Icons.vaccines;
    case 'Exame':
      return Icons.biotech;
    case 'Banho':
      return Icons.water_drop;
    case 'Consulta':
      return Icons.medical_services;
    default:
      return Icons.fact_check;
  }
}
