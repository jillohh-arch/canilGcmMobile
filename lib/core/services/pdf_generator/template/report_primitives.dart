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

  /// Cabeçalho Tático K9 Ops V2 (Dark Navy #0A1A24).
  static pw.Widget darkTacticalHeader({
    required String title,
    String? subtitle,
    String? organization,
    String? category,
    String? motto,
    required ReportMetadata metadata,
    ReportBranding branding = const ReportBranding(),
    required PdfFonts fonts,
    String? statusLabel,
    ReportTone? statusTone,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.darkNavy,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Linha Superior: Badge K9 OPS® + Categoria à esquerda | Motto/Unidade à direita
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: pw.BoxDecoration(
                      color: ReportColors.darkNavySurface,
                      border: pw.Border.all(color: ReportColors.darkNavyBorder, width: 0.75),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Text(
                      'K9 OPS®',
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 8.5,
                        color: ReportColors.cyanAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (category != null && category.isNotEmpty) ...[
                    pw.SizedBox(width: 8),
                    pw.Text(
                      category.toUpperCase(),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 7.5,
                        color: ReportColors.cyanAccent,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ],
              ),
              pw.Text(
                (motto ?? organization ?? 'DISCIPLINA · PROTEÇÃO · RESULTADO').toUpperCase(),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7,
                  color: ReportColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // Linha do Título Principal e Status Badge
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title.toUpperCase(),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 15,
                        color: ReportColors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        subtitle,
                        style: pw.TextStyle(
                          font: fonts.regular,
                          fontSize: 8.5,
                          color: ReportColors.cyanAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (statusLabel != null && statusTone != null)
                statusBadge(statusLabel, statusTone, fonts),
            ],
          ),
          pw.SizedBox(height: 8),

          // Barra de Metadados (Doc ID, Emissão, K9)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: pw.BoxDecoration(
              color: ReportColors.darkNavySurface,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (metadata.documentId != null && metadata.documentId!.isNotEmpty) ...[
                      pw.Text(
                        'ID: ',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 7, color: ReportColors.textMuted),
                      ),
                      pw.Text(
                        metadata.documentId!,
                        style: pw.TextStyle(font: fonts.monoRegular, fontSize: 7.5, color: ReportColors.white),
                      ),
                      pw.SizedBox(width: 12),
                    ],
                    pw.Text(
                      'EMISSÃO: ',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 7, color: ReportColors.textMuted),
                    ),
                    pw.Text(
                      _dateTimeFormat.format(metadata.generatedAt),
                      style: pw.TextStyle(font: fonts.monoRegular, fontSize: 7.5, color: ReportColors.white),
                    ),
                  ],
                ),
                if (metadata.dogIdentity != null && metadata.dogIdentity!.isNotEmpty) ...[
                  pw.Row(
                    children: [
                      pw.Text(
                        'K9: ',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 7, color: ReportColors.cyanAccent),
                      ),
                      pw.Text(
                        metadata.dogIdentity!,
                        style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: ReportColors.white),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 6),

          // Linha de acento inferior
          pw.Row(
            children: [
              pw.Container(width: 140, height: 2, color: ReportColors.accent),
              pw.Container(width: 80, height: 2, color: ReportColors.cyanAccent),
              pw.Expanded(child: pw.Container(height: 2, color: ReportColors.darkNavySurface)),
            ],
          ),
        ],
      ),
    );
  }

  /// Cabeçalho Tático Compacto para páginas de continuação (2..N).
  static pw.Widget darkCompactContinuationHeader({
    required String title,
    String? documentId,
    required PdfFonts fonts,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.darkNavy,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'K9 OPS® · ',
                style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: ReportColors.cyanAccent),
              ),
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(font: fonts.bold, fontSize: 8, color: ReportColors.white),
              ),
            ],
          ),
          if (documentId != null && documentId.isNotEmpty)
            pw.Text(
              'ID: $documentId',
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
    final hasPhotoOrTags = data.avatar != null || data.tags.isNotEmpty || data.avatarPlaceholder != null;

    if (!hasPhotoOrTags) {
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

    // Layout Tático Enriquecido (Avatar/Foto + Tags Operacionais)
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surface,
        border: pw.Border.all(color: ReportColors.borderSoft, width: 1),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      padding: const pw.EdgeInsets.all(ReportSpacing.md),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.md),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Avatar ou Placeholder Tático
              if (data.avatar != null) ...[
                pw.Container(
                  width: 52,
                  height: 52,
                  decoration: pw.BoxDecoration(
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: ReportColors.borderSoft),
                  ),
                  child: pw.ClipRRect(
                    horizontalRadius: 4,
                    verticalRadius: 4,
                    child: pw.Image(
                      pw.MemoryImage(data.avatar!.bytes),
                      fit: pw.BoxFit.cover,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
              ] else ...[
                pw.Container(
                  width: 50,
                  height: 50,
                  decoration: pw.BoxDecoration(
                    color: ReportColors.darkNavy,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: ReportColors.cyanAccent, width: 1),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    data.avatarPlaceholder ?? 'K9',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 16,
                      color: ReportColors.cyanAccent,
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
              ],

              // Informações centrais e Badges
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      data.title,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 14,
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
                    pw.SizedBox(height: 4),
                    // Linha de tags e status
                    pw.Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      crossAxisAlignment: pw.WrapCrossAlignment.center,
                      children: [
                        ...data.tags.map((tag) {
                          return pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: ReportColors.darkNavy,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2.5)),
                            ),
                            child: pw.Text(
                              tag.toUpperCase(),
                              style: pw.TextStyle(
                                font: fonts.bold,
                                fontSize: 6.8,
                                color: ReportColors.goldAccent,
                                letterSpacing: 0.4,
                              ),
                            ),
                          );
                        }),
                        if (data.statusLabel != null && data.statusTone != null)
                          statusBadge(data.statusLabel!, data.statusTone!, fonts),
                      ],
                    ),
                  ],
                ),
              ),
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

  /// Título de Seção Estilizado K9 Ops com Badge/Ícone e Acento Visual.
  static pw.Widget styledSectionTitle(
    String title,
    PdfFonts fonts, {
    String? iconText,
    String? subtitle,
    ReportTone tone = ReportTone.info,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8, bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (iconText != null && iconText.isNotEmpty) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                  margin: const pw.EdgeInsets.only(right: 6),
                  decoration: pw.BoxDecoration(
                    color: ReportColors.darkNavy,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                  ),
                  child: pw.Text(
                    iconText.toUpperCase(),
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: 7.5,
                      color: ReportColors.cyanAccent,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ] else ...[
                pw.Container(
                  width: 3,
                  height: 12,
                  margin: const pw.EdgeInsets.only(right: 6),
                  decoration: pw.BoxDecoration(
                    color: ReportColors.accent,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(1.5)),
                  ),
                ),
              ],
              pw.Text(
                title.toUpperCase(),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 9.5,
                  color: ReportColors.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  height: 1,
                  color: ReportColors.borderSoft,
                ),
              ),
            ],
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 12),
              child: pw.Text(
                subtitle,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7.5,
                  color: ReportColors.textMuted,
                ),
              ),
            ),
          ],
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

  /// Gráfico Vetorial de Evolução Ponderal K9 Ops.
  static pw.Widget weightTrendChart({
    required List<WeightChartPoint> points,
    double? idealMin,
    double? idealMax,
    required PdfFonts fonts,
    double height = 100,
  }) {
    if (points.length < 2) {
      return pw.Container(
        height: 50,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: ReportColors.surfaceSubtle,
          border: pw.Border.all(color: ReportColors.borderSoft),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Text(
          'Sem dados suficientes para exibição do gráfico ponderal (mínimo de 2 pesagens).',
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 8.5,
            color: ReportColors.textMuted,
          ),
        ),
      );
    }

    final weights = points.map((p) => p.weight).toList();
    double minWeight = weights.reduce((a, b) => a < b ? a : b);
    double maxWeight = weights.reduce((a, b) => a > b ? a : b);

    if (idealMin != null && idealMin < minWeight) {
      minWeight = idealMin;
    }
    if (idealMax != null && idealMax > maxWeight) {
      maxWeight = idealMax;
    }

    final minVal = minWeight - 0.5;
    final maxVal = maxWeight + 0.5;
    final range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    final firstDateStr = DateFormat('dd/MM/yyyy').format(points.first.date);
    final lastDateStr = DateFormat('dd/MM/yyyy').format(points.last.date);

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.surfaceSubtle,
        border: pw.Border.all(color: ReportColors.borderSoft),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.all(10),
      margin: const pw.EdgeInsets.only(bottom: ReportSpacing.sm),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Legenda do gráfico
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 8, height: 8, color: ReportColors.accent),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    'Evolução do Peso (kg)',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: ReportColors.textSecondary),
                  ),
                  if (idealMin != null && idealMax != null) ...[
                    pw.SizedBox(width: 12),
                    pw.Container(width: 8, height: 8, color: PdfColor.fromHex('BBF7D0')),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      'Faixa Ideal (${idealMin.toStringAsFixed(1)} - ${idealMax.toStringAsFixed(1)} kg)',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 7.5, color: PdfColor.fromHex('166534')),
                    ),
                  ],
                ],
              ),
              pw.Text(
                'Min: ${minWeight.toStringAsFixed(1)} kg | Max: ${maxWeight.toStringAsFixed(1)} kg',
                style: pw.TextStyle(font: fonts.monoRegular, fontSize: 7.5, color: ReportColors.textMuted),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // Área de plotagem com pw.CustomPaint
          pw.Container(
            height: height,
            child: pw.CustomPaint(
              painter: (canvas, size) {
                final width = size.x;
                final plotHeight = size.y;
                final padX = 20.0;
                final padY = 12.0;
                final usableW = width - (padX * 2);
                final usableH = plotHeight - (padY * 2);

                // 1. Faixa ideal sombreada (verde claro)
                if (idealMin != null && idealMax != null) {
                  final yMin = padY + ((idealMin - minVal) / range) * usableH;
                  final yMax = padY + ((idealMax - minVal) / range) * usableH;
                  canvas
                    ..setFillColor(PdfColor.fromHex('DCFCE7'))
                    ..drawRect(padX, yMin, usableW, yMax - yMin)
                    ..fillPath();
                }

                // 2. Linhas de grade sutis
                canvas
                  ..setLineWidth(0.4)
                  ..setStrokeColor(ReportColors.borderSoft);
                for (var i = 0; i <= 3; i++) {
                  final gy = padY + (usableH * i / 3);
                  canvas.drawLine(padX, gy, padX + usableW, gy);
                }
                canvas.strokePath();

                // 3. Linha conectando os pontos
                final coords = <PdfPoint>[];
                for (var i = 0; i < points.length; i++) {
                  final px = padX + (usableW * i / (points.length - 1));
                  final py = padY + (((points[i].weight - minVal) / range) * usableH);
                  coords.add(PdfPoint(px, py));
                }

                if (coords.isNotEmpty) {
                  canvas
                    ..setLineWidth(1.8)
                    ..setStrokeColor(ReportColors.accent)
                    ..moveTo(coords.first.x, coords.first.y);
                  for (final pt in coords.skip(1)) {
                    canvas.lineTo(pt.x, pt.y);
                  }
                  canvas.strokePath();

                  // 4. Marcadores de ponto
                  for (final pt in coords) {
                    canvas
                      ..setFillColor(ReportColors.surface)
                      ..setStrokeColor(ReportColors.accent)
                      ..setLineWidth(1.5)
                      ..drawEllipse(pt.x, pt.y, 2.5, 2.5)
                      ..fillPath()
                      ..drawEllipse(pt.x, pt.y, 2.5, 2.5)
                      ..strokePath();
                  }
                }
              },
            ),
          ),
          pw.SizedBox(height: 4),

          // Extremos temporais
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(firstDateStr, style: pw.TextStyle(font: fonts.monoRegular, fontSize: 7, color: ReportColors.textMuted)),
              pw.Text('${points.length} pesagens na série', style: pw.TextStyle(font: fonts.regular, fontSize: 7, color: ReportColors.textMuted)),
              pw.Text(lastDateStr, style: pw.TextStyle(font: fonts.monoRegular, fontSize: 7, color: ReportColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  /// Tabela Rica com repetição de cabeçalho, zebra striping e suporte a células avançadas.
  static pw.Widget richDataTable(
    RichDataTableData data,
    PdfFonts fonts,
  ) {
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
          final rowBg = row.backgroundColor ?? (isZebra ? ReportColors.surfaceSubtle : ReportColors.surface);

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              for (int i = 0; i < data.columns.length; i++)
                _buildRichTableCell(
                  i < row.cells.length ? row.cells[i] : const RichTableCell.text(''),
                  data.columns[i],
                  fonts,
                ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildRichTableCell(
    RichTableCell cell,
    DataTableColumn col,
    PdfFonts fonts,
  ) {
    final align = cell.alignment ?? col.alignment;
    final pdfAlign = _alignmentToPdfAlignment(align);

    // 1. Célula com Badge
    if (cell.badgeTone != null && cell.badgeText != null) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        alignment: pdfAlign,
        child: statusBadge(cell.badgeText!, cell.badgeTone!, fonts),
      );
    }

    // 2. Célula de duas linhas (Texto principal + secundário)
    if (cell.secondaryText != null && cell.secondaryText!.isNotEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
        alignment: pdfAlign,
        child: pw.Column(
          crossAxisAlignment: align == DataTableCellAlignment.center
              ? pw.CrossAxisAlignment.center
              : (align == DataTableCellAlignment.right ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start),
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(
              cell.text,
              style: pw.TextStyle(
                font: cell.isBold ? fonts.bold : fonts.regular,
                fontSize: 8,
                color: cell.textColor ?? ReportColors.textPrimary,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              cell.secondaryText!,
              style: pw.TextStyle(
                font: cell.isMonospace ? fonts.monoRegular : fonts.regular,
                fontSize: 7,
                color: ReportColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // 3. Célula de texto padrão
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      alignment: pdfAlign,
      child: pw.Text(
        cell.text,
        style: pw.TextStyle(
          font: cell.isMonospace ? fonts.monoRegular : (cell.isBold ? fonts.bold : fonts.regular),
          fontSize: 8,
          color: cell.textColor ?? ReportColors.textPrimary,
        ),
      ),
    );
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
                if (audit.trackingCode != null && audit.trackingCode!.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    'Código de Auditoria: ${audit.trackingCode}',
                    style: pw.TextStyle(
                      font: fonts.monoRegular,
                      fontSize: 6.8,
                      color: ReportColors.textMuted,
                    ),
                  ),
                ],
                if (audit.description != null && audit.description!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    audit.description!,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 6.8,
                      color: ReportColors.textSecondary,
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

  /// Rodapé Tático K9 Ops V2 (Dark Navy #0A1A24).
  static pw.Widget darkReportFooter(
    pw.Context context, {
    required String title,
    String? documentId,
    String? disclaimer,
    required PdfFonts fonts,
  }) {
    final pageStr = 'Página ${context.pageNumber} de ${context.pagesCount}';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: ReportColors.darkNavy,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              pw.Text(
                'K9 OPS®',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 7.5,
                  color: ReportColors.cyanAccent,
                ),
              ),
              pw.Text(
                ' · $title',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7.5,
                  color: ReportColors.surfaceSubtle,
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
          pw.Text(
            pageStr,
            style: pw.TextStyle(
              font: fonts.monoRegular,
              fontSize: 7.5,
              color: ReportColors.surfaceSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
