import 'dart:typed_data';
import 'package:pdf/pdf.dart';

import 'report_tokens.dart';

/// Imagem ou artefato em bytes para exibição nos slots do relatório.
class ReportImageSlot {
  final Uint8List bytes;
  final String? mimeType;
  final double? aspectRatio;

  const ReportImageSlot({
    required this.bytes,
    this.mimeType,
    this.aspectRatio,
  });
}

/// 4 cenários canônicos de renderização de branding.
enum BrandingScenario {
  productMarkOnly,
  institutionalIssuerMarkOnly,
  both,
  neither,
}

/// Configuração dos slots de branding do relatório.
class ReportBranding {
  final ReportImageSlot? productMarkImage;
  final ReportImageSlot? institutionalIssuerMarkImage;
  final String textualFallback;
  final bool showProductMark;
  final bool showInstitutionalIssuerMark;

  const ReportBranding({
    this.productMarkImage,
    this.institutionalIssuerMarkImage,
    this.textualFallback = 'K9 Ops',
    this.showProductMark = true,
    this.showInstitutionalIssuerMark = true,
  });

  BrandingScenario get scenario {
    final hasProduct = showProductMark;
    final hasIssuer = showInstitutionalIssuerMark && institutionalIssuerMarkImage != null;

    if (hasProduct && hasIssuer) return BrandingScenario.both;
    if (hasProduct && !hasIssuer) return BrandingScenario.productMarkOnly;
    if (!hasProduct && hasIssuer) return BrandingScenario.institutionalIssuerMarkOnly;
    return BrandingScenario.neither;
  }
}

/// Metadados do relatório.
///
/// REGRA CANÔNICA:
/// - [generatedAt] é o ÚNICO metadado universalmente obrigatório.
/// - [documentId] é condicional (apenas quando o documento tem ID canônico).
/// - Campos opcionais sem valor devem ser elegantemente omitidos (SEM 'N/A' automático,
///   SEM UUIDs sintéticos).
class ReportMetadata {
  final DateTime generatedAt;
  final String? documentId;
  final String? operatorName;
  final String? actorRole;
  final String? callsign;
  final String? period;
  final String? dogIdentity;
  final Map<String, String>? additional;

  const ReportMetadata({
    required this.generatedAt,
    this.documentId,
    this.operatorName,
    this.actorRole,
    this.callsign,
    this.period,
    this.dogIdentity,
    this.additional,
  });
}

/// 5 Arquétipos frozen do K9 Ops Report Design System V1.
enum ReportArchetype {
  institutional,
  operational,
  clinical,
  analytical,
  tabular,
}

/// Variante de cabeçalho.
enum HeaderVariant {
  institutional,
  standard,
  compact,
  darkTactical,
}

/// Orientação da página.
enum PageOrientation {
  portrait,
  landscape,
}

/// Configuração e capacidades composáveis do arquétipo.
class ReportArchetypeConfig {
  final ReportArchetype archetype;
  final String name;
  final PageOrientation orientation;
  final HeaderVariant headerVariant;
  final bool requiresAuditBlock;
  final bool requiresSignatures;
  final bool supportsTimeline;
  final bool supportsIdentityBlock;
  final bool supportsDataTable;

  const ReportArchetypeConfig({
    required this.archetype,
    required this.name,
    this.orientation = PageOrientation.portrait,
    this.headerVariant = HeaderVariant.standard,
    this.requiresAuditBlock = false,
    this.requiresSignatures = false,
    this.supportsTimeline = false,
    this.supportsIdentityBlock = false,
    this.supportsDataTable = true,
  });

  /// Arquétipo Institucional / Legal (Certidões, Laudos, Termos)
  factory ReportArchetypeConfig.institutional() {
    return const ReportArchetypeConfig(
      archetype: ReportArchetype.institutional,
      name: 'Institucional / Legal',
      orientation: PageOrientation.portrait,
      headerVariant: HeaderVariant.institutional,
      requiresAuditBlock: true,
      requiresSignatures: true,
      supportsTimeline: false,
      supportsIdentityBlock: true,
      supportsDataTable: true,
    );
  }

  /// Arquétipo Registro Operacional / Ocorrência
  factory ReportArchetypeConfig.operational() {
    return const ReportArchetypeConfig(
      archetype: ReportArchetype.operational,
      name: 'Registro Operacional',
      orientation: PageOrientation.portrait,
      headerVariant: HeaderVariant.standard,
      requiresAuditBlock: true,
      requiresSignatures: true,
      supportsTimeline: true,
      supportsIdentityBlock: true,
      supportsDataTable: true,
    );
  }

