part of 'media_attachment_gallery.dart';

class _AttachPhotoButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AttachPhotoButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.camera_alt, size: 16, color: Colors.white70),
      label: Text(
        'ANEXAR FOTO',
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.white12),
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
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const LinearProgressIndicator(color: Colors.white70),
        const SizedBox(height: 16),
      ],
    );
  }
}
