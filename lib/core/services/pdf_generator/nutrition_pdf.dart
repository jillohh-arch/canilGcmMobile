import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';

/// Gerador do PDF do Relatório Nutricional do Cão.
class NutritionPdf {
  static final _orange = PdfInstitutionalColors.orange;
  static final _textSecondary = PdfInstitutionalColors.textSecondary;
  static final _divider = PdfInstitutionalColors.divider;

  /// Gera os bytes do PDF de histórico nutricional.
  static Future<Uint8List> generate({
    required Dog dog,
    required List<Feeding> feedings,
    required NutritionPrescription? prescription,
    required double conformityPercent,
    required int conformCount,
    required int divergentCount,
  }) async {
    final pdf = pw.Document(
      author: 'Canil K9 GCM Limeira',
      title: 'Relatorio Nutricional - ${dog.name}',
    );

    final fonts = await PdfFonts.load();
    final docId = 'NUT-${dog.name.toUpperCase()}-${DateFormat('yyMM').format(DateTime.now())}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        header: (context) => PdfCommonWidgets.pageHeader(
          docType: 'RELATÓRIO NUTRICIONAL K9',
          docId: docId,
          fonts: fonts,
          color: _orange,
        ),
        footer: (context) => PdfCommonWidgets.pageFooter(
          context: context,
          docType: 'Nutrição e Alimentação',
          fonts: fonts,
        ),
        build: (context) {
          return [
            // --- HEADER ---
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 20),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          dog.name.toUpperCase(),
                          style: fonts.heading(color: _orange),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '${dog.breed} · ${dog.sex == 'M' ? 'MACHO' : 'FÊMEA'} · ${dog.weight != null ? "${dog.weight!.toStringAsFixed(1)} kg" : ""}',
                          style: fonts.bodyBold(color: _textSecondary),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: pw.BoxDecoration(
                      color: _orange.withAlpha(25),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text('CONFORMIDADE', style: fonts.label(color: _orange)),
                        pw.SizedBox(height: 2),
                        pw.Text('${conformityPercent.toStringAsFixed(0)}%', style: fonts.heading(color: _orange)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            PdfCommonWidgets.sectionTitle(title: 'PRESCRIÇÃO VIGENTE', fonts: fonts, color: _orange),
            pw.SizedBox(height: 8),

            prescription == null
                ? PdfCommonWidgets.card(
                    child: pw.Text(
                      'Nenhum laudo nutricional cadastrado para este cão.',
                      style: fonts.body(color: _textSecondary),
                    ),
                  )
                : PdfCommonWidgets.infoTable(
                    rows: [
                      MapEntry('Dose Diária', '${prescription.amountGramsPerDay}g / dia'),
                      MapEntry('Alimento', prescription.foodType),
                      MapEntry('Veterinário', 'Dr(a). ${prescription.vetName ?? "Não informado"}'),
                      MapEntry('CRMV', prescription.vetCrmv ?? 'Não informado'),
                      MapEntry('Vigência', 'Desde ${DateFormat('dd/MM/yyyy').format(prescription.vigentFrom)}'),
                    ],
                    fonts: fonts,
                  ),

            pw.SizedBox(height: 20),

            PdfCommonWidgets.sectionTitle(title: 'ESTATÍSTICAS DA CONFORMIDADE', fonts: fonts, color: _orange),
            pw.SizedBox(height: 8),

            PdfCommonWidgets.infoTable(
              rows: [
                MapEntry('Total de Refeições', '${feedings.length} registradas'),
                MapEntry('Refeições Conformes', '$conformCount (${conformityPercent.toStringAsFixed(0)}%)'),
                MapEntry('Refeições Divergentes', '$divergentCount (${(100 - conformityPercent).toStringAsFixed(0)}%)'),
              ],
              fonts: fonts,
            ),

            pw.SizedBox(height: 20),

            PdfCommonWidgets.sectionTitle(title: 'HISTÓRICO RECENTE DE REFEIÇÕES', fonts: fonts, color: _orange),
            pw.SizedBox(height: 8),

            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(color: _divider, width: 0.5),
              ),
              children: [
                // Table Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: PdfInstitutionalColors.lightGray,
                  ),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Data/Hora', style: fonts.label()),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Período', style: fonts.label()),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Servido', style: fonts.label()),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Status', style: fonts.label()),
                    ),
                  ],
                ),
                // Table Rows
                for (final f in feedings.take(25))
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(f.fedAt),
                          style: fonts.body(),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          f.period == 'manha'
                              ? 'Manhã'
                              : f.period == 'almoco'
                                  ? 'Almoço'
                                  : 'Noite',
                          style: fonts.body(),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          '${f.amountGrams}g',
                          style: fonts.bodyBold(),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(
                          f.divergencePercent.abs() > 10
                              ? 'Divergente (${f.divergencePercent > 0 ? "+" : ""}${f.divergencePercent.toStringAsFixed(0)}%)'
                              : 'Conforme',
                          style: fonts.bodyBold(
                            color: f.divergencePercent.abs() > 10
                                ? PdfInstitutionalColors.amberWarning
                                : PdfInstitutionalColors.greenInstitutional,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