  /// Arquétipo Prontuário Clínico / Saúde
  factory ReportArchetypeConfig.clinical() {
    return const ReportArchetypeConfig(
      archetype: ReportArchetype.clinical,
      name: 'Prontuário Clínico',
      orientation: PageOrientation.portrait,
      headerVariant: HeaderVariant.standard,
      requiresAuditBlock: false,
      requiresSignatures: true,
      supportsTimeline: true,
      supportsIdentityBlock: true,
      supportsDataTable: true,
    );
  }

  /// Arquétipo Prontuário Clínico Tático K9 Ops V2 (Header Dark Tactical)
  factory ReportArchetypeConfig.clinicalTactical() {
    return const ReportArchetypeConfig(
      archetype: ReportArchetype.clinical,
      name: 'Prontuário Clínico Tático',
      orientation: PageOrientation.portrait,
      headerVariant: HeaderVariant.darkTactical,
      requiresAuditBlock: true,
      requiresSignatures: false,
      supportsTimeline: true,
      supportsIdentityBlock: true,
      supportsDataTable: true,
    );
  }

  /// Arquétipo Analítico / Gestão / Produtividade
  factory ReportArchetypeConfig.analytical({PageOrientation orientation = PageOrientation.portrait}) {
    return ReportArchetypeConfig(
      archetype: ReportArchetype.analytical,
      name: 'Analítico / Gestão',
      orientation: orientation,
      headerVariant: HeaderVariant.standard,
      requiresAuditBlock: false,
      requiresSignatures: false,
      supportsTimeline: false,
      supportsIdentityBlock: false,
      supportsDataTable: true,
    );
  }

  /// Arquétipo Tabular / Inventário / Efetivo
  factory ReportArchetypeConfig.tabular({PageOrientation orientation = PageOrientation.landscape}) {
    return ReportArchetypeConfig(
      archetype: ReportArchetype.tabular,
      name: 'Tabular / Inventário',
      orientation: orientation,
      headerVariant: HeaderVariant.standard,
      requiresAuditBlock: false,
      requiresSignatures: false,
      supportsTimeline: false,
      supportsIdentityBlock: false,
      supportsDataTable: true,
    );
  }

  static ReportArchetypeConfig forArchetype(ReportArchetype archetype) {
    switch (archetype) {
      case ReportArchetype.institutional:
        return ReportArchetypeConfig.institutional();
      case ReportArchetype.operational:
        return ReportArchetypeConfig.operational();
      case ReportArchetype.clinical:
        return ReportArchetypeConfig.clinical();
      case ReportArchetype.analytical:
        return ReportArchetypeConfig.analytical();
      case ReportArchetype.tabular:
        return ReportArchetypeConfig.tabular();
    }
  }
}

// ---------------------------------------------------------------------------
// Modelos das Primitivas de Conteúdo
// ---------------------------------------------------------------------------

class EntityIdentityField {
  final String label;
  final String value;
  final bool isMonospace;

  const EntityIdentityField({
    required this.label,
    required this.value,
    this.isMonospace = false,
  });
}

class EntityIdentityData {
  final String title;
  final String? subtitle;
  final String? registrationBadge;
  final List<EntityIdentityField> fields;
  final String? statusLabel;
  final ReportTone? statusTone;
  final ReportImageSlot? avatar;
  final List<String> tags;
  final String? avatarPlaceholder;
  final double photoWidth;
  final double photoHeight;

  const EntityIdentityData({
    required this.title,
    this.subtitle,
    this.registrationBadge,
    this.fields = const [],
    this.statusLabel,
    this.statusTone,
    this.avatar,
    this.tags = const [],
    this.avatarPlaceholder,
    this.photoWidth = 105,
    this.photoHeight = 120,
  });
}

class SummaryCardData {
  final String title;
  final String? description;
  final List<String>? bulletItems;
  final ReportTone tone;

  const SummaryCardData({
    required this.title,
    this.description,
    this.bulletItems,
    this.tone = ReportTone.neutral,
  });
}

class MetricCardData {
  final String label;
  final String value;
  final String? unit;
  final String? trend;
  final ReportTone tone;

