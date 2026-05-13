part of 'media_attachment_gallery.dart';

class _PdfAttachment extends StatelessWidget {
  final String? pdfName;
  final VoidCallback onPickPdf;
  final VoidCallback onRemovePdf;

  const _PdfAttachment({
    required this.pdfName,
    required this.onPickPdf,
    required this.onRemovePdf,
  });

  @override
  Widget build(BuildContext context) {
    if (pdfName == null) {
      return _AttachPdfButton(onPressed: onPickPdf);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.picture_as_pdf_rounded,
            color: Colors.redAccent,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pdfName ?? 'arquivo.pdf',
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: onRemovePdf,
          ),
        ],
      ),
    );
  }
}

class _AttachPdfButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AttachPdfButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(
          Icons.upload_file_rounded,
          size: 16,
          color: Colors.redAccent,
        ),
        label: Text(
          'ANEXAR LAUDO (PDF)',
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.redAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}
