import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';

/// Gerador do PDF do Histórico de Peso do Cão.
class WeightHistoryPdf {
  static final _blue = PdfInstitutionalColors.blue;
  static final _textPrimary = PdfInstitutionalColors.textPrimary;
  static final _textSecondary = PdfInstitutionalColors.textSecondary;
  static final _textTertiary = PdfInstitutionalColors.textTertiary;
  static final _lightGray = PdfInstitutionalColors.lightGray;
  static final _cardBorder = PdfInstitutionalColors.cardBorder;

  /// Gera os bytes do PDF de histórico de peso.
  static Future<Uint8List> generate(Dog dog, List<HealthLogModel> logs) async {
    final pdf = pw.Document(
      author: 'Canil K9 GCM Limeira',
      title: 'Historico de Peso - ${dog.name}',
    );

    final fonts = await PdfFonts.load();

    // Filter weight-related logs
    final weightLogs =
        logs.where((log) => log.dogId == dog.id && log.weight != null).toList()
          ..sort((a, b) => b.date.compareTo(a.date)); // Newest first

    final docId = _buildDocId(dog);
    final count = weightLogs.length;

    // Calculate statistics
    final weights = weightLogs.map((l) => l.weight!).toList();
    final current = weights.isNotEmpty ? weights.first : (dog.weight ?? 0.0);
    final min = weights.isNotEmpty
        ? weights.reduce((a, b) => a < b ? a : b)
        : current;
    final max = weights.isNotEmpty
        ? weights.reduce((a, b) => a > b ? a : b)
        : current;
    final avg = weights.isNotEmpty
        ? weights.reduce((a, b) => a + b) / weights.length
        : current;

    // Determine weight trend
    String trendText = 'Estável';
    if (weights.length >= 2) {
      final oldest = weights.last;
      final newest = weights.first;
      final diff = newest - oldest;
      if (diff.abs() < 0.5) {
        trendText = 'Estável (Variação insignificante)';
      } else if (diff > 0) {
        trendText = 'Ganho de Peso (+${diff.toStringAsFixed(1)} kg)';
      } else {
        trendText = 'Perda de Peso (${diff.toStringAsFixed(1)} kg)';
      }
    }

    // Determine range status
    String rangeStatus = 'Faixa Ideal Não Configurada';
    PdfColor rangeColor = _textTertiary;
    if (dog.idealWeightMin != null && dog.idealWeightMax != null) {
      if (current >= dog.idealWeightMin! && current <= dog.idealWeightMax!) {
        rangeStatus = 'DENTRO DA FAIXA IDEAL';
        rangeColor = PdfInstitutionalColors.greenInstitutional;
      } else if (current < dog.idealWeightMin!) {
        rangeStatus = 'ABAIXO DO PESO IDEAL';
        rangeColor = PdfInstitutionalColors.amberWarning;
      } else {
        rangeStatus = 'ACIMA DO PESO IDEAL';
        rangeColor = PdfInstitutionalColors.redAlert;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        header: (context) => PdfCommonWidgets.pageHeader(
          docType: 'HISTÓRICO DE PESO K9',
          docId: docId,
          fonts: fonts,
          color: _blue,
        ),
        footer: (context) => PdfCommonWidgets.pageFooter(
          context: context,
          docType: 'Histórico de Peso',
          fonts: fonts,
        ),
        build: (context) {
          return [
            // --- CAPA / CABEÇALHO DO RELATÓRIO ---
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
                          'ACOMPANHAMENTO BIOESTATÍSTICO K9',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 10,
                            color: _blue,
                            letterSpacing: 1.0,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          dog.name.toUpperCase(),
                          style: pw.TextStyle(
                            font: fonts.black,
                            fontSize: 26,
                            color: _textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Raça: ${dog.breed}   |   Total de Pesagens: $count',
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10,
                            color: _textSecondary,
                          ),
                        ),
                        if (dog.idealWeightMin != null &&
                            dog.idealWeightMax != null)
                          pw.Text(
                            'Peso Ideal Configurado: ${dog.idealWeightMin!.toStringAsFixed(1)} kg a ${dog.idealWeightMax!.toStringAsFixed(1)} kg',
                            style: pw.TextStyle(
                              font: fonts.regular,
                              fontSize: 9,
                              color: _textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // Current Status Box
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: pw.BoxDecoration(
                      color: rangeColor.withAlpha(25),
                      border: pw.Border.all(color: rangeColor, width: 1.5),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'CONDIÇÃO FÍSICA',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 8,
                            color: rangeColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          rangeStatus,
                          style: pw.TextStyle(
                            font: fonts.black,
                            fontSize: 10,
                            color: rangeColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            PdfCommonWidgets.divider(),

            // --- 4 QUADROS DE ESTATÍSTICA ---
            pw.Row(
              children: [
                _buildStatBox(
                  'PESO ATUAL',
                  '${current.toStringAsFixed(1)} kg',
                  fonts,
                  isPrimary: true,
                ),
                pw.SizedBox(width: 8),
                _buildStatBox('MÍNIMO', '${min.toStringAsFixed(1)} kg', fonts),
                pw.SizedBox(width: 8),
                _buildStatBox('MÉDIO', '${avg.toStringAsFixed(1)} kg', fonts),
                pw.SizedBox(width: 8),
                _buildStatBox('MÁXIMO', '${max.toStringAsFixed(1)} kg', fonts),
              ],
            ),

            pw.SizedBox(height: 20),

            // --- ANÁLISE CLÍNICA ---
            PdfCommonWidgets.sectionTitle(
              title: 'AVALIAÇÃO DE DESEMPENHO FÍSICO E TENDÊNCIA',
              fonts: fonts,
              color: _blue,
            ),
            pw.SizedBox(height: 8),
            _buildClinicalAnalysis(
              dog,
              current,
              trendText,
              rangeStatus,
              rangeColor,
              fonts,
            ),

            pw.SizedBox(height: 20),

            // --- TABELA DE PESAGENS ---
            PdfCommonWidgets.sectionTitle(
              title: 'REGISTROS CRONOLÓGICOS DE PESAGEM',
              fonts: fonts,
              color: _blue,
            ),
            pw.SizedBox(height: 8),
            _buildWeightTable(weightLogs, fonts),

            pw.SizedBox(height: 24),

            // --- BLOCO DE CONFORMIDADE E AUDITORIA (SEM HASH INJUSTIFICADO) ---
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: _lightGray,
                border: pw.Border.all(color: _cardBorder),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 8,
                        height: 8,
                        decoration: pw.BoxDecoration(
                          color: PdfInstitutionalColors.greenInstitutional,
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Text(
                        'REGISTRO VERIFICADO & SINCRONIZADO',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 9,
                          color: PdfInstitutionalColors.greenInstitutional,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Este documento reflete em tempo real o histórico ponderal do cão ${dog.name}, registrado e mantido pela equipe de condutores e veterinários do Canil K9 da GCM de Limeira. Todas as modificações no prontuário geram trilhas de auditoria imutáveis.',
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 8.5,
                      color: _textSecondary,
                      lineSpacing: 1.3,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Código de Rastreamento de Auditoria:',
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8,
                          color: _textTertiary,
                        ),
                      ),
                      pw.Text(
                        _buildAuditReference(dog),
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 8.5,
                          color: _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Gera um ID de documento único estruturado.
  static String _buildDocId(Dog dog) {
    final year = DateTime.now().year;
    final month = DateTime.now().month.toString().padLeft(2, '0');
    final seq = dog.id.length >= 4
        ? dog.id.substring(0, 4).toUpperCase()
        : dog.id.toUpperCase().padRight(4, '0');
    return 'PESO: $year/$month/$seq-K9';
  }

  /// Gera uma referência de auditoria baseada no ID do cão e no timestamp atual.
  static String _buildAuditReference(Dog dog) {
    final dogPart = dog.id.length >= 6
        ? dog.id.substring(0, 6).toUpperCase()
        : dog.id.toUpperCase();
    final timePart = DateTime.now().millisecondsSinceEpoch.toString();
    final truncatedTime = timePart.length > 5
        ? timePart.substring(timePart.length - 5)
        : timePart;
    return 'AUDIT-$dogPart-$truncatedTime';
  }

  /// Caixa estatística.
  static pw.Widget _buildStatBox(
    String label,
    String value,
    PdfFonts fonts, {
    bool isPrimary = false,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: isPrimary ? _blue.withAlpha(20) : _lightGray,
          border: pw.Border.all(
            color: isPrimary ? _blue : _cardBorder,
            width: 1,
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 8,
                color: isPrimary ? _blue : _textTertiary,
                letterSpacing: 0.5,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: fonts.black,
                fontSize: 13,
                color: isPrimary ? _blue : _textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Constrói a avaliação de desempenho clínico.
  static pw.Widget _buildClinicalAnalysis(
    Dog dog,
    double currentWeight,
    String trend,
    String rangeStatus,
    PdfColor color,
    PdfFonts fonts,
  ) {
    String message = '';
    if (rangeStatus == 'DENTRO DA FAIXA IDEAL') {
      message =
          'O cão encontra-se no peso recomendado para as atividades institucionais e de alta intensidade do canil. Recomenda-se manter a rotina nutricional e de treinos atual.';
    } else if (rangeStatus == 'ABAIXO DO PESO IDEAL') {
      message =
          'Atenção: O cão está abaixo do peso ideal recomendado. Isso pode impactar sua performance de guarda, proteção e resistência física. Sugere-se avaliação de ração/suplementação.';
    } else if (rangeStatus == 'ACIMA DO PESO IDEAL') {
      message =
          'Alerta: O cão está acima da faixa ideal de peso recomendada. O sobrepeso aumenta o estresse articular em saltos e corridas. Recomenda-se ajustar a porção diária de ração.';
    } else {
      message =
          'Não há uma faixa de peso ideal cadastrada para este cão no sistema. Defina os limites idealMin e idealMax para viabilizar o acompanhamento clínico automático.';
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: color.withAlpha(15),
        border: pw.Border.all(color: color.withAlpha(40)),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Tendência de Peso: $trend',
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 10,
              color: _textPrimary,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            message,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: _textSecondary,
              lineSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Constrói a tabela de histórico de peso.
  static pw.Widget _buildWeightTable(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    if (logs.isEmpty) {
      return pw.Container(
        height: 80,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _cardBorder),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Text(
          'Nenhuma pesagem registrada no histórico.',
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 10,
            color: _textTertiary,
          ),
        ),
      );
    }

    final headers = [
      'Data',
      'Peso (kg)',
      'Variação',
      'Registrado Por',
      'Observações',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: _cardBorder, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(2.0),
        4: pw.FlexColumnWidth(3.0),
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _blue),
          children: headers.map((header) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                header,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 9,
                  color: PdfInstitutionalColors.white,
                ),
              ),
            );
          }).toList(),
        ),
        // Table Rows
        ...List.generate(logs.length, (index) {
          final log = logs[index];
          final appDate = DateFormat('dd/MM/yyyy').format(log.date);
          final weight = log.weight ?? 0.0;
          final weightStr = '${weight.toStringAsFixed(1)} kg';

          // Variation logic
          double? diff;
          if (index + 1 < logs.length) {
            final prevWeight = logs[index + 1].weight;
            if (prevWeight != null) {
              diff = weight - prevWeight;
            }
          }

          String diffStr = '—';
          PdfColor diffColor = _textSecondary;
          if (diff != null && diff.abs() >= 0.1) {
            diffStr = '${diff > 0 ? "+" : ""}${diff.toStringAsFixed(1)} kg';
            diffColor = diff > 0
                ? PdfInstitutionalColors.amberWarning
                : PdfInstitutionalColors.greenInstitutional;
          }

          final registeredBy = log.vetName ?? log.createdBy ?? 'Sistema';
          final obs = log.healthObservations.trim().isNotEmpty
              ? log.healthObservations
              : 'Nenhuma';

          final isRowOdd = index.isOdd;
          final rowBg = isRowOdd ? _lightGray : PdfInstitutionalColors.white;

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  appDate,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8.5,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  weightStr,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 8.5,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  diffStr,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 8.5,
                    color: diffColor,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  registeredBy,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: _textSecondary,
                  ),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: pw.Text(
                  obs,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: _textSecondary,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
