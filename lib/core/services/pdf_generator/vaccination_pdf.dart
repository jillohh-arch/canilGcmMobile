import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
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

    final docId = _buildDocId(dog);
    final overallStatus = _getOverallStatus(vaccineLogs);
    final overallTone = switch (overallStatus) {
      'EM DIA' => ReportTone.positive,
      'VENCIDA' => ReportTone.critical,
      _ => ReportTone.neutral,
    };

    final auditRef = _buildAuditReference(dog);
    final now = DateTime.now();
    final docHash = sha256
        .convert(utf8.encode('$docId|${dog.id}|${dog.name}|${now.toIso8601String()}'))
        .toString();

    final metadata = ReportMetadata(
      generatedAt: now,
      documentId: docId,
      dogIdentity: '${dog.name} (${dog.breed})',
      operatorName: dog.conductorRa != null ? 'Condutor RA: ${dog.conductorRa}' : null,
      callsign: 'K9-CANIL',
    );

    final builder = ReportTemplateBuilder(
      title: 'CARTEIRA DE VACINAÇÃO K9',
      subtitle: 'REGISTRO SANITÁRIO E CONTROLE DE IMUNOBIOLÓGICOS',
      category: 'PRONTUÁRIO MÉDICO VETERINÁRIO',
      organization: 'CANIL DA GUARDA CIVIL MUNICIPAL DE LIMEIRA',
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
              label: 'Condutor / Unidade',
              value: dog.conductorRa != null ? 'RA ${dog.conductorRa}' : 'GCM Limeira',
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
        subtitle: 'Registro cronológico de vacinas aplicadas com rastreabilidade de lote e CRMV',
      ),
    );

    // 5. Tabela Rica de Vacinações com zebra e status
    builder.addWidget(_buildImmunizationTable(vaccineLogs, fonts));

    builder.addWidget(pw.SizedBox(height: ReportSpacing.md));

    // 6. Bloco de Auditoria e Verificação Técnica
    builder.addWidget(
      ReportPrimitives.auditBlock(
        AuditData(
          verificationUrl: 'https://k9ops.com/v/$docId',
          hash: docHash,
          algorithm: 'SHA-256',
          documentId: docId,
          trackingCode: auditRef,
          description:
              'Este documento reflete em tempo real o prontuário de saúde do cão ${dog.name}, registrado e mantido pela equipe de condutores e veterinários do Canil K9 da GCM de Limeira. Todas as modificações no prontuário geram trilhas de auditoria imutáveis.',
        ),
        fonts,
      ),
    );

    return builder.buildPdf(customFonts: fonts);
  }

  /// Gera um ID de documento estruturado único.
  static String _buildDocId(Dog dog) {
    final year = DateTime.now().year;
    final month = DateTime.now().month.toString().padLeft(2, '0');
    final seq = dog.id.length >= 4
        ? dog.id.substring(0, 4).toUpperCase()
        : dog.id.toUpperCase().padRight(4, '0');
    return 'VAC: $year/$month/$seq-K9';
  }

  /// Gera uma referência de rastreamento de auditoria baseada no ID do cão.
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

  /// Localiza a data da próxima dose futura mais próxima.
  static DateTime? _findNextUpcomingDate(List<HealthLogModel> logs) {
    DateTime? next;
    final now = DateTime.now();
    for (final log in logs) {
      final due = log.nextDueDate ?? log.date.add(const Duration(days: 365));
      if (due.isAfter(now)) {
        if (next == null || due.isBefore(next)) {
          next = due;
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
      final name = log.subtype ?? 'Geral';
      if (!latestByType.containsKey(name) ||
          log.date.isAfter(latestByType[name]!.date)) {
        latestByType[name] = log;
      }
    }

    bool hasOverdue = false;
    for (final entry in latestByType.entries) {
      final log = entry.value;
      final nextDue =
          log.nextDueDate ?? log.date.add(const Duration(days: 365));
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
              'Todas as vacinações do cão estão em dia e com conformidade operacional.',
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
      DataTableColumn(header: 'Vacina', flex: 2.0),
      DataTableColumn(header: 'Lote / Fabricante', flex: 1.6),
      DataTableColumn(
        header: 'Aplicação',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.1,
      ),
      DataTableColumn(
        header: 'Validade / Próx. Dose',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.3,
      ),
      DataTableColumn(header: 'Veterinário / CRMV', flex: 2.2),
      DataTableColumn(
        header: 'Status',
        alignment: DataTableCellAlignment.center,
        flex: 1.0,
      ),
    ];

    final now = DateTime.now();

    final rows = logs.map((log) {
      final vaccineName = log.subtype ?? 'Vacina Geral';
      final appDate = DateFormat('dd/MM/yyyy').format(log.date);
      final nextDue =
          log.nextDueDate ?? log.date.add(const Duration(days: 365));
      final nextDueDateStr = DateFormat('dd/MM/yyyy').format(nextDue);

      final isOverdue = now.isAfter(nextDue);
      final statusStr = isOverdue ? 'Vencido' : 'OK';
      final statusTone = isOverdue ? ReportTone.critical : ReportTone.positive;

      final vetName = log.vetName ?? 'Não Informado';
      final crmv = log.professionalCrmv != null && log.professionalCrmv!.isNotEmpty
          ? 'CRMV: ${log.professionalCrmv}'
          : (log.professionalClinic ?? 'GCM Limeira');

      final loteStr = log.healthObservations.trim().isNotEmpty
          ? log.healthObservations.trim()
          : (log.professionalClinic ?? 'Conforme protocolo');

      return RichDataTableRow(
        cells: [
          RichTableCell.text(vaccineName, isBold: true),
          RichTableCell.text(loteStr),
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
