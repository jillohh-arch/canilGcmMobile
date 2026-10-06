import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:canil_gcm/features/dogs/domain/dog.dart';
import 'package:canil_gcm/features/nutrition/domain/feeding.dart';
import 'package:canil_gcm/features/nutrition/domain/nutrition_prescription.dart';
import 'pdf_common_widgets.dart';
import 'template/template.dart';

/// Gerador do PDF do Relatório Nutricional do Cão baseado na Foundation F70 Oficial.
class NutritionPdf {
  /// Gera os bytes do PDF de histórico nutricional.
  static Future<Uint8List> generate({
    required Dog dog,
    required List<Feeding> feedings,
    required NutritionPrescription? prescription,
    required double conformityPercent,
    required int conformCount,
    required int divergentCount,
    Uint8List? dogPhotoBytes,
  }) async {
    final fonts = await PdfFonts.load();

    final conformityTone = conformityPercent >= 85
        ? ReportTone.positive
        : (conformityPercent >= 70 ? ReportTone.attention : ReportTone.critical);

    final now = DateTime.now();

    final metadata = ReportMetadata(
      generatedAt: now,
      dogIdentity: '${dog.name} (${dog.breed})',
      operatorName: dog.conductorRa != null ? 'Condutor RA: ${dog.conductorRa}' : null,
    );

    final builder = ReportTemplateBuilder(
      title: 'RELATÓRIO NUTRICIONAL K9',
      subtitle: 'PRESCRIÇÃO DIETÉTICA E CONTROLE DE CONFORMIDADE',
      category: 'MANEJO NUTRICIONAL K9',
      motto: 'DISCIPLINA · PROTEÇÃO · RESULTADO',
      metadata: metadata,
      statusLabel: 'CONFORMIDADE: ${conformityPercent.toStringAsFixed(0)}%',
      statusTone: conformityTone,
      useDarkFooter: true,
      archetypeConfig: ReportArchetypeConfig.clinicalTactical(),
    );

    // 1. Hero Section / Identidade do Cão (Foto Ampliada + Ficha em 2 Colunas)
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
          avatar: dogPhotoBytes != null ? ReportImageSlot(bytes: dogPhotoBytes) : null,
          avatarPlaceholder: dog.name.isNotEmpty
              ? dog.name.substring(0, dog.name.length >= 2 ? 2 : 1).toUpperCase()
              : 'K9',
          fields: [
            EntityIdentityField(label: 'Raça', value: dog.breed),
            EntityIdentityField(label: 'Sexo', value: dog.sex == 'M' ? 'Macho' : 'Fêmea'),
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
              label: 'Peso Atual',
              value: dog.weight != null
                  ? '${dog.weight!.toStringAsFixed(1)} kg'
                  : 'Não informado',
            ),
            EntityIdentityField(
              label: 'Condutor',
              value: dog.conductorRa != null ? 'GCM RA ${dog.conductorRa}' : 'Não informado',
            ),
            EntityIdentityField(
              label: 'Alimento Prescrito',
              value: prescription?.foodType ?? 'Sem prescrição',
            ),
          ],
        ),
        fonts,
      ),
    );

    // 2. Cards de Métricas / KPI (Conformidade, Total, Conformes, Divergentes)
    builder.addWidget(
      pw.Row(
        children: [
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Conformidade',
                value: '${conformityPercent.toStringAsFixed(0)}%',
                tone: conformityTone,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Total Refeições',
                value: '${feedings.length}',
                unit: 'registradas',
                tone: ReportTone.neutral,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Conformes',
                value: '$conformCount',
                tone: ReportTone.positive,
              ),
              fonts,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: ReportPrimitives.metricCard(
              MetricCardData(
                label: 'Divergentes',
                value: '$divergentCount',
                tone: divergentCount > 0 ? ReportTone.attention : ReportTone.neutral,
              ),
              fonts,
            ),
          ),
        ],
      ),
    );

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 3. Seção: Prescrição Nutricional Vigente
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'PRESCRIÇÃO NUTRICIONAL VIGENTE',
        fonts,
        iconText: 'RX',
        subtitle: 'Parâmetros dietéticos prescritos pelo médico veterinário responsável',
      ),
    );

    if (prescription == null) {
      builder.addWidget(
        ReportPrimitives.summaryCard(
          const SummaryCardData(
            title: 'SEM PRESCRIÇÃO VIGENTE',
            description:
                'Nenhum laudo nutricional ou prescrição dietética cadastrada para este cão. Recomenda-se avaliação médica veterinária para estipulação de metas calóricas.',
            tone: ReportTone.attention,
          ),
          fonts,
        ),
      );
    } else {
      builder.addWidget(
        ReportPrimitives.summaryCard(
          SummaryCardData(
            title: 'Prescrição Dietética: ${prescription.foodType.toUpperCase()}',
            description:
                'Dose diária recomendada de ${prescription.amountGramsPerDay}g dividida em ${prescription.mealsPerDay} refeições (${prescription.amountPerMeal}g por porção).',
            bulletItems: [
              'Alimento: ${prescription.foodType}',
              'Veterinário Prescritor: Dr(a). ${prescription.vetName ?? "Não informado"}${prescription.vetCrmv != null ? " (CRMV: ${prescription.vetCrmv})" : ""}',
              'Vigência: Desde ${DateFormat('dd/MM/yyyy').format(prescription.vigentFrom)}${prescription.vigentUntil != null ? " até ${DateFormat('dd/MM/yyyy').format(prescription.vigentUntil!)}" : ""}',
              if (prescription.hydrationNotes != null && prescription.hydrationNotes!.isNotEmpty)
                'Hidratação / Manejo: ${prescription.hydrationNotes!}',
              if (prescription.notes != null && prescription.notes!.isNotEmpty)
                'Orientações: ${prescription.notes!}',
            ],
            tone: ReportTone.positive,
          ),
          fonts,
        ),
      );
    }

    builder.addWidget(pw.SizedBox(height: ReportSpacing.sm));

    // 4. Seção: Histórico Recente de Refeições
    builder.addWidget(
      ReportPrimitives.styledSectionTitle(
        'HISTÓRICO RECENTE DE ALIMENTAÇÃO',
        fonts,
        iconText: 'REF',
        subtitle: 'Registro das refeições servidas com auditoria de porção e divergência',
      ),
    );

    builder.addWidget(_buildFeedingsTable(feedings, fonts));

    builder.addWidget(pw.SizedBox(height: ReportSpacing.md));

    // 5. Bloco de Emissão
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
              'MANEJO NUTRICIONAL K9 · SISTEMA K9 OPS',
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

  /// Constrói a tabela rica de histórico de alimentação.
  static pw.Widget _buildFeedingsTable(
    List<Feeding> rawFeedings,
    PdfFonts fonts,
  ) {
    if (rawFeedings.isEmpty) {
      return ReportPrimitives.observationBlock(
        const ObservationBlockData(
          title: 'Histórico de Refeições',
          text: 'Nenhuma refeição registrada no período consultado.',
        ),
        fonts,
      );
    }

    final sortedFeedings = [...rawFeedings]
      ..sort((a, b) => b.fedAt.compareTo(a.fedAt));

    final columns = const [
      DataTableColumn(
        header: 'Data / Hora',
        alignment: DataTableCellAlignment.center,
        isMonospace: true,
        flex: 1.4,
      ),
      DataTableColumn(header: 'Período', flex: 1.0),
      DataTableColumn(
        header: 'Servido',
        alignment: DataTableCellAlignment.right,
        isMonospace: true,
        flex: 1.0,
      ),
      DataTableColumn(
        header: 'Prescrito',
        alignment: DataTableCellAlignment.right,
        isMonospace: true,
        flex: 1.1,
      ),
      DataTableColumn(
        header: 'Divergência',
        alignment: DataTableCellAlignment.right,
        isMonospace: true,
        flex: 1.2,
      ),
      DataTableColumn(
        header: 'Status',
        alignment: DataTableCellAlignment.center,
        flex: 1.1,
      ),
    ];

    final rows = sortedFeedings.map((f) {
      final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(f.fedAt);
      final periodStr = f.period == 'manha'
          ? 'Manhã'
          : (f.period == 'almoco' ? 'Almoço' : 'Noite');
      final amountStr = '${f.amountGrams}g';
      final prescribedStr = f.prescriptionAtTime > 0 ? '${f.prescriptionAtTime}g' : '—';

      // Autoridade de domínio F20: Feeding.isConform (divergencePercent.abs() <= 10.0)
      final isConform = f.isConform;
      final isDivergent = !isConform;
      final diffPrefix = f.divergencePercent > 0 ? '+' : '';
      final diffStr = '$diffPrefix${f.divergencePercent.toStringAsFixed(0)}%';

      final statusStr = isConform ? 'Conforme' : 'Divergente';
      final statusTone = isConform ? ReportTone.positive : ReportTone.attention;

      return RichDataTableRow(
        cells: [
          RichTableCell.text(dateStr, isMonospace: true),
          RichTableCell.text(periodStr),
          RichTableCell.text(amountStr, isBold: true, isMonospace: true),
          RichTableCell.text(prescribedStr, isMonospace: true),
          RichTableCell.text(
            diffStr,
            isBold: true,
            isMonospace: true,
            textColor: isDivergent ? PdfColor.fromHex('B88A0C') : PdfColor.fromHex('166534'),
          ),
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
