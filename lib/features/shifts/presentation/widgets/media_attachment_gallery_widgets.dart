part of 'media_attachment_gallery.dart';

class _MediaAttachmentSectionLabel extends StatelessWidget {
  const _MediaAttachmentSectionLabel();

  @override
  Widget build(BuildContext context) {
    return Text(
      'ANEXOS PERICIAIS / FOTOS',
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: Colors.white54,
        letterSpacing: 1,
      ),
    );
  }
}
