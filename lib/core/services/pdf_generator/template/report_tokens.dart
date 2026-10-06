import 'package:pdf/pdf.dart';

/// Tokens visuais canônicos do K9 Ops Report Design System V1.
///
/// Imutáveis, compartilhados e independentes de domínio específico.
class ReportColors {
  ReportColors._();

  static final surface = PdfColor.fromHex('FFFFFF');
  static final surfaceSubtle = PdfColor.fromHex('F8FAFC');
  static final textPrimary = PdfColor.fromHex('0F172A');
  static final textSecondary = PdfColor.fromHex('334155');
  static final textMuted = PdfColor.fromHex('64748B');
  static final borderSoft = PdfColor.fromHex('E2E8F0');
  static final borderStrong = PdfColor.fromHex('94A3B8');
  static final accent = PdfColor.fromHex('0A8E9D');

  // Auxiliares neutros
  static final white = surface;
  static final black = PdfColor.fromHex('000000');
}

/// 6 tons genéricos de status do Design System V1.
///
/// REQUISITO ESTRITO: As primitivas NUNCA devem conhecer enums de domínio
/// (ex: OPERACIONAL, INAPTO, etc.). Apenas estes 6 tons genéricos.
enum ReportTone {
  positive,
  attention,
  critical,
  neutral,
  info,
  unknown,
}

/// Especificação de cores para cada tom de status.
class ReportToneColors {
  final PdfColor background;
  final PdfColor border;
  final PdfColor text;
  final PdfColor accent;

  const ReportToneColors({
    required this.background,
    required this.border,
    required this.text,
    required this.accent,
  });

  static ReportToneColors of(ReportTone tone) {
    switch (tone) {
      case ReportTone.positive:
        return ReportToneColors(
          background: PdfColor.fromHex('F0FDF4'),
          border: PdfColor.fromHex('BBF7D0'),
          text: PdfColor.fromHex('166534'),
          accent: PdfColor.fromHex('22C55E'),
        );
      case ReportTone.attention:
        return ReportToneColors(
          background: PdfColor.fromHex('FFFBEB'),
          border: PdfColor.fromHex('FDE68A'),
          text: PdfColor.fromHex('92400E'),
          accent: PdfColor.fromHex('F59E0B'),
        );
      case ReportTone.critical:
        return ReportToneColors(
          background: PdfColor.fromHex('FEF2F2'),
          border: PdfColor.fromHex('FECACA'),
          text: PdfColor.fromHex('991B1B'),
          accent: PdfColor.fromHex('EF4444'),
        );
      case ReportTone.neutral:
        return ReportToneColors(
          background: PdfColor.fromHex('F1F5F9'),
          border: PdfColor.fromHex('CBD5E1'),
          text: PdfColor.fromHex('475569'),
          accent: PdfColor.fromHex('64748B'),
        );
      case ReportTone.info:
        return ReportToneColors(
          background: PdfColor.fromHex('F0F9FF'),
          border: PdfColor.fromHex('BAE6FD'),
          text: PdfColor.fromHex('075985'),
          accent: PdfColor.fromHex('0284C7'),
        );
      case ReportTone.unknown:
        return ReportToneColors(
          background: PdfColor.fromHex('F8FAFC'),
          border: PdfColor.fromHex('E2E8F0'),
          text: PdfColor.fromHex('64748B'),
          accent: PdfColor.fromHex('94A3B8'),
        );
    }
  }
}

/// Escala de espaçamento em pontos (pt).
class ReportSpacing {
  ReportSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
}

/// Métricas de página e slots segundo as diretrizes de impressão A4.
class ReportPageMetrics {
  ReportPageMetrics._();

  // A4 Portrait: 210 x 297 mm
  static const double portraitWidthMm = 210.0;
  static const double portraitHeightMm = 297.0;
  static const double portraitMarginLeftMm = 15.0;
  static const double portraitMarginTopMm = 12.0;
  static const double portraitMarginRightMm = 12.0;
  static const double portraitMarginBottomMm = 12.0;

  // A4 Landscape: 297 x 210 mm
  static const double landscapeWidthMm = 297.0;
  static const double landscapeHeightMm = 210.0;
  static const double landscapeMarginMm = 12.0;

  // Slots de branding
  static const double productMarkMaxWidthMm = 28.0;
  static const double productMarkMaxHeightMm = 12.0;
  static const double productMarkSafeAreaMm = 2.0;

  static const double issuerMarkMaxWidthMm = 18.0;
  static const double issuerMarkMaxHeightMm = 18.0;
  static const double issuerMarkSafeAreaMm = 2.0;

  static PdfPageFormat get portraitFormat => PdfPageFormat(
    portraitWidthMm * PdfPageFormat.mm,
    portraitHeightMm * PdfPageFormat.mm,
    marginLeft: portraitMarginLeftMm * PdfPageFormat.mm,
    marginTop: portraitMarginTopMm * PdfPageFormat.mm,
    marginRight: portraitMarginRightMm * PdfPageFormat.mm,
    marginBottom: portraitMarginBottomMm * PdfPageFormat.mm,
  );

  static PdfPageFormat get landscapeFormat => PdfPageFormat(
    landscapeWidthMm * PdfPageFormat.mm,
    landscapeHeightMm * PdfPageFormat.mm,
    marginLeft: landscapeMarginMm * PdfPageFormat.mm,
    marginTop: landscapeMarginMm * PdfPageFormat.mm,
    marginRight: landscapeMarginMm * PdfPageFormat.mm,
    marginBottom: landscapeMarginMm * PdfPageFormat.mm,
  );
}
