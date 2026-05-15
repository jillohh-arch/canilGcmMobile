part of 'occurrence_close_wizard.dart';

const _occurrenceCloseDrugOptions = [
  'Maconha',
  'Cocaína',
  'Crack',
  'Sintéticos',
  'Nose MP',
  'Outros',
];

const _occurrenceCloseResultOptions = [
  _ResultOption(
    label: 'Droga apreendida',
    icon: Icons.science_rounded,
    color: Color(0xFFA855F7),
  ),
  _ResultOption(
    label: 'Objetos apreendidos',
    icon: Icons.inventory_2_rounded,
    color: AppTheme.warning,
  ),
  _ResultOption(
    label: 'Veículo detido',
    icon: Icons.directions_car_rounded,
    color: Color(0xFF00B8FF),
  ),
  _ResultOption(
    label: 'Indivíduo detido',
    icon: Icons.person_pin_rounded,
    color: Color(0xFFFF8A00),
  ),
  _ResultOption(
    label: 'Apoio prestado',
    icon: Icons.handshake_rounded,
    color: AppTheme.success,
  ),
  _ResultOption(
    label: 'BO elaborado',
    icon: Icons.article_rounded,
    color: AppTheme.primary,
  ),
  _ResultOption(
    label: 'Encaminhamento médico',
    icon: Icons.local_hospital_rounded,
    color: AppTheme.error,
  ),
  _ResultOption(
    label: 'Sem constatação',
    icon: Icons.highlight_off_rounded,
    color: Color(0xFFB8C2D6),
  ),
];
