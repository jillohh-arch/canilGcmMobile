import 'package:flutter/material.dart';

import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

class TrainingActivityFields extends StatelessWidget {
  final bool visible;
  final TextEditingController durationController;

  const TrainingActivityFields({
    super.key,
    required this.visible,
    required this.durationController,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 24),
        TacticalTextField(
          controller: durationController,
          keyboardType: TextInputType.number,
          labelText: 'Duração (Minutos)',
          prefixIcon: Icons.timer_rounded,
        ),
      ],
    );
  }
}
