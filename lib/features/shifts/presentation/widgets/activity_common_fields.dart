import 'package:flutter/material.dart';
import 'package:canil_gcm/core/theme/app_theme.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

import 'location_time_row.dart';

class ActivityLocationTimeFields extends StatelessWidget {
  final TextEditingController locationController;
  final TextEditingController timeController;
  final bool isHealth;

  const ActivityLocationTimeFields({
    super.key,
    required this.locationController,
    required this.timeController,
    required this.isHealth,
  });

  @override
  Widget build(BuildContext context) {
    return LocationTimeRow(
      locationField: TacticalTextField(
        controller: locationController,
        labelText: isHealth ? 'Local / Clínica' : 'Endereço / Local',
        prefixIcon: Icons.location_on_rounded,
      ),
      timeField: TacticalTextField(
        controller: timeController,
        labelText: 'Hora',
        readOnly: true,
      ),
    );
  }
}

class ActivityDescriptionField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final bool isListening;
  final VoidCallback onStartListening;
  final VoidCallback onStopListening;
  final VoidCallback onToggleListening;

  const ActivityDescriptionField({
    super.key,
    required this.controller,
    required this.labelText,
    required this.isListening,
    required this.onStartListening,
    required this.onStopListening,
    required this.onToggleListening,
  });

  @override
  Widget build(BuildContext context) {
    return TacticalTextField(
      controller: controller,
      maxLines: 5,
      minLines: 3,
      labelText: labelText,
      prefixIcon: Icons.notes_rounded,
      suffixIcon: GestureDetector(
        onLongPressStart: (_) => onStartListening(),
        onLongPressEnd: (_) => onStopListening(),
        onTap: onToggleListening,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: isListening ? AppTheme.errorStrong : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
