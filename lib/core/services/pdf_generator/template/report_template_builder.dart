import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_common_widgets.dart';
import 'report_primitives.dart';
import 'report_tokens.dart';
import 'report_types.dart';

/// Builder orquestrador de relatórios baseado no K9 Ops Report Design System V1.
///
/// Encapsula paginação automática (A4 portrait ou landscape), cabeçalhos de continuação
/// nas páginas subsequentes, rodapés canônicos e suporte aos 5 arquétipos frozen.
class ReportTemplateBuilder {
  final String title;
  final String? subtitle;
  final String? organization;
  final String? category;
  final String? disclaimer;
  final ReportMetadata metadata;
  final ReportBranding branding;
  final ReportArchetypeConfig archetypeConfig;
  final String? motto;
  final bool useDarkFooter;
  final String? statusLabel;
  final ReportTone? statusTone;

  final List<pw.Widget> _contentWidgets = [];

  ReportTemplateBuilder({
    required this.title,
    this.subtitle,
    this.organization,
    this.category,
    this.disclaimer,
    required this.metadata,
    this.branding = const ReportBranding(),
    ReportArchetypeConfig? archetypeConfig,
    this.motto,
    this.useDarkFooter = false,
    this.statusLabel,
    this.statusTone,
  }) : archetypeConfig = archetypeConfig ?? ReportArchetypeConfig.operational();

  /// Construtor de conveniência por arquétipo.
  factory ReportTemplateBuilder.forArchetype({
    required ReportArchetype archetype,
    required String title,
    String? subtitle,
    String? organization,
    String? category,
    String? disclaimer,
    required ReportMetadata metadata,
    ReportBranding branding = const ReportBranding(),
    PageOrientation? orientationOverride,
  }) {
    var config = ReportArchetypeConfig.forArchetype(archetype);
    if (orientationOverride != null) {
      config = ReportArchetypeConfig(
        archetype: config.archetype,
        name: config.name,
        orientation: orientationOverride,
        headerVariant: config.headerVariant,
        requiresAuditBlock: config.requiresAuditBlock,
        requiresSignatures: config.requiresSignatures,
        supportsTimeline: config.supportsTimeline,
        supportsIdentityBlock: config.supportsIdentityBlock,
        supportsDataTable: config.supportsDataTable,
      );
    }

    return ReportTemplateBuilder(
      title: title,
      subtitle: subtitle,
      organization: organization,
      category: category,
      disclaimer: disclaimer,
      metadata: metadata,
      branding: branding,
      archetypeConfig: config,
    );
  }

  /// Adiciona um widget qualquer ao corpo do relatório.
  ReportTemplateBuilder addWidget(pw.Widget widget) {
    _contentWidgets.add(widget);
    return this;
  }

  /// Adiciona múltiplos widgets ao corpo do relatório.
  ReportTemplateBuilder addWidgets(List<pw.Widget> widgets) {
    _contentWidgets.addAll(widgets);
    return this;
  }

  /// Constrói o documento PDF com MultiPage, paginação canônica e fontes institucionais.
  Future<Uint8List> buildPdf({PdfFonts? customFonts}) async {
    final fonts = customFonts ?? await PdfFonts.load();
    final pdf = pw.Document(
      title: title,
      author: organization ?? 'K9 Ops',
      theme: fonts.toThemeData(),
    );

    final format = archetypeConfig.orientation == PageOrientation.portrait
        ? ReportPageMetrics.portraitFormat
        : ReportPageMetrics.landscapeFormat;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (context) {
          // Na página 1, o cabeçalho principal é construído no corpo
          if (context.pageNumber == 1) {
            return pw.SizedBox.shrink();
          }
          // Nas páginas 2..N, cabeçalho de continuação apropriado
          if (archetypeConfig.headerVariant == HeaderVariant.darkTactical) {
            return ReportPrimitives.darkCompactContinuationHeader(
              title: title,
              documentId: metadata.documentId,
              fonts: fonts,
            );
          }
          return ReportPrimitives.compactContinuationHeader(
            title: title,
            documentId: metadata.documentId,
            fonts: fonts,
          );
        },
        footer: (context) {
          if (useDarkFooter) {
            return ReportPrimitives.darkReportFooter(
              context,
              title: title,
              documentId: metadata.documentId,
              disclaimer: disclaimer,
              fonts: fonts,
            );
          }
          return ReportPrimitives.reportFooter(
            context,
            title: title,
            documentId: metadata.documentId,
            disclaimer: disclaimer,
            fonts: fonts,
          );
        },
        build: (context) {
          final pageContent = <pw.Widget>[];

          // 1. Cabeçalho primário na página inicial
          switch (archetypeConfig.headerVariant) {
            case HeaderVariant.institutional:
              pageContent.add(
                ReportPrimitives.institutionalHeader(
                  title: title,
                  subtitle: subtitle,
                  organization: organization,
                  metadata: metadata,
                  branding: branding,
                  fonts: fonts,
                ),
              );
              break;
            case HeaderVariant.standard:
              pageContent.add(
                ReportPrimitives.standardReportHeader(
                  title: title,
                  category: category,
                  subtitle: subtitle,
                  metadata: metadata,
                  branding: branding,
                  fonts: fonts,
                ),
              );
              break;
            case HeaderVariant.compact:
              pageContent.add(
                ReportPrimitives.compactContinuationHeader(
                  title: title,
                  documentId: metadata.documentId,
                  fonts: fonts,
                ),
              );
              break;
            case HeaderVariant.darkTactical:
              pageContent.add(
                ReportPrimitives.darkTacticalHeader(
                  title: title,
                  subtitle: subtitle,
                  organization: organization,
                  category: category,
                  motto: motto,
                  metadata: metadata,
                  branding: branding,
                  fonts: fonts,
                  statusLabel: statusLabel,
                  statusTone: statusTone,
                ),
              );
              break;
          }

          // 2. Conteúdo injetado
          pageContent.addAll(_contentWidgets);

          return pageContent;
        },
      ),
    );

    return pdf.save();
  }
}