  const MetricCardData({
    required this.label,
    required this.value,
    this.unit,
    this.trend,
    this.tone = ReportTone.neutral,
  });
}

class StatusBadgeData {
  final String label;
  final ReportTone tone;
  final String? iconText;

  const StatusBadgeData({
    required this.label,
    required this.tone,
    this.iconText,
  });
}

class TimelineNodeData {
  final DateTime? timestamp;
  final String? timeLabel;
  final String title;
  final String? description;
  final ReportTone tone;

  const TimelineNodeData({
    this.timestamp,
    this.timeLabel,
    required this.title,
    this.description,
    this.tone = ReportTone.info,
  });
}

enum DataTableCellAlignment {
  left,
  center,
  right,
}

class DataTableColumn {
  final String header;
  final DataTableCellAlignment alignment;
  final bool isMonospace;
  final double flex;

  const DataTableColumn({
    required this.header,
    this.alignment = DataTableCellAlignment.left,
    this.isMonospace = false,
    this.flex = 1.0,
  });
}

class DataTableRow {
  final List<String> cells;

  const DataTableRow({
    required this.cells,
  });
}

class DataTableData {
  final List<DataTableColumn> columns;
  final List<DataTableRow> rows;

  const DataTableData({
    required this.columns,
    required this.rows,
  });
}

class EvidenceItemData {
  final ReportImageSlot image;
  final String caption;
  final String? timestamp;
  final String? metadata;

  const EvidenceItemData({
    required this.image,
    required this.caption,
    this.timestamp,
    this.metadata,
  });
}

class AttachmentItemData {
  final String fileName;
  final String? fileType;
  final String? fileSize;
  final String? hash;

  const AttachmentItemData({
    required this.fileName,
    this.fileType,
    this.fileSize,
    this.hash,
  });
}

class ObservationBlockData {
  final String text;
  final String title;

  const ObservationBlockData({
    required this.text,
    this.title = 'Observações',
  });
}

class SignatureData {
  final String name;
  final String role;
  final String? identifier;

  const SignatureData({
    required this.name,
    required this.role,
    this.identifier,
  });
}

class AuditData {
  final String verificationUrl;
  final String hash;
  final String algorithm;
  final String? documentId;
  final String? trackingCode;
  final String? description;

  const AuditData({
    required this.verificationUrl,
    required this.hash,
    this.algorithm = 'SHA-256',
    this.documentId,
    this.trackingCode,
    this.description,
  });
}

// ---------------------------------------------------------------------------
// Extensões Visuais K9 Ops V2 (Gráfico e Tabelas Ricas)
// ---------------------------------------------------------------------------

class WeightChartPoint {
  final DateTime date;
  final double weight;
  final String? label;

  const WeightChartPoint({
    required this.date,
    required this.weight,
    this.label,
  });
}

class RichTableCell {
  final String text;
  final String? secondaryText;
  final ReportTone? badgeTone;
  final String? badgeText;
  final PdfColor? textColor;
  final bool isBold;
  final bool isMonospace;
  final DataTableCellAlignment? alignment;

  const RichTableCell({
    required this.text,
    this.secondaryText,
    this.badgeTone,
    this.badgeText,
    this.textColor,
    this.isBold = false,
    this.isMonospace = false,
    this.alignment,
  });

  const RichTableCell.text(
    this.text, {
    this.isBold = false,
    this.isMonospace = false,
    this.textColor,
    this.alignment,
  })  : secondaryText = null,
        badgeTone = null,
        badgeText = null;

  const RichTableCell.badge({
    required this.badgeText,
    required this.badgeTone,
    this.alignment,
  })  : text = badgeText ?? '',
        secondaryText = null,
        textColor = null,
        isBold = true,
        isMonospace = false;

  const RichTableCell.twoLine({
    required this.text,
    required this.secondaryText,
    this.isMonospace = false,
    this.alignment,
  })  : badgeTone = null,
        badgeText = null,
        textColor = null,
        isBold = true;
}

class RichDataTableRow {
  final List<RichTableCell> cells;
  final PdfColor? backgroundColor;

  const RichDataTableRow({
    required this.cells,
    this.backgroundColor,
  });
}

class RichDataTableData {
  final List<DataTableColumn> columns;
  final List<RichDataTableRow> rows;

  const RichDataTableData({
    required this.columns,
    required this.rows,
  });
}
