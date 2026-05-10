part of 'event_details_bottom_sheet.dart';

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
          _EvidenceActions(
            accentColor: accentColor,
            warningColor: warningColor,
            onAddPhotos: onAddPhotos,
            onCaptureLocation: onCaptureLocation,
          ),
        ],
      ),
    );
  }
}

class _EvidenceActions extends StatelessWidget {
  final Color accentColor;
  final Color warningColor;
  final Future<void> Function() onAddPhotos;
  final Future<void> Function() onCaptureLocation;

  const _EvidenceActions({
    required this.accentColor,
    required this.warningColor,
    required this.onAddPhotos,
    required this.onCaptureLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EventOutlineActionButton(
            label: 'FOTO',
            icon: Icons.add_a_photo_rounded,
            color: accentColor,
            onPressed: onAddPhotos,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _EventOutlineActionButton(
            label: 'GPS',
            icon: Icons.my_location_rounded,
            color: warningColor,
            onPressed: onCaptureLocation,
          ),
        ),
      ],
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
