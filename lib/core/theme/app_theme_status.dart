part of 'app_theme.dart';

Color _statusColor(String status) {
  switch (status) {
    case 'Ativo':
      return AppTheme.statusActive;
    case 'Em Treino':
      return AppTheme.statusTraining;
    case 'Licença':
      return AppTheme.statusLeave;
    case 'Aposentado':
      return AppTheme.statusRetired;
    case 'Veterinário':
      return AppTheme.statusVet;
    case 'Baixa':
      return AppTheme.statusAlert;
    default:
      return const Color(0xFF546E7A);
  }
}

Color _statusBg(String status) {
  switch (status) {
    case 'Ativo':
      return const Color(0xFF0A1E12);
    case 'Em Treino':
      return const Color(0xFF00151A);
    case 'Licença':
      return const Color(0xFF1A1400);
    case 'Aposentado':
      return const Color(0xFF05111A);
    case 'Veterinário':
      return const Color(0xFF12001E);
    case 'Baixa':
      return const Color(0xFF1E0505);
    default:
      return const Color(0xFF0B1215);
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'Ativo':
      return 'ATIVO';
    case 'Em Treino':
      return 'EM TREINO';
    case 'Licença':
      return 'LICENÇA';
    case 'Aposentado':
      return 'APOSENTADO';
    case 'Veterinário':
      return 'VETERINÁRIO';
    case 'Baixa':
      return 'BAIXA MÉD.';
    default:
      return status.toUpperCase();
  }
}

IconData _statusIcon(String status) {
  switch (status) {
    case 'Ativo':
      return Icons.check_circle_rounded;
    case 'Em Treino':
      return Icons.fitness_center_rounded;
    case 'Licença':
      return Icons.pause_circle_rounded;
    case 'Aposentado':
      return Icons.archive_rounded;
    case 'Veterinário':
      return Icons.medical_services_rounded;
    case 'Baixa':
      return Icons.personal_injury_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

LinearGradient _statusGradient(String status) {
  switch (status) {
    case 'Ativo':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B5E3A), Color(0xFF0A3320)],
      );
    case 'Em Treino':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF004D5A), Color(0xFF002830)],
      );
    case 'Licença':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7A5800), Color(0xFF3D2C00)],
      );
    case 'Aposentado':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D3B5C), Color(0xFF051D30)],
      );
    case 'Veterinário':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4A0072), Color(0xFF230036)],
      );
    case 'Baixa':
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF7A1A1A), Color(0xFF3D0000)],
      );
    default:
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A2328), Color(0xFF0B1215)],
      );
  }
}
