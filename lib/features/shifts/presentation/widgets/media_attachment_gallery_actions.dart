part of 'media_attachment_gallery.dart';

class _AttachPhotoButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AttachPhotoButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        Icons.camera_alt,
        size: 16,
        color: AppTheme.textPrimary.withAlpha(179),
      ),
      label: Text(
        'ANEXAR FOTO',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary.withAlpha(179),
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppTheme.textPrimary.withAlpha(31)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _CompressionStatus extends StatelessWidget {
  const _CompressionStatus();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMPRIMINDO IMAGEM...',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary.withAlpha(179),
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(color: AppTheme.textPrimary.withAlpha(179)),
        const SizedBox(height: 16),
      ],
    );
  }
}
