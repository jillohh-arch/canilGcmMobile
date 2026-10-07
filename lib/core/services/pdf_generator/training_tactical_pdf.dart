import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/core/services/report_service.dart';
import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/training/domain/training_session_model.dart';
import 'pdf_common_widgets.dart';
import 'template/template.dart';

/// Registro adaptado para exibição tática de treinos.
class TrainingTacticalRecord {
  final DateTime date;
  final String trainingType;
  final String location;
  final String? substanceUsed;
  final int? searchDurationSeconds;
  final String? weather;
  final String observations;
  final String? instructorOrHandler;

  const TrainingTacticalRecord({
    required this.date,
    required this.trainingType,
    required this.location,
    this.substanceUsed,
    this.searchDurationSeconds,
    this.weather,
    required this.observations,
    this.instructorOrHandler,
  });

  factory TrainingTacticalRecord.fromSession(TrainingSessionModel session) {
    return TrainingTacticalRecord(
      date: session.date,
      trainingType: session.trainingType.trim().isNotEmpty
          ? session.trainingType.trim()
          : 'Treino Geral',
      location: session.location.trim().isNotEmpty
          ? session.location.trim()
          : 'Canil GCM',
      substanceUsed: session.substanceUsed?.trim().isNotEmpty == true
          ? session.substanceUsed!.trim()
          : null,
      searchDurationSeconds: session.searchDuration,
      weather: session.weather.trim().isNotEmpty ? session.weather.trim() : null,
      observations: session.handlerNotes.trim().isNotEmpty
          ? session.handlerNotes.trim()
          : 'Sem observações registradas',
      instructorOrHandler: session.handlerId.trim().isNotEmpty
          ? session.handlerId.trim()
          : null,
    );
  }

  factory TrainingTacticalRecord.fromReportEntry(ReportEntry entry) {
    return TrainingTacticalRecord(
      date: entry.date,
      trainingType: entry.type.trim().isNotEmpty ? entry.type.trim() : 'Treino Geral',
      location: entry.location.trim().isNotEmpty ? entry.location.trim() : 'Canil GCM',
      observations: entry.observations.trim().isNotEmpty
          ? entry.observations.trim()
          : 'Sem observações registradas',
    );
  }
}

/// Gerador do Relatório Tático de Treinos K9 (MOB-DOC-05)
/// baseado no K9 Ops Report Design System V1 (F70).
class TrainingTacticalPdf {
  TrainingTacticalPdf._();

