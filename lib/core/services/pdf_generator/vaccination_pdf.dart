import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/health/domain/health_log_model.dart';
import 'pdf_common_widgets.dart';
import 'template/template.dart';

/// Gerador do PDF da Carteira de Vacinação do Cão baseado na Foundation F70 Oficial.
class VaccinationPdf {
  /// Gera os bytes do PDF da carteira de vacinação.
  static Future<Uint8List> generate(Dog dog, List<HealthLogModel> logs) async {
    final fonts = await PdfFonts.load();

    // Filtra logs de vacinação do cão (preservando ordenação decrescente de data)
    final vaccineLogs = logs
        .where(
          (log) =>
              log.dogId == dog.id &&
              (log.type == 'vaccination' ||
                  log.logType == 'Vacina' ||
                  log.vaccines.isNotEmpty),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final overallStatus = _getOverallStatus(vaccineLogs);
    final overallTone = switch (overallStatus) {
      'EM DIA' => ReportTone.positive,
      'VENCIDA' => ReportTone.critical,
      'REGISTRADA' => ReportTone.positive,
      _ => ReportTone.neutral,
    };

    final now = DateTime.now();

    final metadata = ReportMetadata(
      generatedAt: now,
      dogIdentity: '${dog.name} (${dog.breed})',
      operatorName: dog.conductorRa != null ? 'Condutor RA: ${dog.conductorRa}' : null,
    );

    final builder = ReportTemplateBuilder(
      title: 'CARTEIRA DE VACINAÇÃO K9',
      subtitle: 'REGISTRO SANITÁRIO E CONTROLE DE IMUNOBIOLÓGICOS',
      category: 'PRONTUÁRIO MÉDICO VETERINÁRIO',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      statusLabel: overallStatus,
      statusTone: overallTone,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig(
        archetype: ReportArchetype.clinical,
        name: 'Carteira de Vacinação',
        headerVariant: HeaderVariant.darkTactical,
      ),
    );

    // 1. Card de Identidade Canina (com foto/avatar e tags de Cão de Trabalho)
    builder.addWidget(
      ReportPrimitives.entityIdentityBlock(
        EntityIdentityData(
          title: dog.name.toUpperCase(),
          subtitle: 'Raça: ${dog.breed}',
          tags: [
            'CÃO DE TRABALHO',
            if (dog.specialties != null) ...dog.specialties!,
          ],
          statusLabel: dog.status.toUpperCase(),
          statusTone: dog.status.toLowerCase() == 'ativo'
              ? ReportTone.positive
              : ReportTone.neutral,
          avatarPlaceholder: dog.name.isNotEmpty
              ? dog.name.substring(0, dog.name.length >= 2 ? 2 : 1).toUpperCase()
              : 'K9',
          fields: [
            EntityIdentityField(
              label: 'Microchip',
              value: dog.microchip ?? 'Não informado',
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Matrícula',
              value: dog.registrationNumber ?? 'Não informada',
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Sexo',
              value: dog.sex == 'M' ? 'Macho' : 'Fêmea',
            ),
            EntityIdentityField(
              label: 'Nascimento',
              value: DateFormat('dd/MM/yyyy').format(dog.dateOfBirth),
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Condutor (RA)',
              value: dog.conductorRa != null ? 'RA ${dog.conductorRa}' : 'Não informado',
            ),
            EntityIdentityField(
              label: 'Peso Registrado',
              value: dog.weight != null
                  ? '${dog.weight!.toStringAsFixed(1)} kg'
                  : 'Não informado',
            ),
          ],
        ),
        fonts,
      ),
    );

    // 2. Cards de Métricas / KPI (Total de Doses, Status Geral, Próxima Dose)
    final nextUpcoming = _findNextUpcomingDate(vaccineLogs);
    builder.addWidget(
      pw.Row(
        children: [
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Total de Vacinas',
                value: '${vaccineLogs.length}',
                unit: 'aplicações',
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Status Geral',
                value: overallStatus,
                tone: overallTone,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Próxima Revacinação',
                value: nextUpcoming != null
                    ? DateFormat('dd/MM/yy').format(nextUpcoming)
                    : (vaccineLogs.isNotEmpty ? 'Em dia' : '—'),
                tone: ReportTone.info,
              ),
              fonts,
            ),
          ),
        ],
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 3. Banner de Alertas / Próximas Doses
    builder.addWidget(_buildUpcomingAlertWidget(vaccineLogs, fonts));

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 4. Seção Estilizada: Histórico de Imunizações
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'HISTÓRICO DE VACINAS E IMUNIZAÇÕES',
        fonts,
        iconText: 'VAC',
        subtitle: 'Registro cronológico de vacinas aplicadas e controle de revacinação',
      ),
    );

    // 5. Tabela Rica de Vacinações com zebra e status
    builder.addWidget(_buildImmunizationTable(vaccineLogs, fonts));

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 6. Observações Médicas e Sanitárias (conforme dados factuais da fonte)
    final observations = <String>[];
    if (dog.observacoes != null && dog.observacoes!.trim().isNotEmpty) {
      observations.add(dog.observacoes!.trim());
    }
    for (final l in vaccineLogs) {
      if (l.healthObservations.trim().isNotEmpty) {
        final prefix = l.subtype ?? l.logType;
        observations.add('$prefix: ${l.healthObservations.trim()}');
      }
    }

    if (observations.isNotEmpty) {
      builder.addWidget(
        ReportPrimitives.styledSectionTitle(
          'OBSERVAÇÕES MÉDICAS E SANITÁRIAS',
          fonts,
          iconText: 'OBS',
          subtitle: 'Anotações clínicas e sanitárias registradas pela equipe técnica',
        ),
      );
      builder.addWidget(
        ReportPrimitives.summaryCard(
          SummaryCardData(
            title: 'REGISTROS E OBSERVAÇÕES CLÍNICAS',
            bulletItems: observations,
            tone: ReportTone.neutral,
          ),
          fonts,
        ),
      );
      builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));
    }

    // 7. Bloco Técnico de Emissão e Responsável Veterinário (se identificado na fonte)
    final recentVetLog = vaccineLogs.cast<HealthLogModel?>().firstWhere(
      (l) => l?.vetName != null && l!.vetName!.isNotEmpty,
      orElse: () => null,
    );

    builder.addWidget(
      pw.Container(
        padding: const pw.EdgeInsets.all(ReportSpacing.sm),
        decoration: pw.BoxDecoration(
          color: ReportColors.surfaceSubtle,
          border: pw.Border.all(color: ReportColors.borderSoft, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            if (recentVetLog != null) ...[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RESPONSÁVEL TÉCNICO',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 7,
                      color: ReportColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    recentVetLog.vetName!,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 8.5,
                      color: ReportColors.textPrimary,
                    ),
                  ),
                  if (recentVetLog.professionalCrmv != null &&
                      recentVetLog.professionalCrmv!.isNotEmpty)
                    pw.Text(
                      'CRMV: ${recentVetLog.professionalCrmv!}',
                      style: pw.TextStyle(
                        font: fonts.monoRegular,
                        fontSize: 7.5,
                        color: ReportColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ] else ...[
              pw.Text(
                'HISTÓRICO SANITÁRIO K9',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'DOCUMENTO EMITIDO PELO SISTEMA K9 OPS',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 7,
                    color: ReportColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Emissão: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
                  style: pw.TextStyle(
                    font: fonts.monoRegular,
                    fontSize: 7.5,
                    color: ReportColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return builder.buildPdf(customFonts: fonts);
  }

  /// Determina o status geral com base no histórico factual de vacinas.
  static String _getOverallStatus(List<HealthLogModel> vaccineLogs) {
    if (vaccineLogs.isEmpty) return 'SEM REGISTROS';
    final now = DateTime.now();
    bool hasExpired = false;
    bool hasScheduledDoses = false;
    for (final log in vaccineLogs) {
      if (log.nextDueDate != null) {
        hasScheduledDoses = true;
        if (now.isAfter(log.nextDueDate!)) {
          hasExpired = true;
          break;
        }
      }
    }
    if (hasExpired) return 'VENCIDA';
    if (hasScheduledDoses) return 'EM DIA';
    return 'REGISTRADA';
  }

  /// Localiza a data da próxima dose futura mais próxima conforme a fonte.
  static DateTime? _findNextUpcomingDate(List<HealthLogModel> logs) {
    DateTime? next;
    final now = DateTime.now();
    for (final log in logs) {
      if (log.nextDueDate != null && log.nextDueDate!.isAfter(now)) {
        if (next == null || log.nextDueDate!.isBefore(next)) {
          next = log.nextDueDate;
        }
      }
    }
    return next;
  }

  /// Constrói o widget de resumo e alerta de próximas doses.
  static pw.Widget _buildUpcomingAlertWidget(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    final now = DateTime.now();
    final upcoming = <Map<String, dynamic>>[];

    // Agrupar por tipo de vacina e obter a última data
    final latestByType = <String, HealthLogModel>{};
    for (final log in logs) {
      final name = log.subtype ?? log.logType;
      if (!latestByType.containsKey(name) ||
          log.date.isAfter(latestByType[name]!.date)) {
        latestByType[name] = log;
      }
    }

    bool hasOverdue = false;
    for (final entry in latestByType.entries) {
      final log = entry.value;
      if (log.nextDueDate == null) continue;
      final nextDue = log.nextDueDate!;
      final diffDays = nextDue.difference(now).inDays;

      if (diffDays <= 30) {
        if (diffDays < 0) hasOverdue = true;
        upcoming.add({
          'name': entry.key,
          'dueDate': nextDue,
          'diffDays': diffDays,
        });
      }
    }

    if (upcoming.isEmpty) {
      return ReportPrimitives.summaryCard(
        const SummaryCardData(
          title: 'CONFORMIDADE SANITÁRIA OPERACIONAL',
          description:
              'Todas as vacinações do cão com data prevista cadastrada estão em conformidade.',
          tone: ReportTone.positive,
        ),
        fonts,
      );
    }

    final alertBullets = upcoming.map((alert) {
      final overdue = alert['diffDays'] < 0;
      final days = (alert['diffDays'] as int).abs();
      final dateStr = DateFormat('dd/MM/yyyy').format(alert['dueDate']);
      return overdue
          ? 'Vacina ${alert['name']}: VENCIDA há $days dia(s) (venceu em $dateStr).'
          : 'Vacina ${alert['name']}: Vencerá em $days dia(s) (data limite: $dateStr).';
    }).toList();

    return ReportPrimitives.summaryCard(
      SummaryCardData(
        title: hasOverdue
            ? 'ALERTA SANITÁRIO — DOSES VENCIDAS'
            : 'AVISO PREVENTIVO — REVACINAÇÕES PRÓXIMAS',
        description:
            'Acompanhamento preventivo de imunobiológicos exigidos para atividades do cão:',
        bulletItems: alertBullets,
        tone: hasOverdue ? ReportTone.critical : ReportTone.attention,
      ),
      fonts,
    );
  }

  /// Constrói a tabela rica de histórico de imunizações.
  static pw.Widget _buildImmunizationTable(
    List<HealthLogModel> logs,
    PdfFonts fonts,
  ) {
    if (logs.isEmpty) {
      return ReportPrimitives.observationBlock(
        const ObservationBlockData(
          title: 'Histórico de Vacinação',
          text: 'Nenhuma vacina cadastrada no histórico médico deste cão.',
        ),
        fonts,
      );
    }

    final columns = const [
      DataTableColumn(header: 'Vacina', flex: 2.2),
      DataTableColumn(
        header: 'Aplicação',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.1,
      ),
      DataTableColumn(
        header: 'Próxima Dose',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.3,
      ),
      DataTableColumn(header: 'Veterinário / CRMV', flex: 2.4),
      DataTableColumn(
        header: 'Status',
        alignment: DataTableCellAlignment.center,
        flex: 1.0,
      ),
    ];

    final now = DateTime.now();

    final rows = logs.map((log) {
      final vaccineName = log.subtype ?? log.logType;
      final appDate = DateFormat('dd/MM/yyyy').format(log.date);
      final nextDueDateStr = log.nextDueDate != null
          ? DateFormat('dd/MM/yyyy').format(log.nextDueDate!)
          : '—';

      final isOverdue = log.nextDueDate != null && now.isAfter(log.nextDueDate!);
      final statusStr = log.nextDueDate == null
          ? 'Aplicada'
          : (isOverdue ? 'Vencida' : 'Em dia');
      final statusTone = log.nextDueDate == null
          ? ReportTone.neutral
          : (isOverdue ? ReportTone.critical : ReportTone.positive);

      final vetName = log.vetName ?? 'Veterinário não informado';
      final crmv = log.professionalCrmv != null && log.professionalCrmv!.isNotEmpty
          ? 'CRMV: ${log.professionalCrmv}'
          : (log.professionalClinic != null && log.professionalClinic!.isNotEmpty
              ? 'Clínica: ${log.professionalClinic}'
              : null);

      return RichDataTableRow(
        cells: [
          RichTableCell.text(vaccineName, isBold: true),
          RichTableCell.text(appDate, isMonospace: true),
          RichTableCell.text(nextDueDateStr, isMonospace: true),
          RichTableCell.twoLine(text: vetName, secondaryText: crmv),
          RichTableCell.badge(badgeText: statusStr, badgeTone: statusTone),
        ],
      );
    }).toList();

    return ReportPrimitives.richDataTable(
      RichDataTableData(columns: columns, rows: rows),
      fonts,
    );
  }
}
