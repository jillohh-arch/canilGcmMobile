import 'package:flutter/material.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/widgets/hud_chip_group.dart';
import 'package:canil_gcm/widgets/tactical_text_field.dart';
import '../controllers/occurrence_form_controller.dart';
import 'occurrence_quick_update_catalog.dart';
import 'occurrence_quick_update_shortcuts.dart';
import 'occurrence_timeline_preview.dart';

class OccurrenceMetaFields extends StatelessWidget {
  final String status;
  final bool? successful;
  final List<String> outcomeOptions;
  final Set<String> selectedOutcomes;
  final List<OccurrenceQuickUpdateShortcut> shortcuts;
  final String? selectedShortcutTitle;
  final bool showUpdateSpacing;
  final TextEditingController updateController;
  final List<IncidentProgressUpdate> timelineUpdates;
  final Color accent;
  final ValueChanged<String> onStatusSelected;
  final ValueChanged<bool> onSuccessChanged;
  final ValueChanged<String> onOutcomeToggle;
  final ValueChanged<String> onShortcutSelected;
  final ValueChanged<int> onEventTap;

  const OccurrenceMetaFields({
    super.key,
    required this.status,
    required this.successful,
    required this.outcomeOptions,
    required this.selectedOutcomes,
    required this.shortcuts,
    required this.selectedShortcutTitle,
    required this.showUpdateSpacing,
    required this.updateController,
    required this.timelineUpdates,
    required this.accent,
    required this.onStatusSelected,
    required this.onSuccessChanged,
    required this.onOutcomeToggle,
    required this.onShortcutSelected,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        HudChoiceChipGroup(
          label: 'Status da ocorrência',
          options: const [
            OccurrenceFormController.statusInProgress,
            OccurrenceFormController.statusCompleted,
            OccurrenceFormController.statusCanceled,
          ],
          selectedOption: status,
          accent: accent,
          onSelected: onStatusSelected,
        ),
        if (status != OccurrenceFormController.statusInProgress) ...[
          const SizedBox(height: 8),
          HudChoiceChipGroup(
            label: 'Desfecho Operacional',
            options: const ['Com êxito', 'Sem êxito'],
            selectedOption: successful == true
                ? 'Com êxito'
                : successful == false
                ? 'Sem êxito'
                : null,
            accent: accent,
            onSelected: (value) => onSuccessChanged(value == 'Com êxito'),
          ),
        ],
        const SizedBox(height: 8),
        HudMultiChipGroup(
          label: 'Resultados Finais',
          options: outcomeOptions,
          selectedOptions: selectedOutcomes,
          accent: accent,
          onToggle: onOutcomeToggle,
        ),
        const SizedBox(height: 16),
        if (shortcuts.isNotEmpty)
          OccurrenceQuickUpdateShortcuts(
            titles: shortcuts.map((shortcut) => shortcut.title).toList(),
            selectedTitle: selectedShortcutTitle,
            accent: accent,
            onSelected: onShortcutSelected,
          ),
        if (showUpdateSpacing) const SizedBox(height: 12),
        TacticalTextField(
          controller: updateController,
          labelText: 'Atualização desta etapa',
          prefixIcon: Icons.timeline_rounded,
          maxLines: 3,
          minLines: 2,
        ),
        if (timelineUpdates.isNotEmpty)
          OccurrenceTimelinePreview(
            updates: timelineUpdates,
            accent: accent,
            onEventTap: onEventTap,
          ),
      ],
    );
  }
}