  /// Gera os bytes do PDF do relatório tático de treinos.
  ///
  /// Preserva integralmente a semântica de F50 (capacitação/treinamento).
  /// Suporta sessões ricas ([sessions]), entradas de relatório legadas ([entries])
  /// ou registros táticos diretos ([records]).
  static Future<Uint8List> generate({
    required Dog dog,
    List<TrainingSessionModel>? sessions,
    List<ReportEntry>? entries,
    List<TrainingTacticalRecord>? records,
    String? conductorCallsign,
    String? period,
    DateTime? startDate,
    DateTime? endDate,
    Uint8List? dogPhotoBytes,
    Uint8List? k9LogoBytes,
  }) async {
    final fonts = await PdfFonts.load();
    final logoBytes = k9LogoBytes ?? await ReportBrandingAssets.loadOfficialLogo();

    // 1. Resolução e unificação dos registros
    final List<TrainingTacticalRecord> allRecords;
    if (records != null) {
      allRecords = records;
    } else if (sessions != null) {
      allRecords = sessions.map(TrainingTacticalRecord.fromSession).toList();
    } else if (entries != null) {
      allRecords = entries.map(TrainingTacticalRecord.fromReportEntry).toList();
    } else {
      allRecords = [];
    }

    // Ordenação cronológica decrescente (mais recentes primeiro)
    final sortedRecords = [...allRecords]
      ..sort((a, b) => b.date.compareTo(a.date));

    // 2. Resolução do período
    final String resolvedPeriod;
    if (period != null && period.isNotEmpty) {
      resolvedPeriod = period;
    } else if (startDate != null && endDate != null) {
      resolvedPeriod =
          '${DateFormat('dd/MM/yyyy').format(startDate)} a ${DateFormat('dd/MM/yyyy').format(endDate)}';
    } else if (sortedRecords.isNotEmpty) {
      final sortedAsc = [...sortedRecords]..sort((a, b) => a.date.compareTo(b.date));
      resolvedPeriod =
          '${DateFormat('dd/MM/yyyy').format(sortedAsc.first.date)} a ${DateFormat('dd/MM/yyyy').format(sortedAsc.last.date)}';
    } else {
      resolvedPeriod = 'Período não especificado';
    }

    // 3. Métricas factuais derivadas da contagem real
    final totalCount = sortedRecords.length;
    final distinctModalities = sortedRecords.map((r) => r.trainingType).toSet();
    final distinctLocations = sortedRecords.map((r) => r.location).toSet();

    final durationsRecorded = sortedRecords
        .where((r) => r.searchDurationSeconds != null && r.searchDurationSeconds! > 0)
        .toList();
    final totalDurationSeconds = durationsRecorded.fold<int>(
      0,
      (acc, r) => acc + r.searchDurationSeconds!,
    );
    final hasDuration = durationsRecorded.isNotEmpty;
    final mostRecentDate = sortedRecords.isNotEmpty ? sortedRecords.first.date : null;

    final now = DateTime.now();

    final metadata = ReportMetadata(
      generatedAt: now,
      period: resolvedPeriod,
      dogIdentity: '${dog.name} (${dog.breed})',
      operatorName: conductorCallsign?.isNotEmpty == true
          ? conductorCallsign
          : (dog.conductorRa != null ? 'Condutor RA: ${dog.conductorRa}' : null),
    );

    final builder = ReportTemplateBuilder(
      title: 'RELATÓRIO TÁTICO DE TREINOS',
      subtitle: 'REGISTRO DE CAPACITAÇÃO E CONDICIONAMENTO OPERACIONAL K9',
      category: 'TREINAMENTO TÁTICO K9',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      branding: ReportBranding(
        productMarkImage:
            logoBytes != null ? ReportImageSlot(bytes: logoBytes) : null,
      ),
      statusLabel: totalCount > 0 ? '$totalCount SESSÕES' : 'SEM REGISTROS',
      statusTone: totalCount > 0 ? ReportTone.info : ReportTone.neutral,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig(
        archetype: ReportArchetype.operational,
        name: 'Relatório Tático de Treinos',
        headerVariant: HeaderVariant.darkTactical,
        orientation: PageOrientation.portrait,
      ),
    );

    // 4. Hero Section / Identidade do Cão
    builder.addWidget(
      ReportPrimitives.entityIdentityBlock(
        EntityIdentityData(
          title: dog.name.toUpperCase(),
          subtitle: null,
          registrationBadge: dog.registrationNumber,
          tags: [
            'CÃO DE TRABALHO',
            if (dog.specialties != null) ...dog.specialties!,
          ],
          statusLabel: dog.status.toUpperCase(),
          statusTone: dog.status.toLowerCase() == 'ativo'
              ? ReportTone.positive
              : ReportTone.neutral,
          avatar: dogPhotoBytes != null
              ? ReportImageSlot(bytes: dogPhotoBytes)
              : null,
          avatarPlaceholder: dog.name.isNotEmpty
              ? dog.name.substring(0, dog.name.length >= 2 ? 2 : 1).toUpperCase()
              : 'K9',
          fields: [
            EntityIdentityField(label: 'Raça', value: dog.breed),
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
              label: 'Microchip',
              value: dog.microchip ?? 'Não informado',
              isMonospace: true,
            ),
            EntityIdentityField(
              label: 'Condutor',
              value: conductorCallsign?.isNotEmpty == true
                  ? conductorCallsign!
                  : (dog.conductorRa != null
                      ? 'GCM RA ${dog.conductorRa}'
                      : 'Não informado'),
            ),
            if (dog.cor != null && dog.cor!.isNotEmpty)
              EntityIdentityField(label: 'Pelagem', value: dog.cor!),
            EntityIdentityField(
              label: 'Situação',
              value: dog.status.toUpperCase(),
            ),
            EntityIdentityField(
              label: 'Total no Período',
              value: '$totalCount sessões',
            ),
          ],
        ),
        fonts,
      ),
    );

