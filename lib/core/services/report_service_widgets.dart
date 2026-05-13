part of 'report_service.dart';

pw.Widget _buildReportHeader(
  String institution,
  pw.Font fontBlack,
  pw.Font fontBold,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 40,
            height: 40,
            decoration: const pw.BoxDecoration(
              color: PdfColors.grey800,
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                'K9',
                style: pw.TextStyle(
                  font: fontBlack,
                  fontSize: 11,
                  color: PdfColors.white,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                institution,
                style: pw.TextStyle(
                  font: fontBlack,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              pw.Text(
                'SISTEMA DE GESTÃO CANINA — RELATÓRIO OFICIAL',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 9,
                  color: PdfColors.grey600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget _buildReportFooter(pw.Context context, pw.Font font) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Documento de uso interno — não divulgar sem autorização',
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500),
      ),
      pw.Text(
        'Pág. ${context.pageNumber} / ${context.pagesCount}',
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500),
      ),
    ],
  );
}

pw.Widget _sectionDivider() {
  return pw.Container(height: 2, color: PdfColors.grey800);
}

pw.Widget _infoBlock(
  String label,
  String value,
  pw.Font bold,
  pw.Font regular,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          font: bold,
          fontSize: 8,
          color: PdfColors.grey600,
          letterSpacing: 0.8,
        ),
      ),
      pw.SizedBox(height: 3),
      pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 11)),
    ],
  );
}

pw.Widget _tableHeader(String text, pw.Font font) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: font,
        fontSize: 8,
        color: PdfColors.white,
        letterSpacing: 0.5,
      ),
    ),
  );
}

pw.Widget _tableCell(String text, pw.Font font) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey800),
    ),
  );
}
