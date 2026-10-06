import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_common_widgets.dart';
import 'report_tokens.dart';
import 'report_types.dart';

/// Primitivas visuais canônicas do K9 Ops Report Design System V1.
///
/// Todas as primitivas são puras, sem conhecimento de regras de negócio ou enums
/// de domínio. Elas operam exclusivamente com tokens e modelos genéricos.
class ReportPrimitives {
  ReportPrimitives._();

  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

  // =========================================================================
  // 1. BRANDING SLOTS
  // =========================================================================

  /// Slot da Marca do Produto (K9 Ops).
  ///
  /// Dimensões: máx 28x12mm, fit contain, área de segurança 2mm.
  /// Fallback textual: "K9 Ops" tipográfico limpo.
  /// REGRA ESTRITA: NUNCA crie logotipo sintético (sem círculo ciano, sem glifo inventado).
  static pw.Widget productMark(ReportBranding branding, PdfFonts fonts) {
    final maxWidthPt = ReportPageMetrics.productMarkMaxWidthMm * PdfPageFormat.mm;
    final maxHeightPt = ReportPageMetrics.productMarkMaxHeightMm * PdfPageFormat.mm;
    final paddingPt = ReportPageMetrics.productMarkSafeAreaMm * PdfPageFormat.mm;

    if (branding.productMarkImage != null) {
      return pw.Padding(
        padding: pw.EdgeInsets.all(paddingPt),
        child: pw.ConstrainedBox(
          constraints: pw.BoxConstraints(maxWidth: maxWidthPt, maxHeight: maxHeightPt),
          child: pw.Image(
            pw.MemoryImage(branding.productMarkImage!.bytes),
            fit: pw.BoxFit.contain,
          ),
        ),
      );
    }

    // Fallback textual oficial limpo
    return pw.Padding(
      padding: pw.EdgeInsets.all(paddingPt),
      child: pw.Text(
        branding.textualFallback,
        style: pw.TextStyle(
          font: fonts.bold,
          fontSize: 11,
          color: ReportColors.accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Slot da Marca do Emissor Institucional.
  ///
  /// Dimensões: máx 18x18mm, fit contain, área de segurança 2mm.
  /// Fornecido pela fonte de dados; F70 não define qual brasão é obrigatório.
  static pw.Widget institutionalIssuerMark(ReportBranding branding) {
    if (branding.institutionalIssuerMarkImage == null) {
      return pw.SizedBox.shrink();
    }

    final maxWidthPt = ReportPageMetrics.issuerMarkMaxWidthMm * PdfPageFormat.mm;
    final maxHeightPt = ReportPageMetrics.issuerMarkMaxHeightMm * PdfPageFormat.mm;
    final paddingPt = ReportPageMetrics.issuerMarkSafeAreaMm * PdfPageFormat.mm;

    return pw.Padding(
      padding: pw.EdgeInsets.all(paddingPt),
      child: pw.ConstrainedBox(
        constraints: pw.BoxConstraints(maxWidth: maxWidthPt, maxHeight: maxHeightPt),
        child: pw.Image(
          pw.MemoryImage(branding.institutionalIssuerMarkImage!.bytes),
          fit: pw.BoxFit.contain,
        ),
      ),
    );
  }

  /// Linha de Branding com resolução dos 4 cenários:
  /// 1. productMarkOnly
  /// 2. institutionalIssuerMarkOnly
  /// 3. both
  /// 4. neither
  static pw.Widget brandingHeaderRow(ReportBranding branding, PdfFonts fonts) {
    switch (branding.scenario) {
      case BrandingScenario.both:
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            productMark(branding, fonts),
            institutionalIssuerMark(branding),
          ],
        );
      case BrandingScenario.productMarkOnly:
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            productMark(branding, fonts),
          ],
        );
      case BrandingScenario.institutionalIssuerMarkOnly:
        return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            institutionalIssuerMark(branding),
          ],
        );
      case BrandingScenario.neither:
        return pw.SizedBox.shrink();
    }
  }

  // =========================================================================
  // 2. STATUS BADGE
  // =========================================================================

  /// Badge de status com acessibilidade e contraste garantido.
  /// Utiliza exclusivamente os 6 tons genéricos de [ReportTone].
  static pw.Widget statusBadge(
    String label,
    ReportTone tone,
    PdfFonts fonts, {
    String? iconText,
  }) {
    final colors = ReportToneColors.of(tone);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: pw.BoxDecoration(
        color: colors.background,
        border: pw.Border.all(color: colors.border, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            decoration: pw.BoxDecoration(
              color: colors.accent,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 4),
          if (iconText != null && iconText.isNotEmpty) ...[
            pw.Text(
              iconText,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 7.5,
                color: colors.text,
              ),
            ),
            pw.SizedBox(width: 3),
          ],
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 7.5,
              color: colors.text,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. CABEÇALHOS (HEADERS)
  // =========================================================================

  /// Cabeçalho Institucional / Legal: variante formal.
  static pw.Widget institutionalHeader({
    required String title,
    String? subtitle,
    String? organization,
    required ReportMetadata metadata,
    ReportBranding branding = const ReportBranding(),
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportColors.borderStrong, width: 1.0),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.lg),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Linha de brasão/emblema e product mark
          brandingHeaderRow(branding, fonts),
          pw.SizedBox(height: ReportSpacing.xs),

          // Organização / Órgão Superior (se houver)
          if (organization != null && organization.isNotEmpty) ...[
            pw.Text(
              organization.toUpperCase(),
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 9,
                color: ReportColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: ReportSpacing.xxs),
          ],

          // Título do Documento
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 16,
              color: ReportColors.textPrimary,
            ),
          ),

          // Subtítulo
          if (subtitle != null && subtitle.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.xxs),
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: ReportColors.textMuted,
              ),
            ),
          ],

          pw.SizedBox(height: ReportSpacing.sm),

          // Metadados universais e condicionais
          metadataRow(metadata, fonts),
        ],
      ),
    );
  }

  /// Cabeçalho Padrão / Analítico: variante operacional, clínica e gerencial.
  static pw.Widget standardReportHeader({
    required String title,
    String? category,
    String? subtitle,
    required ReportMetadata metadata,
    ReportBranding branding = const ReportBranding(),
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportColors.borderSoft, width: 1.5),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.lg),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Linha de Branding
          brandingHeaderRow(branding, fonts),
          pw.SizedBox(height: ReportSpacing.sm),

          // Categoria (opcional)
          if (category != null && category.isNotEmpty) ...[
            pw.Text(
              category.toUpperCase(),
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 8,
                color: ReportColors.accent,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: ReportSpacing.xxs),
          ],

          // Título Principal
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 18,
              color: ReportColors.textPrimary,
            ),
          ),

          // Subtítulo
          if (subtitle != null && subtitle.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.xxs),
            pw.Text(
              subtitle,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 10,
                color: ReportColors.textSecondary,
              ),
            ),
          ],

          pw.SizedBox(height: ReportSpacing.sm),

          // Barra de metadados
          metadataRow(metadata, fonts),
        ],
      ),
    );
  }

  /// Cabeçalho de Continuação Compacto para páginas 2..N.
  static pw.Widget compactContinuationHeader({
    required String title,
    String? documentId,
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ReportColors.borderSoft, width: 0.75),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: ReportSpacing.xs),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 8.5,
              color: ReportColors.textSecondary,
            ),
          ),
          if (documentId != null && documentId.isNotEmpty)
            pw.Text(
              'ID: $documentId',
              style: pw.TextStyle(
                font: fonts.monoRegular,
                fontSize: 8,
                color: ReportColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // 4. METADADOS
  // =========================================================================

  /// Linha de metadados com omissão elegante de campos nulos.
  ///
  /// GENERATED_AT é universalmente obrigatório.
  /// DOCUMENT_ID é condicional.
  static pw.Widget metadataRow(ReportMetadata metadata, PdfFonts fonts) {
    final items = <pw.Widget>[];

    // Data de geração obrigatória
    items.add(
      _metadataItem(
        label: 'EMISSÃO',
        value: _dateTimeFormat.format(metadata.generatedAt),
        fonts: fonts,
        isMono: true,
      ),
    );

    // ID do documento (condicional)
    if (metadata.documentId != null && metadata.documentId!.isNotEmpty) {
      items.add(
        _metadataItem(
          label: 'ID DO DOCUMENTO',
          value: metadata.documentId!,
          fonts: fonts,
          isMono: true,
        ),
      );
    }

    // Operador / Autor
    if (metadata.operatorName != null && metadata.operatorName!.isNotEmpty) {
      items.add(
        _metadataItem(
          label: 'OPERADOR',
          value: metadata.operatorName!,
          fonts: fonts,
        ),
      );
    }

    // Prefixo / Callsign
    if (metadata.callsign != null && metadata.callsign!.isNotEmpty) {
      items.add(
        _metadataItem(
          label: 'PREFIXO',
          value: metadata.callsign!,
          fonts: fonts,
          isMono: true,
        ),
      );
    }

    // Período
    if (metadata.period != null && metadata.period!.isNotEmpty) {
      items.add(
        _metadataItem(
          label: 'PERÍODO',
          value: metadata.period!,
          fonts: fonts,
        ),
      );
    }

    // Identidade K9
    if (metadata.dogIdentity != null && metadata.dogIdentity!.isNotEmpty) {
      items.add(
        _metadataItem(
          label: 'K9',
          value: metadata.dogIdentity!,
          fonts: fonts,
        ),
      );
    }

    return pw.Wrap(
      spacing: ReportSpacing.lg,
      runSpacing: ReportSpacing.xs,
      children: items,
    );
  }

  static pw.Widget _metadataItem({
    required String label,
    required String value,
    required PdfFonts fonts,
    bool isMono = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 7,
            color: ReportColors.textMuted,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 1),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: isMono ? fonts.monoRegular : fonts.regular,
            fontSize: 8.5,
            color: ReportColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 5. PRIMITIVAS DE CONTEÚDO
  // =========================================================================

  /// Bloco de Identidade Formal K9 ou Humana.
  static pw.Widget entityIdentityBlock(EntityIdentityData data, PdfFonts fonts) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.title,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 12,
                      color: ReportColors.textPrimary,
                    ),
                  ),
                  if (data.subtitle != null && data.subtitle!.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      data.subtitle!,
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 8.5,
                        color: ReportColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              if (data.statusLabel != null && data.statusTone != null)
                statusBadge(data.statusLabel!, data.statusTone!, fonts),
            ],
          ),
          if (data.fields.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.sm),
            pw.Container(height: 0.5, color: ReportColors.borderSoft),
            pw.SizedBox(height: ReportSpacing.sm),
            pw.Wrap(
              spacing: ReportSpacing.xl,
              runSpacing: ReportSpacing.sm,
              children: data.fields.map((field) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text(
                      field.label.toUpperCase(),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7,
                        color: ReportColors.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      field.value,
                      style: pw.TextStyle(
                        font: field.isMonospace ? fonts.monoRegular : fonts.bold,
                        fontSize: 8.5,
                        color: ReportColors.textPrimary,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Card de Resumo / Alerta em destaque.
  static pw.Widget summaryCard(SummaryCardData data, PdfFonts fonts) {
    final colors = ReportToneColors.of(data.tone);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: colors.border, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 6,
                height: 6,
                decoration: pw.BoxDecoration(
                  color: colors.accent,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Text(
                  data.title,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 10,
                    color: ReportColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (data.description != null && data.description!.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.xs),
            pw.Text(
              data.description!,
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 8.5,
                color: ReportColors.textSecondary,
              ),
            ),
          ],
          if (data.bulletItems != null && data.bulletItems!.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.xs),
            ...data.bulletItems!.map((bullet) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('• ', style: pw.TextStyle(font: fonts.bold, fontSize: 8.5, color: colors.accent)),
                    pw.Expanded(
                      child: pw.Text(
                        bullet,
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8.5, color: ReportColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Card de Métrica / KPI.
  static pw.Widget metricCard(MetricCardData data, PdfFonts fonts) {
    final colors = ReportToneColors.of(data.tone);
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            data.label.toUpperCase(),
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 7.5,
              color: ReportColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: ReportSpacing.xs),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                data.value,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 18,
                  color: ReportColors.textPrimary,
                ),
              ),
              if (data.unit != null && data.unit!.isNotEmpty) ...[
                pw.SizedBox(width: 4),
                pw.Text(
                  data.unit!,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 9,
                    color: ReportColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          if (data.trend != null && data.trend!.isNotEmpty) ...[
            pw.SizedBox(height: ReportSpacing.xxs),
            pw.Text(
              data.trend!,
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 8,
                color: colors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Seção de Informações com título destacado.
  static pw.Widget informationSection(
    String title,
    List<pw.Widget> children,
    PdfFonts fonts,
  ) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.lg),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: ReportSpacing.xs),
            margin: const pw.EdgeInsets.only(bottom: ReportSpacing.sm),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: ReportColors.borderSoft, width: 1),
              ),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 3,
                  height: 12,
                  decoration: pw.BoxDecoration(
                    color: ReportColors.accent,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 11,
                    color: ReportColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  /// Linha do Tempo Operacional (Timeline).
  static pw.Widget timelineSection(List<TimelineNodeData> nodes, PdfFonts fonts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: nodes.map((node) {
        final colors = ReportToneColors.of(node.tone);
        final timeStr = node.timeLabel ??
            (node.timestamp != null ? _dateTimeFormat.format(node.timestamp!) : '');

        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Indicador temporal
            pw.SizedBox(
              width: 85,
              child: pw.Text(
                timeStr,
                style: pw.TextStyle(
                  font: fonts.monoRegular,
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                ),
              ),
            ),
            // Ponto do nó
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              width: 6,
              height: 6,
              decoration: pw.BoxDecoration(
                color: colors.accent,
                shape: pw.BoxShape.circle,
              ),
            ),
            // Conteúdo
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.only(bottom: ReportSpacing.sm),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      node.title,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 8.5,
                        color: ReportColors.textPrimary,
                      ),
                    ),
                    if (node.description != null && node.description!.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        node.description!,
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8,
                          color: ReportColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  /// Tabela de Dados com repetição de cabeçalho, zebra rows (surfaceSubtle) e alinhamentos canônicos:
  /// - texto: left
  /// - datas: center mono
  /// - números/pesos: right mono
  static pw.Widget dataTable(DataTableData data, PdfFonts fonts) {
    return pw.Table(
      border: pw.TableBorder.all(color: ReportColors.borderSoft, width: 0.5),
      columnWidths: {
        for (int i = 0; i < data.columns.length; i++)
          i: pw.FlexColumnWidth(data.columns[i].flex),
      },
      children: [
        // Cabeçalho da tabela com repeat: true
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: ReportColors.surfaceSubtle),
          children: data.columns.map((col) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              alignment: _alignmentToPdfAlignment(col.alignment),
              child: pw.Text(
                col.header.toUpperCase(),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7.5,
                  color: ReportColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            );
          }).toList(),
        ),

        // Linhas de dados (com zebra striping)
        ...data.rows.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          final isZebra = index.isOdd;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isZebra ? ReportColors.surfaceSubtle : ReportColors.surface,
            ),
            children: [
              for (int i = 0; i < data.columns.length; i++)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
                  alignment: _alignmentToPdfAlignment(data.columns[i].alignment),
                  child: pw.Text(
                    i < row.cells.length ? row.cells[i] : '',
                    style: pw.TextStyle(
                      font: data.columns[i].isMonospace ? fonts.monoRegular : fonts.regular,
                      fontSize: 8,
                      color: ReportColors.textPrimary,
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Alignment _alignmentToPdfAlignment(DataTableCellAlignment alignment) {
    switch (alignment) {
      case DataTableCellAlignment.left:
        return pw.Alignment.centerLeft;
      case DataTableCellAlignment.center:
        return pw.Alignment.center;
      case DataTableCellAlignment.right:
        return pw.Alignment.centerRight;
    }
  }

  /// Bloco de Evidência com PRESERVAÇÃO ESTRITA de proporção (aspect ratio contain)
  /// e agrupamento inseparável de imagem + legenda (keep-together).
  static pw.Widget evidenceBlock(EvidenceItemData item, PdfFonts fonts) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.sm),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // Imagem contida sem corte nem distorção
          pw.Center(
            child: pw.ConstrainedBox(
              constraints: const pw.BoxConstraints(maxHeight: 180),
              child: pw.Image(
                pw.MemoryImage(item.image.bytes),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
          pw.SizedBox(height: ReportSpacing.xs),
          // Legenda inseparável da imagem
          pw.Text(
            item.caption,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8,
              color: ReportColors.textSecondary,
            ),
          ),
          if (item.timestamp != null || item.metadata != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              [item.timestamp, item.metadata].whereType<String>().join(' · '),
              style: pw.TextStyle(
                font: fonts.monoRegular,
                fontSize: 7,
                color: ReportColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bloco de Anexos.
  static pw.Widget attachmentBlock(List<AttachmentItemData> attachments, PdfFonts fonts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: attachments.map((att) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          margin: const pw.EdgeInsets.only(bottom: 4),
          decoration: pw.BoxDecoration(
            color: ReportColors.surfaceSubtle,
            border: pw.Border.all(color: ReportColors.borderSoft, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Text('📎 ', style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                  pw.Text(
                    att.fileName,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 8,
                      color: ReportColors.textPrimary,
                    ),
                  ),
                  if (att.fileSize != null) ...[
                    pw.SizedBox(width: 6),
                    pw.Text(
                      '(${att.fileSize})',
                      style: pw.TextStyle(
                        font: fonts.regular,
                        fontSize: 7.5,
                        color: ReportColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              if (att.hash != null)
                pw.Text(
                  att.hash!,
                  style: pw.TextStyle(
                    font: fonts.monoRegular,
                    fontSize: 7,
                    color: ReportColors.textMuted,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// Bloco de Observações.
  static pw.Widget observationBlock(ObservationBlockData data, PdfFonts fonts) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            data.title.toUpperCase(),
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: 7.5,
              color: ReportColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          pw.SizedBox(height: ReportSpacing.xs),
          pw.Text(
            data.text,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 8.5,
              color: ReportColors.textPrimary,
              lineSpacing: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 6. ASSINATURAS E AUDITORIA
  // =========================================================================

  /// Bloco de Assinatura Individual.
  static pw.Widget signatureBlock(SignatureData signature, PdfFonts fonts) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 180,
          height: 0.75,
          color: ReportColors.borderStrong,
        ),
        pw.SizedBox(height: ReportSpacing.xs),
        pw.Text(
          signature.name,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 8.5,
            color: ReportColors.textPrimary,
          ),
        ),
        pw.Text(
          signature.role,
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 7.5,
            color: ReportColors.textSecondary,
          ),
        ),
        if (signature.identifier != null && signature.identifier!.isNotEmpty) ...[
          pw.SizedBox(height: 1),
          pw.Text(
            signature.identifier!,
            style: pw.TextStyle(
              font: fonts.monoRegular,
              fontSize: 7,
              color: ReportColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }

  /// Bloco de Co-Assinaturas (múltiplas assinaturas alinhadas) com proteção
  /// contra quebra isolada.
  static pw.Widget coSignatureBlock(List<SignatureData> signatures, PdfFonts fonts) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: ReportSpacing.xl, bottom: ReportSpacing.md),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: signatures.map((sig) {
          return pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: ReportSpacing.sm),
              child: signatureBlock(sig, fonts),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Bloco de Auditoria e Integridade.
  ///
  /// Agnóstico a provedor (NÃO assume rotas internas como `/v/[id]`).
  /// Exibe: QR code, URL legível e hash com algoritmo.
  static pw.Widget auditBlock(AuditData audit, PdfFonts fonts) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 0.75),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      margin: const pw.EdgeInsets.only(top: ReportSpacing.lg, bottom: ReportSpacing.md),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // QR Code oficial renderizado via BarcodeWidget
          pw.Container(
            padding: const pw.EdgeInsets.all(3),
            color: ReportColors.surface,
            child: pw.BarcodeWidget(
              data: audit.verificationUrl,
              barcode: pw.Barcode.qrCode(),
              width: 54,
              height: 54,
            ),
          ),
          pw.SizedBox(width: ReportSpacing.md),

          // Informações de integridade
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'VERIFICAÇÃO DOCUMENTAL E INTEGRIDADE',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 7.5,
                    color: ReportColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Escaneie o código ou acesse o endereço abaixo para verificar a autenticidade deste documento:',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 7.5,
                    color: ReportColors.textSecondary,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  audit.verificationUrl,
                  style: pw.TextStyle(
                    font: fonts.monoRegular,
                    fontSize: 7,
                    color: ReportColors.accent,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Text(
                      '${audit.algorithm}: ',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7,
                        color: ReportColors.textMuted,
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        audit.hash,
                        style: pw.TextStyle(
                          font: fonts.monoRegular,
                          fontSize: 6.8,
                          color: ReportColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (audit.documentId != null && audit.documentId!.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'ID Canônico: ${audit.documentId}',
                    style: pw.TextStyle(
                      font: fonts.monoRegular,
                      fontSize: 6.8,
                      color: ReportColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 7. RODAPÉ E PAGINAÇÃO
  // =========================================================================

  /// Rodapé Canônico para todas as páginas.
  static pw.Widget reportFooter(
    pw.Context context, {
    required String title,
    String? documentId,
    String? disclaimer,
    required PdfFonts fonts,
  }) {
    final pageStr = 'Página ${context.pageNumber} de ${context.pagesCount}';

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: ReportColors.borderSoft, width: 0.75),
        ),
      ),
      padding: const pw.EdgeInsets.only(top: ReportSpacing.xs),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    'K9 Ops · $title',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 7.5,
                      color: ReportColors.textSecondary,
                    ),
                  ),
                  if (documentId != null && documentId.isNotEmpty) ...[
                    pw.Text(
                      ' · ID: $documentId',
                      style: pw.TextStyle(
                        font: fonts.monoRegular,
                        fontSize: 7,
                        color: ReportColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              if (disclaimer != null && disclaimer.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  disclaimer,
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 6.5,
                    color: ReportColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
          pw.Text(
            pageStr,
            style: pw.TextStyle(
              font: fonts.monoRegular,
              fontSize: 7.5,
              color: ReportColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
