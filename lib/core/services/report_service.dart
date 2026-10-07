import 'dart:typed_data';

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'pdf_generator/pdf_colors.dart';
import 'pdf_generator/training_tactical_pdf.dart';

part 'report_service_entry.dart';
part 'report_service_formatters.dart';
part 'report_service_pdf_builder.dart';
part 'report_service_widgets.dart';

class ReportService {
  /// Gera o relatório tático formal de atividades em PDF.
  /// Delegado para o gerador canônico F70 [TrainingTacticalPdf].
  static Future<Uint8List> generateActivityReport({
    required Dog dog,
    required String conductorCallsign,
    required List<ReportEntry> entries,
    String institution = 'PREFEITURA MUNICIPAL — CANIL GCM',
    String period = '',
  }) {
    return TrainingTacticalPdf.generate(
      dog: dog,
      conductorCallsign: conductorCallsign,
      entries: entries,
      period: period,
    );
  }
}
