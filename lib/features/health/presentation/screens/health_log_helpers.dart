part of 'health_log_screen.dart';

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.poppins(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Colors.white70,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────
(IconData, Color) _iconAndColor(String logType) {
  switch (logType) {
    case 'Vacina':
      return (Icons.vaccines_rounded, const Color(0xFFEF5350));
    case 'Consulta':
      return (Icons.local_hospital_rounded, const Color(0xFF66BB6A));
    case 'Exame':
      return (Icons.biotech_rounded, const Color(0xFF7E57C2));
    case 'Medicação':
      return (Icons.medication_rounded, const Color(0xFFFF7043));
    case 'Banho':
      return (Icons.water_drop_rounded, const Color(0xFF29B6F6));
    default:
      return (Icons.medical_services_rounded, const Color(0xFFEF5350));
  }
}

IconData _logIcon(String logType) => _iconAndColor(logType).$1;
