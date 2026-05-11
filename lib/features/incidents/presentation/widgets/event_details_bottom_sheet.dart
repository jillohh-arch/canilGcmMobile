import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/core/widgets/tactical_text_field.dart';

part 'event_details_bottom_sheet_header.dart';
part 'event_details_bottom_sheet_frame.dart';
part 'event_details_bottom_sheet_form.dart';
part 'event_details_bottom_sheet_meta.dart';
part 'event_details_bottom_sheet_evidence.dart';
part 'event_details_bottom_sheet_evidence_actions.dart';
part 'event_details_bottom_sheet_evidence_rows.dart';
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
    return _EventDetailsFrame(
      bottomInset: MediaQuery.of(context).viewInsets.bottom,
      backgroundColor: backgroundColor,
      accentColor: accentColor,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(accentColor: accentColor),
          const SizedBox(height: 12),
          _EventDetailsMetaList(
            update: update,
            timestampLabel: timestampLabel,
            eventLocation: eventLocation,
            accentColor: accentColor,
            successColor: successColor,
            warningColor: warningColor,
          ),
          const SizedBox(height: 12),
          _EventDetailsFormFields(
            titleController: titleController,
            descriptionController: descriptionController,
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
    );
  }
}
