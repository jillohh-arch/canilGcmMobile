import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_colors.dart';

/// Fontes carregadas para uso nos PDFs institucionais.
class PdfFonts {
  final pw.Font regular;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font black;

  const PdfFonts({
    required this.regular,
    required this.medium,
    required this.bold,
    required this.black,
  });

  static Future<PdfFonts> load() async {
    return PdfFonts(
      regular: await PdfGoogleFonts.interRegular(),
      medium: await PdfGoogleFonts.interMedium(),
      bold: await PdfGoogleFonts.interBold(),
      black: await PdfGoogleFonts.interExtraBold(),
    );
  }

  pw.TextStyle body({PdfColor? color}) => pw.TextStyle(
        font: regular,
        fontSize: 10,
        color: color ?? PdfInstitutionalColors.textPrimary,
      );

  pw.TextStyle bodyBold({PdfColor? color}) => pw.TextStyle(
        font: bold,
        fontSize: 10,
        color: color ?? PdfInstitutionalColors.textPrimary,
      );

  pw.TextStyle caption({PdfColor? color}) => pw.TextStyle(
        font: regular,
        fontSize: 9,
        color: color ?? PdfInstitutionalColors.textTertiary,
      );

  pw.TextStyle label({PdfColor? color}) => pw.TextStyle(
        font: bold,
        fontSize: 8,
        color: color ?? PdfInstitutionalColors.textTertiary,
        letterSpacing: 1.0,
      );

  pw.TextStyle sectionTitle({PdfColor? color}) => pw.TextStyle(
        font: bold,
        fontSize: 13,
        color: color ?? PdfInstitutionalColors.textPrimary,
      );

  pw.TextStyle heading({PdfColor? color}) => pw.TextStyle(
        font: black,
        fontSize: 24,
        color: color ?? PdfInstitutionalColors.textPrimary,
      );

  pw.TextStyle mono({PdfColor? color, double? fontSize}) => pw.TextStyle(
        font: regular,
        fontSize: fontSize ?? 8,
        color: color ?? PdfInstitutionalColors.textTertiary,
      );
}

/// Widgets reutilizáveis para PDFs institucionais.
class PdfCommonWidgets {
  PdfCommonWidgets._();

  /// Header padrão de páginas internas.
  static pw.Widget pageHeader({
    required String docType,
    required String docId,
    required PdfFonts fonts,
    PdfColor? color,
  }) {
    final c = color ?? PdfInstitutionalColors.cyan;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: c, width: 2)),
      ),
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        children: [
          pw.Container(
            width: 20,
            height: 20,
            decoration: pw.BoxDecoration(color: c, shape: pw.BoxShape.circle),
            child: pw.Center(
              child: pw.Text(
                'K9',
                style: pw.TextStyle(
                  font: fonts.black,
                  fontSize: 7,
                  color: PdfColors.white,
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            'GCM LIMEIRA · $docType',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 10,
              color: c,
              letterSpacing: 1,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            docId,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 9,
              color: PdfInstitutionalColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Footer padrão de páginas internas.
  static pw.Widget pageFooter({
    required pw.Context context,
    required String docType,
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfInstitutionalColors.divider, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'GCM Limeira · Canil K9 · $docType',
            style: fonts.caption(),
          ),
          pw.Text(
            'Pág. ${context.pageNumber} / ${context.pagesCount}',
            style: fonts.caption(),
          ),
        ],
      ),
    );
  }

  /// Título de seção com linha colorida à esquerda.
  static pw.Widget sectionTitle({
    required String title,
    required PdfFonts fonts,
    PdfColor? color,
  }) {
    final c = color ?? PdfInstitutionalColors.cyan;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(left: 10, top: 4, bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: c, width: 3)),
      ),
      child: pw.Text(title, style: fonts.sectionTitle(color: c)),
    );
  }

  /// Linha de tabela informativa (label: value).
  static pw.Widget infoRow({
    required String label,
    required String value,
    required PdfFonts fonts,
    bool alternate = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: alternate ? PdfInstitutionalColors.background : PdfInstitutionalColors.lightGray,
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: fonts.label()),
          ),
          pw.Expanded(
            child: pw.Text(value, style: fonts.bodyBold()),
          ),
        ],
      ),
    );
  }

  /// Tabela informativa com borda e linhas alternadas.
  static pw.Widget infoTable({
    required List<MapEntry<String, String>> rows,
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfInstitutionalColors.cardBorder),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 4,
        verticalRadius: 4,
        child: pw.Column(
          children: [
            for (int i = 0; i < rows.length; i++)
              infoRow(
                label: rows[i].key,
                value: rows[i].value,
                fonts: fonts,
                alternate: i.isOdd,
              ),
          ],
        ),
      ),
    );
  }

  /// Card com fundo cinza claro e borda.
  static pw.Widget card({required pw.Widget child, PdfColor? borderColor}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfInstitutionalColors.lightGray,
        border: pw.Border.all(
          color: borderColor ?? PdfInstitutionalColors.cardBorder,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: child,
    );
  }

  /// Divider horizontal sutil.
  static pw.Widget divider() {
    return pw.Container(
      height: 1,
      color: PdfInstitutionalColors.divider,
      margin: const pw.EdgeInsets.symmetric(vertical: 12),
    );
  }
}