    // 5. Cards de Métricas Fatuais
    builder.addWidget(
      pw.Row(
        children: [
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Total de Sessões',
                value: '$totalCount',
                unit: 'treinos',
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Modalidades',
                value: '${distinctModalities.length}',
                unit: 'distintas',
                tone: distinctModalities.isNotEmpty
                    ? ReportTone.info
                    : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              hasDuration
                  ? MetricCardData(
                      label: 'Tempo em Treino',
                      value: totalDurationSeconds >= 3600
                          ? '${(totalDurationSeconds / 3600).toStringAsFixed(1)} h'
                          : '${(totalDurationSeconds ~/ 60)} min',
                      unit: 'acumulado',
                      tone: ReportTone.positive,
                    )
                  : MetricCardData(
                      label: 'Locais de Treino',
                      value: '${distinctLocations.length}',
                      unit: 'ambientes',
                      tone: ReportTone.neutral,
                    ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Sessão Mais Recente',
                value: mostRecentDate != null
                    ? DateFormat('dd/MM/yy').format(mostRecentDate)
                    : '—',
                unit: mostRecentDate != null ? 'última data' : '',
                tone: mostRecentDate != null
                    ? ReportTone.info
                    : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
        ],
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 6. Título de Seção Estilizado
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'REGISTRO TÁTICO DE TREINAMENTOS',
        fonts,
        iconText: 'TRN',
        subtitle:
            'Detalhamento cronológico de sessões, técnicas e observações operacionais',
      ),
    );

    // 7. Tabela Rica de Sessões ou Estado Vazio
    if (sortedRecords.isEmpty) {
      builder.addWidget(
        ReportPrimitives.observationBlock(
          const ObservationBlockData(
            title: 'Histórico de Treinamentos',
            text:
                'Nenhuma sessão de treinamento cadastrada para os filtros e período selecionados.',
          ),
          fonts,
        ),
      );
    } else {
      builder.addWidget(_buildTrainingTable(sortedRecords, fonts));
    }

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 8. Bloco Técnico de Emissão Factual
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
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'RELATÓRIO DE TREINAMENTO K9 · SISTEMA K9 OPS',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 7,
                color: ReportColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
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
      ),
    );

    return builder.buildPdf(customFonts: fonts);
  }

  /// Constrói a tabela rica com repetição de cabeçalho multipágina.
  static pw.Widget _buildTrainingTable(
    List<TrainingTacticalRecord> records,
    PdfFonts fonts,
  ) {
    final columns = const [
      DataTableColumn(
        header: 'Data / Hora',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.10,
      ),
      DataTableColumn(
        header: 'Modalidade',
        alignment: DataTableCellAlignment.left,
        flex: 1.85,
      ),
      DataTableColumn(
        header: 'Local / Ambiente',
        flex: 1.35,
      ),
      DataTableColumn(
        header: 'Especificação Técnica',
        flex: 1.50,
      ),
      DataTableColumn(
        header: 'Observações do Condutor',
        flex: 2.20,
      ),
    ];

    final rows = records.map((record) {
      final dateFormatted = DateFormat('dd/MM/yyyy').format(record.date);
      final timeFormatted = DateFormat('HH:mm').format(record.date);
      final modalityTone = _resolveModalityTone(record.trainingType);

      final weatherStr = record.weather != null && record.weather!.isNotEmpty
          ? 'Clima: ${record.weather}'
          : null;

      final durationText = _formatDuration(record.searchDurationSeconds);
      final String techPrimary;
      final String? techSecondary;

      if (record.substanceUsed != null && record.substanceUsed!.isNotEmpty) {
        techPrimary = 'Odor: ${record.substanceUsed}';
        techSecondary = durationText != null ? 'Duração: $durationText' : null;
      } else if (durationText != null) {
        techPrimary = 'Duração: $durationText';
        techSecondary = null;
      } else {
        techPrimary = '—';
        techSecondary = null;
      }

      return RichDataTableRow(
        cells: [
          RichTableCell.twoLine(
            text: dateFormatted,
            secondaryText: timeFormatted,
            isMonospace: true,
            alignment: DataTableCellAlignment.center,
          ),
          RichTableCell.semanticDot(
            text: record.trainingType,
            tone: modalityTone,
          ),
          RichTableCell.twoLine(
            text: record.location,
            secondaryText: weatherStr,
          ),
          techSecondary != null
              ? RichTableCell.twoLine(
                  text: techPrimary,
                  secondaryText: techSecondary,
                )
              : RichTableCell.text(techPrimary),
          RichTableCell.text(record.observations),
        ],
      );
    }).toList();

    return ReportPrimitives.richDataTable(
      RichDataTableData(columns: columns, rows: rows),
      fonts,
    );
  }

  static String? _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final remSecs = seconds % 60;
    if (remSecs == 0) return '$mins min';
    return '${mins}m ${remSecs}s';
  }

  static ReportTone _resolveModalityTone(String modality) {
    final lower = modality.toLowerCase();
    if (lower.contains('faro') ||
        lower.contains('detec') ||
        lower.contains('busca') ||
        lower.contains('captura')) {
      return ReportTone.critical;
    }
    if (lower.contains('prote') ||
        lower.contains('guarda') ||
        lower.contains('interven') ||
        lower.contains('mordida')) {
      return ReportTone.attention;
    }
    if (lower.contains('obedi') ||
        lower.contains('agility') ||
        lower.contains('condicion')) {
      return ReportTone.positive;
    }
    return ReportTone.info;
  }
}
