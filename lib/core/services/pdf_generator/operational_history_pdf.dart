import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/history/presentation/screens/history_screen.dart';
import 'pdf_common_widgets.dart';
import 'template/template.dart';

/// Gerador do PDF do Histórico Operacional do Cão (MOB-DOC-06)
/// baseado no K9 Ops Report Design System V1 (F70).
class OperationalHistoryPdf {
  OperationalHistoryPdf._();

  /// Gera os bytes do PDF do histórico operacional.
  ///
  /// Preserva 100% da semântica factual das entradas da trilha operacional ([entries]),
  /// atribuindo as categorias e dados de autoria originais sem sintetizar scores,
  /// rankings ou conclusões clínicas inexistentes na fonte.
  static Future<Uint8List> generate({
    required List<HistoryEntry> entries,
    Dog? dog,
    String? handlerName,
    String? periodLabel,
    DateTime? startDate,
    DateTime? endDate,
    Uint8List? dogPhotoBytes,
    Uint8List? k9LogoBytes,
  }) async {
    final fonts = await PdfFonts.load();
    final logoBytes = k9LogoBytes ?? await ReportBrandingAssets.loadOfficialLogo();

    // Ordenação estritamente cronológica decrescente (mais recentes primeiro)
    final sortedEntries = [...entries]..sort((a, b) => b.time.compareTo(a.time));

    final String resolvedPeriod;
    if (periodLabel != null && periodLabel.isNotEmpty) {
      resolvedPeriod = periodLabel;
    } else if (startDate != null && endDate != null) {
      resolvedPeriod =
          '${DateFormat('dd/MM/yyyy').format(startDate)} a ${DateFormat('dd/MM/yyyy').format(endDate)}';
    } else if (sortedEntries.isNotEmpty) {
      final sortedAsc = [...sortedEntries]..sort((a, b) => a.time.compareTo(b.time));
      resolvedPeriod =
          '${DateFormat('dd/MM/yyyy').format(sortedAsc.first.time)} a ${DateFormat('dd/MM/yyyy').format(sortedAsc.last.time)}';
    } else {
      resolvedPeriod = 'Período não especificado';
    }

    final totalCount = sortedEntries.length;
    final occurrencesCount =
        sortedEntries.where((e) => e.type == HistoryEntryType.occurrence).length;
    final trainingsCount =
        sortedEntries.where((e) => e.type == HistoryEntryType.training).length;
    final healthAndNutritionCount = sortedEntries
        .where(
          (e) =>
              e.type == HistoryEntryType.health ||
              e.type == HistoryEntryType.nutrition,
        )
        .length;

    final now = DateTime.now();

    final metadata = ReportMetadata(
      generatedAt: now,
      period: resolvedPeriod,
      dogIdentity: dog != null ? '${dog.name} (${dog.breed})' : null,
      operatorName: handlerName?.isNotEmpty == true
          ? handlerName
          : (dog?.conductorRa != null ? 'Condutor RA: ${dog!.conductorRa}' : null),
    );

    final builder = ReportTemplateBuilder(
      title: 'HISTÓRICO OPERACIONAL K9',
      subtitle: 'REGISTRO CRONOLÓGICO DE ATIVIDADES E EMPREGO OPERACIONAL',
      category: 'HISTÓRICO OPERACIONAL',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      branding: ReportBranding(
        productMarkImage:
            logoBytes != null ? ReportImageSlot(bytes: logoBytes) : null,
      ),
      statusLabel: totalCount > 0 ? '$totalCount REGISTROS' : 'SEM REGISTROS',
      statusTone: totalCount > 0 ? ReportTone.info : ReportTone.neutral,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig(
        archetype: ReportArchetype.operational,
        name: 'Histórico Operacional',
        headerVariant: HeaderVariant.darkTactical,
        orientation: PageOrientation.portrait,
      ),
    );

    // 1. Hero Section / Identidade do Cão ou da Guarnição
    if (dog != null) {
      builder.addWidget(
        ReportPrimitives.entityIdentityBlock(
          EntityIdentityData(
            title: dog.name.toUpperCase(),
            subtitle: 'Raça: ${dog.breed}',
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
                value: handlerName?.isNotEmpty == true
                    ? handlerName!
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
                value: '$totalCount registros',
              ),
            ],
          ),
          fonts,
        ),
      );
    } else {
      builder.addWidget(
        ReportPrimitives.entityIdentityBlock(
          EntityIdentityData(
            title: 'REGISTRO OPERACIONAL DE ATIVIDADES',
            subtitle: 'Relatório consolidado de emprego e movimentação',
            tags: const ['OPERAÇÕES K9'],
            statusLabel: totalCount > 0 ? '$totalCount ATIVIDADES' : 'SEM REGISTROS',
            statusTone: totalCount > 0 ? ReportTone.info : ReportTone.neutral,
            avatarPlaceholder: 'K9',
            fields: [
              EntityIdentityField(
                label: 'Responsável / Condutor',
                value: handlerName?.isNotEmpty == true
                    ? handlerName!
                    : 'Não informado',
              ),
              EntityIdentityField(
                label: 'Período',
                value: resolvedPeriod,
              ),
              EntityIdentityField(
                label: 'Total de Registros',
                value: '$totalCount registros no período',
              ),
            ],
          ),
          fonts,
        ),
      );
    }

    // 2. Cards de Métricas Fatuais (Sem scores inventados)
    builder.addWidget(
      pw.Row(
        children: [
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Total de Registros',
                value: '$totalCount',
                unit: 'atividades',
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Ocorrências',
                value: '$occurrencesCount',
                unit: 'empenhos',
                tone: occurrencesCount > 0
                    ? ReportTone.critical
                    : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Treinamentos',
                value: '$trainingsCount',
                unit: 'sessões',
                tone: trainingsCount > 0 ? ReportTone.info : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Saúde & Manejo',
                value: '$healthAndNutritionCount',
                unit: 'registros',
                tone: healthAndNutritionCount > 0
                    ? ReportTone.attention
                    : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
        ],
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 3. Título de Seção Estilizado
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'REGISTRO CRONOLÓGICO DE ATIVIDADES',
        fonts,
        iconText: 'OPS',
        subtitle:
            'Detalhamento temporal de ocorrências, treinos, saúde e manejo',
      ),
    );

    // 4. Tabela de Cronologia ou Estado Vazio
    if (sortedEntries.isEmpty) {
      builder.addWidget(
        ReportPrimitives.observationBlock(
          const ObservationBlockData(
            title: 'Histórico Operacional',
            text:
                'Nenhum registro operacional cadastrado para os filtros e período selecionados.',
          ),
          fonts,
        ),
      );
    } else {
      builder.addWidget(_buildChronologyTable(sortedEntries, fonts));
    }

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 5. Bloco Técnico de Emissão Factual
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
              'HISTÓRICO OPERACIONAL K9 · SISTEMA K9 OPS',
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

  /// Constrói a tabela rica e multipágina de registros cronológicos.
  static pw.Widget _buildChronologyTable(
    List<HistoryEntry> entries,
    PdfFonts fonts,
  ) {
    final columns = const [
      DataTableColumn(
        header: 'Data / Hora',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.2,
      ),
      DataTableColumn(
        header: 'Categoria',
        alignment: DataTableCellAlignment.center,
        flex: 1.0,
      ),
      DataTableColumn(
        header: 'Registro / Atividade',
        flex: 2.8,
      ),
      DataTableColumn(
        header: 'Responsável',
        flex: 1.4,
      ),
    ];

    final rows = entries.map((entry) {
      final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(entry.time);
      final categoryTone = switch (entry.type) {
        HistoryEntryType.occurrence => ReportTone.critical,
        HistoryEntryType.training => ReportTone.info,
        HistoryEntryType.health => ReportTone.attention,
        HistoryEntryType.nutrition => ReportTone.positive,
      };

      final secondaryParts = [
        if (entry.subtitle.trim().isNotEmpty) entry.subtitle.trim(),
        if (entry.location.trim().isNotEmpty) entry.location.trim(),
      ];
      final secondaryText =
          secondaryParts.isNotEmpty ? secondaryParts.join(' · ') : null;

      final authorText = entry.author.trim().isNotEmpty
          ? entry.author.trim()
          : (entry.authorId.trim().isNotEmpty
              ? entry.authorId.trim()
              : 'Não informado');

      return RichDataTableRow(
        cells: [
          RichTableCell.text(dateStr, isMonospace: true),
          RichTableCell.badge(
            badgeText: entry.category,
            badgeTone: categoryTone,
          ),
          RichTableCell.twoLine(
            text: entry.title.trim().isNotEmpty
                ? entry.title.trim()
                : 'Sem título',
            secondaryText: secondaryText,
          ),
          RichTableCell.text(authorText),
        ],
      );
    }).toList();

    return ReportPrimitives.richDataTable(
      RichDataTableData(columns: columns, rows: rows),
      fonts,
    );
  }
}
