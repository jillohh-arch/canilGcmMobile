part of 'health_dashboard_screen.dart';

Color _healthLogColor(String type) {
  switch (type) {
    case 'Vacina':
      return const Color(0xFFFF00FF);
    case 'Exame':
      return Colors.cyanAccent;
    case 'Banho':
      return const Color(0xFF00BFFF);
    case 'Consulta':
      return Colors.orangeAccent;
    default:
      return Colors.cyan;
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
