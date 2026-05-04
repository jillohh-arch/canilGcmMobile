import 'package:flutter/material.dart';

import 'tactical_text_field.dart';

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

class RoutineActivityFields extends StatelessWidget {
  final bool visible;
  final bool isFeeding;
  final bool isPlayOrWalk;
  final bool isWalk;
  final TextEditingController rationBrandController;
  final TextEditingController rationAmountController;
  final TextEditingController durationController;
  final TextEditingController distanceController;

  const RoutineActivityFields({
    super.key,
    required this.visible,
    required this.isFeeding,
    required this.isPlayOrWalk,
    required this.isWalk,
    required this.rationBrandController,
    required this.rationAmountController,
    required this.durationController,
    required this.distanceController,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Column(
      children: [
        if (isFeeding) ...[
          const SizedBox(height: 16),
          TacticalTextField(
            controller: rationBrandController,
            labelText: 'Marca da ração',
            prefixIcon: Icons.shopping_bag_rounded,
          ),
          const SizedBox(height: 16),
          TacticalTextField(
            controller: rationAmountController,
            keyboardType: TextInputType.number,
            labelText: 'Quantidade (em gramas)',
            prefixIcon: Icons.scale_rounded,
          ),
        ] else if (isPlayOrWalk) ...[
          const SizedBox(height: 16),
          TacticalTextField(
            controller: durationController,
            keyboardType: TextInputType.number,
            labelText: 'Duração (Minutos)',
            prefixIcon: Icons.timer_rounded,
          ),
          if (isWalk) ...[
            const SizedBox(height: 16),
            TacticalTextField(
              controller: distanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              labelText: 'Distância (km)',
              prefixIcon: Icons.straighten_rounded,
            ),
          ],
        ],
      ],
    );
  }
}
