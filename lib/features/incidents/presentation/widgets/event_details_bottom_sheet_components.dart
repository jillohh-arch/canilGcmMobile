part of 'event_details_bottom_sheet.dart';

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

class _EventDetailsActions extends StatelessWidget {
  final Color backgroundColor;
  final Color accentColor;
  final Color dangerColor;
  final VoidCallback onDelete;
  final Future<void> Function() onSave;

  const _EventDetailsActions({
    required this.backgroundColor,
    required this.accentColor,
    required this.dangerColor,
    required this.onDelete,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EventOutlineActionButton(
            label: 'EXCLUIR',
            icon: Icons.delete_outline_rounded,
            color: dangerColor,
            onPressed: onDelete,
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
    );
  }
}

class _EventOutlineActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _EventOutlineActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(
        label,
        style: GoogleFonts.robotoMono(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withAlpha(150)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
