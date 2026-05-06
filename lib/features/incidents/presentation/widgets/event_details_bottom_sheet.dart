import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:canil_gcm/features/incidents/domain/incident.dart';
import 'package:canil_gcm/widgets/tactical_text_field.dart';

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
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(
                        'EXCLUIR',
                        style: GoogleFonts.robotoMono(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: dangerColor,
                        side: BorderSide(color: dangerColor.withAlpha(150)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onSave,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        'SALVAR',
                        style: GoogleFonts.robotoMono(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: backgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Color accentColor;

  const _Header({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: accentColor.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accentColor.withAlpha(120)),
          ),
          child: Icon(Icons.timeline_rounded, color: accentColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'DETALHES DO EVENTO',
            style: GoogleFonts.robotoMono(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: Colors.white54,
        ),
      ],
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  final Color panelColor;
  final Color accentColor;
  final Color successColor;
  final Color warningColor;
  final List<Map<String, dynamic>> eventAttachments;
  final int pendingPhotoCount;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onCaptureLocation;

  const _EvidencePanel({
    required this.panelColor,
    required this.accentColor,
    required this.successColor,
    required this.warningColor,
    required this.eventAttachments,
    required this.pendingPhotoCount,
    required this.onAddPhotos,
    required this.onCaptureLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelColor.withAlpha(220),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withAlpha(65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EVIDÊNCIAS DO EVENTO',
            style: GoogleFonts.robotoMono(
              color: accentColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (eventAttachments.isEmpty && pendingPhotoCount == 0)
            Text(
              'Nenhuma foto anexada a este evento.',
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            ...eventAttachments.map(
              (item) => _EventAttachmentRow(
                label: (item['caption'] as String?)?.trim().isNotEmpty == true
                    ? item['caption'] as String
                    : 'Foto sincronizada',
                icon: Icons.cloud_done_rounded,
                color: successColor,
              ),
            ),
            for (var i = 0; i < pendingPhotoCount; i++)
              _EventAttachmentRow(
                label: 'Foto pendente ${i + 1}',
                icon: Icons.photo_camera_rounded,
                color: warningColor,
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddPhotos,
                  icon: const Icon(Icons.add_a_photo_rounded),
                  label: Text(
                    'FOTO',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accentColor,
                    side: BorderSide(color: accentColor.withAlpha(150)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCaptureLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text(
                    'GPS',
                    style: GoogleFonts.robotoMono(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: warningColor,
                    side: BorderSide(color: warningColor.withAlpha(150)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventAttachmentRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _EventAttachmentRow({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _EventDetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: GoogleFonts.robotoMono(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
