import 'package:flutter/material.dart';

import 'package:canil_gcm/core/widgets/hud_chip_group.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

class GuardProtectionActivityFields extends StatelessWidget {
  final String? selectedScenario;
  final String? selectedFigurant;
  final String? selectedControl;
  final Color accent;
  final TextEditingController objectiveController;
  final void Function(String label, String? value) onChanged;

  const GuardProtectionActivityFields({
    super.key,
    required this.selectedScenario,
    required this.selectedFigurant,
    required this.selectedControl,
    required this.accent,
    required this.objectiveController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Cenário',
          options: const [
            'Abordagem',
            'Edificação',
            'Perseguição',
            'Estampido',
          ],
          selectedOption: selectedScenario,
          accent: accent,
          onChanged: (value) => onChanged('Cenário', value),
        ),
        HudToggleChipGroup(
          label: 'Figurante',
          options: const ['Manga', 'Traje Completo', 'Focinheira', 'Civil'],
          selectedOption: selectedFigurant,
          accent: accent,
          onChanged: (value) => onChanged('Figurante', value),
        ),
        HudToggleChipGroup(
          label: 'Controle/Out',
          options: const ['Solta Limpa', 'Comando Extra', 'Correção Mecânica'],
          selectedOption: selectedControl,
          accent: accent,
          onChanged: (value) => onChanged('Controle/Out', value),
        ),
        const SizedBox(height: 8),
        TacticalTextField(
          controller: objectiveController,
          labelText: 'Objetivo do Treino',
          prefixIcon: Icons.flag_rounded,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class ObedienceActivityFields extends StatelessWidget {
  final String? selectedDistraction;
  final String? selectedLead;
  final String? selectedSuccess;
  final Color accent;
  final TextEditingController objectiveController;
  final TextEditingController difficultiesController;
  final void Function(String label, String? value) onChanged;

  const ObedienceActivityFields({
    super.key,
    required this.selectedDistraction,
    required this.selectedLead,
    required this.selectedSuccess,
    required this.accent,
    required this.objectiveController,
    required this.difficultiesController,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TacticalTextField(
          controller: objectiveController,
          labelText: 'Objetivos do Treino',
          prefixIcon: Icons.flag_rounded,
        ),
        const SizedBox(height: 16),
        HudToggleChipGroup(
          label: 'Distração',
          options: const ['Baixa', 'Média', 'Alta', 'Extrema'],
          selectedOption: selectedDistraction,
          accent: accent,
          onChanged: (value) => onChanged('Distração', value),
        ),
        HudToggleChipGroup(
          label: 'Guia',
          options: const ['Sem guia', 'Misto', 'Com guia'],
          selectedOption: selectedLead,
          accent: accent,
          onChanged: (value) => onChanged('Guia', value),
        ),
        HudToggleChipGroup(
          label: 'Teve êxito?',
          options: const ['Sim', 'Não'],
          selectedOption: selectedSuccess,
          accent: accent,
          onChanged: (value) => onChanged('Teve êxito?', value),
        ),
        TacticalTextField(
          controller: difficultiesController,
          labelText: 'Dificuldades Encontradas',
          prefixIcon: Icons.warning_amber_rounded,
          maxLines: 3,
          minLines: 2,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class LeisureConditioningActivityFields extends StatelessWidget {
  final String? selectedActivity;
  final String? selectedIntensity;
  final Color accent;
  final void Function(String label, String? value) onChanged;

  const LeisureConditioningActivityFields({
    super.key,
    required this.selectedActivity,
    required this.selectedIntensity,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HudToggleChipGroup(
          label: 'Atividade',
          options: const [
            'Passeio Livre',
            'Bolinha/Tug',
            'Socialização',
            'Esteira',
            'Natação',
          ],
          selectedOption: selectedActivity,
          accent: accent,
          onChanged: (value) => onChanged('Atividade', value),
        ),
        HudToggleChipGroup(
          label: 'Intensidade',
          options: const ['Regenerativo', 'Moderado', 'Alta Intensidade'],
          selectedOption: selectedIntensity,
          accent: accent,
          onChanged: (value) => onChanged('Intensidade', value),
        ),
      ],
    );
  }
}
