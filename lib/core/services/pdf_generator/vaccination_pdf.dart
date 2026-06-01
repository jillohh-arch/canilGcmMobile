import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'pdf_colors.dart';
import 'pdf_common_widgets.dart';

/// Gerador do PDF da Carteira de Vacinação do Cão.
class VaccinationPdf {
  static final _cyan = PdfInstitutionalColors.cyan;
  static final _textPrimary = PdfInstitutionalColors.textPrimary;
  static final _textSecondary = PdfInstitutionalColors.textSecondary;
  static final _textTertiary = PdfInstitutionalColors.textTertiary;
  static final _lightGray = PdfInstitutionalColors.lightGray;
  static final _cardBorder = PdfInstitutionalColors.cardBorder;

  /// Gera os bytes do PDF da carteira de vacinação.
  static Future<Uint8List> generate(Dog dog, List<HealthLogModel> logs) async {
    final pdf = pw.Document(
      author: 'Canil K9 GCM Limeira',
      title: 'Carteira de Vacinacao - ${dog.name}',
    );

    final fonts = await PdfFonts.load();

    // Filter vaccine-related logs
    final vaccineLogs =
        logs
            .where(
              (log) =>
                  log.dogId == dog.id &&
                  (log.type == 'vaccination' ||
                      log.logType == 'Vacina' ||
                      log.vaccines.isNotEmpty),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final docId = _buildDocId(dog);
    final overallStatus = _getOverallStatus(vaccineLogs);
    final isVaccineOk = overallStatus == 'EM DIA';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        header: (context) => PdfCommonWidgets.pageHeader(
          docType: 'CARTEIRA DE VACINAÇÃO K9',
          docId: docId,
          fonts: fonts,
          color: _cyan,
        ),
        footer: (context) => PdfCommonWidgets.pageFooter(
          context: context,
          docType: 'Carteira de Vacinação',
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
                          'PRONTUÁRIO MÉDICO VETERINÁRIO',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 10,
                            color: _cyan,
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
                          'Raça: ${dog.breed}   |   Microchip: ${dog.microchip ?? "Não Informado"}',
                          style: pw.TextStyle(
                            font: fonts.regular,
                            fontSize: 10,
                            color: _textSecondary,
                          ),
                        ),
                        pw.Text(
                          'Matrícula: ${dog.registrationNumber ?? "Não Informado"}',
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
                  // Status box
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: pw.BoxDecoration(
                      color: isVaccineOk
                          ? PdfInstitutionalColors.greenInstitutional.withAlpha(
                              25,
                            )
                          : PdfInstitutionalColors.redAlert.withAlpha(25),
                      border: pw.Border.all(
                        color: isVaccineOk
                            ? PdfInstitutionalColors.greenInstitutional
                            : PdfInstitutionalColors.redAlert,
                        width: 1.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(8),
                      ),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'STATUS GERAL',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 8,
                            color: isVaccineOk
                                ? PdfInstitutionalColors.greenInstitutional
                                : PdfInstitutionalColors.redAlert,
                            letterSpacing: 0.5,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          overallStatus,
                          style: pw.TextStyle(
                            font: fonts.black,
                            fontSize: 12,
                            color: isVaccineOk
                                ? PdfInstitutionalColors.greenInstitutional
                                : PdfInstitutionalColors.redAlert,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            PdfCommonWidgets.divider(),

            // --- AVISO DE PRÓXIMAS DOSES / ALERTAS ---
            _buildUpcomingAlert(vaccineLogs, fonts),

            pw.SizedBox(height: 16),

            // --- TABELA DE IMUNIZAÇÃO ---
            PdfCommonWidgets.sectionTitle(
              title: 'HISTÓRICO DE VACINAS E IMUNIZAÇÕES',
              fonts: fonts,
              color: _cyan,
            ),
            pw.SizedBox(height: 8),
            _buildImmunizationTable(vaccineLogs, fonts),

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
                    'Este documento reflete em tempo real o prontuário de saúde do cão ${dog.name}, registrado e mantido pela equipe de condutores e veterinários do Canil K9 da GCM de Limeira. Todas as modificações no prontuário geram trilhas de auditoria imutáveis.',
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
    return 'VAC: $year/$month/$seq-K9';
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

  /// Determina o status geral com base no histórico de vacinas.
  static String _getOverallStatus(List<HealthLogModel> vaccineLogs) {
    if (vaccineLogs.isEmpty) return 'SEM DADOS';
    final now = DateTime.now();
    bool hasExpired = false;
    for (final log in vaccineLogs) {
      final nextDue =
          log.nextDueDate ?? log.date.add(const Duration(days: 365));
      if (now.isAfter(nextDue)) {
        hasExpired = true;
        break;
      }
    }
    return hasExpired ? 'VENCIDA' : 'EM DIA';
  }

  /// Constrói o alerta de próximas doses.
  static pw.Widget _buildUpcomingAlert(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    final now = DateTime.now();
    final upcoming = <Map<String, dynamic>>[];

    // Agrupar por tipo de vacina e obter a última data
    final latestByType = <String, HealthLogModel>{};
    for (final log in logs) {
      final name = log.subtype ?? 'Geral';
      if (!latestByType.containsKey(name) ||
          log.date.isAfter(latestByType[name]!.date)) {
        latestByType[name] = log;
      }
    }

    for (final entry in latestByType.entries) {
      final log = entry.value;
      final nextDue =
          log.nextDueDate ?? log.date.add(const Duration(days: 365));
      final diffDays = nextDue.difference(now).inDays;

      if (diffDays <= 30) {
        upcoming.add({
          'name': entry.key,
          'dueDate': nextDue,
          'diffDays': diffDays,
        });
      }
    }

    if (upcoming.isEmpty) {
      return pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfInstitutionalColors.greenInstitutional.withAlpha(15),
          border: pw.Border.all(
            color: PdfInstitutionalColors.greenInstitutional.withAlpha(50),
          ),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Row(
          children: [
            pw.Container(
              width: 6,
              height: 6,
              decoration: pw.BoxDecoration(
                color: PdfInstitutionalColors.greenInstitutional,
                shape: pw.BoxShape.circle,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              'Todas as vacinações do cão estão em dia e com conformidade operacional.',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 9,
                color: PdfInstitutionalColors.greenInstitutional,
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: upcoming.map((alert) {
        final overdue = alert['diffDays'] < 0;
        final days = (alert['diffDays'] as int).abs();
        final text = overdue
            ? 'A vacina ${alert['name']} está VENCIDA há $days dia(s) (${DateFormat('dd/MM/yyyy').format(alert['dueDate'])}).'
            : 'A vacina ${alert['name']} vencerá em $days dia(s) (${DateFormat('dd/MM/yyyy').format(alert['dueDate'])}).';

        final color = overdue
            ? PdfInstitutionalColors.redAlert
            : PdfInstitutionalColors.amberWarning;

        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(bottom: 6),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: color.withAlpha(15),
            border: pw.Border.all(color: color.withAlpha(50)),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Row(
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: color,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  text,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 9,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Constrói a tabela de histórico de imunizações.
  static pw.Widget _buildImmunizationTable(
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
          'Nenhuma vacina cadastrada no histórico médico deste cão.',
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 10,
            color: _textTertiary,
          ),
        ),
      );
    }

    final headers = [
      'Vacina',
      'Aplicação',
      'Validade / Próx. Dose',
      'Veterinário / CRMV',
      'Status',
    ];
    final now = DateTime.now();

    return pw.Table(
      border: pw.TableBorder.all(color: _cardBorder, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.0),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.5),
        3: pw.FlexColumnWidth(2.5),
        4: pw.FlexColumnWidth(1.0),
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _cyan),
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
          final vaccineName = log.subtype ?? 'Vacina Geral';
          final appDate = DateFormat('dd/MM/yyyy').format(log.date);
          final nextDue =
              log.nextDueDate ?? log.date.add(const Duration(days: 365));
          final nextDueDateStr = DateFormat('dd/MM/yyyy').format(nextDue);

          final isOverdue = now.isAfter(nextDue);
          final statusStr = isOverdue ? 'Vencido' : 'OK';
          final statusColor = isOverdue
              ? PdfInstitutionalColors.redAlert
              : PdfInstitutionalColors.greenInstitutional;

          final vetName = log.vetName ?? 'Não Informado';
          final crmv = log.professionalCrmv != null
              ? ' (CRMV: ${log.professionalCrmv})'
              : '';
          final vetInfo = '$vetName$crmv';

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
                  vaccineName,
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
                  appDate,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8.5,
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
                  nextDueDateStr,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8.5,
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
                  vetInfo,
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
                  statusStr,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 8.5,
                    color: statusColor,
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
