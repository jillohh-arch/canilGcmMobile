import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/dog.dart';

// Generic activity entry used for the report table
class ReportEntry {
  final DateTime date;
  final String type;
  final String location;
  final String observations;
  const ReportEntry({
    required this.date,
    required this.type,
    required this.location,
    required this.observations,
  });
}

class ReportService {
  /// Generates a formal tactical activity report PDF.
  /// Call [Printing.layoutPdf] or [Printing.sharePdf] with the returned bytes.
  static Future<Uint8List> generateActivityReport({
    required Dog dog,
    required String conductorCallsign,
    required List<ReportEntry> entries,
    String institution = 'PREFEITURA MUNICIPAL — CANIL GCM',
    String period = '',
  }) async {
    final pdf = pw.Document();

    // ── Load font ────────────────────────────────────────────────────────────
    final font      = await PdfGoogleFonts.interRegular();
    final fontBold  = await PdfGoogleFonts.interBold();
    final fontBlack = await PdfGoogleFonts.interExtraBold();

    // Sort entries by date ascending
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));

    // ── Page ────────────────────────────────────────────────────────────────
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
        header: (ctx) => _buildHeader(institution, fontBlack, fontBold),
        footer: (ctx) => _buildFooter(ctx, font),
        build: (ctx) => [
          _sectionDivider(),
          pw.SizedBox(height: 12),

          // ── Dog & Conductor block ──────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoBlock('CÃO K9', dog.name.toUpperCase(), fontBold, font),
                pw.SizedBox(width: 24),
                _infoBlock('MATRÍCULA', dog.registrationNumber ?? 'N/A', fontBold, font),
                pw.SizedBox(width: 24),
                _infoBlock('RAÇA', dog.breed, fontBold, font),
                pw.SizedBox(width: 24),
                _infoBlock('CONDUTOR', conductorCallsign, fontBold, font),
                pw.Spacer(),
                _infoBlock('PERÍODO', period.isNotEmpty ? period : _formatDate(DateTime.now()), fontBold, font),
              ],
            ),
          ),

          pw.SizedBox(height: 20),
          pw.Text(
            'RELATÓRIO DE ATIVIDADES TÁTICAS',
            style: pw.TextStyle(font: fontBlack, fontSize: 13, color: PdfColors.grey800, letterSpacing: 1.5),
          ),
          pw.SizedBox(height: 10),

          // ── Activity Table ─────────────────────────────────────────────
          pw.Table(
            columnWidths: {
              0: const pw.FixedColumnWidth(72),  // Date
              1: const pw.FixedColumnWidth(42),  // Time
              2: const pw.FlexColumnWidth(1.2),  // Type
              3: const pw.FlexColumnWidth(1.5),  // Location
              4: const pw.FlexColumnWidth(2.5),  // Observations
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              // Header row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                children: ['DATA', 'HORA', 'TIPO', 'LOCAL', 'OBSERVAÇÕES']
                    .map((h) => _tableHeader(h, fontBold))
                    .toList(),
              ),
              // Data rows
              ...sorted.asMap().entries.map((entry) {
                final odd = entry.key.isOdd;
                final e   = entry.value;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: odd ? PdfColors.grey50 : PdfColors.white),
                  children: [
                    _tableCell(_formatDate(e.date), font),
                    _tableCell('${e.date.hour.toString().padLeft(2,'0')}:${e.date.minute.toString().padLeft(2,'0')}', font),
                    _tableCell(e.type, font),
                    _tableCell(e.location, font),
                    _tableCell(e.observations, font),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 20),
          pw.Text(
            'Total de registros: ${sorted.length}',
            style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 48),

          // ── Signature block ────────────────────────────────────────────
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(height: 1, color: PdfColors.grey700),
                    pw.SizedBox(height: 6),
                    pw.Text('Assinatura do GCM Responsável', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
                    pw.SizedBox(height: 2),
                    pw.Text(conductorCallsign.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 11)),
                  ],
                ),
              ),
              pw.SizedBox(width: 40),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(height: 1, color: PdfColors.grey700),
                    pw.SizedBox(height: 6),
                    pw.Text('Data / Hora do Relatório', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
                    pw.SizedBox(height: 2),
                    pw.Text(_formatDate(DateTime.now()), style: pw.TextStyle(font: fontBold, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static pw.Widget _buildHeader(String institution, pw.Font fontBlack, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Shield icon placeholder
            pw.Container(
              width: 40, height: 40,
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey800,
                shape: pw.BoxShape.circle,
              ),
              child: pw.Center(
                child: pw.Text('K9', style: pw.TextStyle(font: fontBlack, fontSize: 11, color: PdfColors.white)),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(institution, style: pw.TextStyle(font: fontBlack, fontSize: 13, letterSpacing: 1)),
                pw.Text('SISTEMA DE GESTÃO CANINA — RELATÓRIO OFICIAL', style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.grey600, letterSpacing: 0.8)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context ctx, pw.Font font) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Documento de uso interno — não divulgar sem autorização', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
        pw.Text('Pág. ${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey500)),
      ],
    );
  }

  static pw.Widget _sectionDivider() => pw.Container(height: 2, color: PdfColors.grey800);

  static pw.Widget _infoBlock(String label, String value, pw.Font bold, pw.Font regular) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 8, color: PdfColors.grey600, letterSpacing: 0.8)),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 11)),
      ],
    );
  }

  static pw.Widget _tableHeader(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white, letterSpacing: 0.5),
      ),
    );
  }

  static pw.Widget _tableCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey800)),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
}
