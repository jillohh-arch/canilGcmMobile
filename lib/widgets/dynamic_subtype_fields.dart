import 'package:flutter/material.dart';

import 'activity_card_catalog.dart';
import 'scent_work_activity_fields.dart';
import 'tracking_activity_fields.dart';
import 'training_subtype_fields.dart';

typedef FormDataChanged = void Function(String label, String? value);

typedef TrackingActionBuilder =
    Widget Function({
      required String startLabel,
      required IconData startIcon,
      required Color backgroundColor,
      required Color foregroundColor,
      bool isLightMode,
      EdgeInsetsGeometry padding,
      EdgeInsetsGeometry capturedMargin,
    });

class DynamicSubtypeFields extends StatelessWidget {
  static const searchCaptureSubtype = ActivitySubtypeIds.searchCapture;
  static const guardProtectionSubtype = ActivitySubtypeIds.guardProtection;
  static const scentWorkSubtype = ActivitySubtypeIds.scentWork;
  static const obedienceSubtype = ActivitySubtypeIds.obedience;
  static const physicalConditioningSubtype =
      ActivitySubtypeIds.physicalConditioning;
  static const leisureConditioningSubtype = 'Lazer/Condicionamento';
  static const walkSubtype = ActivitySubtypeIds.walk;

  final String? subtype;
  final Map<String, dynamic> formData;
  final Color accentColor;
  final Color odorAccentColor;
  final TextEditingController objectiveController;
  final TextEditingController difficultiesController;
  final TextEditingController temperatureController;
  final TextEditingController humidityController;
  final FormDataChanged onChanged;
  final ValueChanged<String?> onOdorChanged;
  final VoidCallback onPullWeather;
  final TrackingActionBuilder trackingActionBuilder;

  const DynamicSubtypeFields({
    super.key,
    required this.subtype,
    required this.formData,
    required this.accentColor,
    required this.odorAccentColor,
    required this.objectiveController,
    required this.difficultiesController,
    required this.temperatureController,
    required this.humidityController,
    required this.onChanged,
    required this.onOdorChanged,
    required this.onPullWeather,
    required this.trackingActionBuilder,
  });

  static bool handles(String? subtype) {
    return subtype == searchCaptureSubtype ||
        subtype == guardProtectionSubtype ||
        subtype == scentWorkSubtype ||
        subtype == obedienceSubtype ||
        subtype == physicalConditioningSubtype ||
        subtype == leisureConditioningSubtype ||
        subtype == walkSubtype;
  }

  @override
  Widget build(BuildContext context) {
    return switch (subtype) {
      searchCaptureSubtype => SearchCaptureActivityFields(
        selectedTrailAge: formData['Idade da Trilha'] as String?,
        selectedTerrain: formData['Terreno'] as String?,
        selectedOdorArticle: formData['Artigo de Odor'] as String?,
        accent: accentColor,
        onChanged: onChanged,
        trackingAction: trackingActionBuilder(
          startLabel: 'INICIAR RASTREIO TÁTICO',
          startIcon: Icons.satellite_alt_rounded,
          backgroundColor: const Color(0xFFFBBF24),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.only(bottom: 24),
        ),
      ),
      guardProtectionSubtype => GuardProtectionActivityFields(
        selectedScenario: formData['Cenário'] as String?,
        selectedFigurant: formData['Figurante'] as String?,
        selectedControl: formData['Controle/Out'] as String?,
        accent: accentColor,
        objectiveController: objectiveController,
        onChanged: onChanged,
      ),
      scentWorkSubtype => ScentWorkActivityFields(
        accentColor: accentColor,
        odorAccentColor: odorAccentColor,
        selectedWindDirection: formData['Direção do Vento'] as String?,
        selectedDifficulty: formData['Dificuldade'] as String?,
        selectedFinalResponse: formData['Resposta Final'] as String?,
        selectedOdor: formData['Tipo de Odor'] as String?,
        temperatureController: temperatureController,
        humidityController: humidityController,
        onChipChanged: onChanged,
        onOdorChanged: onOdorChanged,
        onPullWeather: onPullWeather,
      ),
      obedienceSubtype => ObedienceActivityFields(
        selectedDistraction: formData['Distração'] as String?,
        selectedLead: formData['Guia'] as String?,
        selectedSuccess: formData['Teve êxito?'] as String?,
        accent: accentColor,
        objectiveController: objectiveController,
        difficultiesController: difficultiesController,
        onChanged: onChanged,
      ),
      physicalConditioningSubtype => LeisureConditioningActivityFields(
        selectedActivity: formData['Atividade'] as String?,
        selectedIntensity: formData['Intensidade'] as String?,
        accent: accentColor,
        onChanged: onChanged,
      ),
      leisureConditioningSubtype => LeisureConditioningActivityFields(
        selectedActivity: formData['Atividade'] as String?,
        selectedIntensity: formData['Intensidade'] as String?,
        accent: accentColor,
        onChanged: onChanged,
      ),
      walkSubtype => WalkTrackingActivityFields(
        selectedFloorType: formData['Tipo de Piso'] as String?,
        selectedLeadType: formData['Guia'] as String?,
        accent: accentColor,
        onChanged: onChanged,
        trackingAction: trackingActionBuilder(
          startLabel: 'INICIAR RASTREIO DE PASSEIO',
          startIcon: Icons.directions_walk_rounded,
          backgroundColor: const Color(0xFF43A047),
          foregroundColor: Colors.white,
          isLightMode: true,
          padding: const EdgeInsets.only(bottom: 24),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
