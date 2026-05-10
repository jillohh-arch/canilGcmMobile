import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

part 'event_details_bottom_sheet_header.dart';
part 'event_details_bottom_sheet_evidence.dart';
part 'event_details_bottom_sheet_actions.dart';
part 'event_details_bottom_sheet_detail_line.dart';

class OccurrenceEventDetailsSheet extends StatelessWidget {
  final IncidentProgressUpdate update;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final String timestampLabel;
  final String eventLocation;
  final List<Map<String, dynamic>> eventAttachments;
  final int pendingPhotoCount;
  final Color backgroundColor;
  final Color panelColor;
  final Color accentColor;
  final Color successColor;
  final Color warningColor;
  final Color dangerColor;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onCaptureLocation;
  final VoidCallback onDelete;
  final Future<void> Function() onSave;

  const OccurrenceEventDetailsSheet({
    super.key,
    required this.update,
    required this.titleController,
    required this.descriptionController,
    required this.timestampLabel,
    required this.eventLocation,
    required this.eventAttachments,
    required this.pendingPhotoCount,
    required this.backgroundColor,
    required this.panelColor,
    required this.accentColor,
    required this.successColor,
    required this.warningColor,
    required this.dangerColor,
    required this.onAddPhotos,
    required this.onCaptureLocation,
    required this.onDelete,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withAlpha(135)),
          boxShadow: [
            BoxShadow(color: accentColor.withAlpha(38), blurRadius: 24),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(accentColor: accentColor),
              const SizedBox(height: 12),
              _EventDetailLine(
                icon: Icons.schedule_rounded,
                label: 'Data e hora',
                value: timestampLabel,
                color: accentColor,
              ),
              if ((update.authorName ?? '').isNotEmpty)
                _EventDetailLine(
                  icon: Icons.person_rounded,
                  label: 'Operador',
                  value: update.authorName!,
                  color: successColor,
                ),
              if (eventLocation.isNotEmpty)
                _EventDetailLine(
                  icon: Icons.location_on_rounded,
                  label: 'Local',
                  value: eventLocation,
                  color: warningColor,
                ),
              const SizedBox(height: 12),
              TacticalTextField(
                controller: titleController,
                labelText: 'Título do evento',
                prefixIcon: Icons.label_rounded,
              ),
              const SizedBox(height: 10),
              TacticalTextField(
                controller: descriptionController,
                labelText: 'Observação',
                prefixIcon: Icons.notes_rounded,
                maxLines: 4,
                minLines: 2,
              ),
              const SizedBox(height: 14),
              _EvidencePanel(
                panelColor: panelColor,
                accentColor: accentColor,
                successColor: successColor,
                warningColor: warningColor,
                eventAttachments: eventAttachments,
                pendingPhotoCount: pendingPhotoCount,
                onAddPhotos: onAddPhotos,
                onCaptureLocation: onCaptureLocation,
              ),
              const SizedBox(height: 14),
              _EventDetailsActions(
                backgroundColor: backgroundColor,
                accentColor: accentColor,
                dangerColor: dangerColor,
                onDelete: onDelete,
                onSave: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
