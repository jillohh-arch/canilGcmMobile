import 'dart:typed_data';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

part 'report_service_entry.dart';
part 'report_service_formatters.dart';
part 'report_service_pdf_builder.dart';
part 'report_service_widgets.dart';

class ReportService {
  /// Gera o relatório tático formal de atividades em PDF.
  /// Use [Printing.layoutPdf] ou [Printing.sharePdf] com os bytes retornados.
  static Future<Uint8List> generateActivityReport({
    required Dog dog,
    required String conductorCallsign,
    required List<ReportEntry> entries,
    String institution = 'PREFEITURA MUNICIPAL — CANIL GCM',
    String period = '',
  }) {
    return _ActivityReportPdfBuilder(
      dog: dog,
      conductorCallsign: conductorCallsign,
      entries: entries,
      institution: institution,
      period: period,
    ).build();
  }
}
