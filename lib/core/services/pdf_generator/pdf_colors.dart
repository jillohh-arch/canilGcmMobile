import 'package:pdf/pdf.dart';

/// Paleta institucional light mode para PDFs formais.
class PdfInstitutionalColors {
  PdfInstitutionalColors._();

  // Fundo e textos.
  static final background = PdfColor.fromHex('FFFFFF');
  static final white = background;
  static final black = PdfColor.fromHex('000000');
  static final textPrimary = PdfColor.fromHex('1A1A1A');
  static final textSecondary = PdfColor.fromHex('4A5560');
  static final textTertiary = PdfColor.fromHex('6C7A83');
  static final textInk = PdfColor.fromHex('14202B');
  static final textMuted = PdfColor.fromHex('46586A');
  static final textFaint = PdfColor.fromHex('8493A1');
  static final textPlaceholder = PdfColor.fromHex('8AA0AD');
  static final textSubtle = PdfColor.fromHex('97A6B2');

  // Cores de identidade por tipo de documento.
  static final cyan = PdfColor.fromHex('0A8E9D');
  static final cyanDeep = PdfColor.fromHex('07707C');
  static final cyanAccent = PdfColor.fromHex('4DD0E1');
  static final blue = PdfColor.fromHex('2C6E91');
  static final orange = PdfColor.fromHex('C25E1F');
  static final purple = PdfColor.fromHex('5A4080');

  // Status e alertas.
  static final greenInstitutional = PdfColor.fromHex('2A9D52');
  static final green = PdfColor.fromHex('1F9D52');
  static final greenBright = PdfColor.fromHex('2ECC71');
  static final amberWarning = PdfColor.fromHex('B88A0C');
  static final amber = PdfColor.fromHex('B07D0A');
  static final redAlert = PdfColor.fromHex('C0392B');

  // Superficies.
  static final lightGray = PdfColor.fromHex('F8FAFB');
  static final divider = PdfColor.fromHex('D8E0E5');
  static final cardBorder = PdfColor.fromHex('E8EEF1');
  static final dividerStrong = PdfColor.fromHex('DDE4EA');
  static final dividerSoft = PdfColor.fromHex('EAEFF3');
  static final neutralBorder = PdfColor.fromHex('E0E0E0');
  static final greenBackground = PdfColor.fromHex('F1FAF4');
  static final greenBorder = PdfColor.fromHex('BFE6CF');
  static final amberBackground = PdfColor.fromHex('FDF8EC');
  static final amberBorder = PdfColor.fromHex('ECDCA8');
  static final amberSoft = PdfColor.fromHex('FFF8E1');
  static final amberStrong = PdfColor.fromHex('FFA000');
  static final amberDeep = PdfColor.fromHex('FF6F00');
  static final headerBackground = PdfColor.fromHex('0E1A24');
  static final headerAccent = PdfColor.fromHex('2BB6C4');
  static final headerDeep = PdfColor.fromHex('13242F');
  static final timelineDark = PdfColor.fromHex('26313C');
  static final mapBackground = PdfColor.fromHex('F3F6F8');
  static final mediaBackground = PdfColor.fromHex('D5E0E6');
  static final panelLight = PdfColor.fromHex('EEF2F5');
  static final panelCyan = PdfColor.fromHex('EEF9FB');
  static final panelCyanBorder = PdfColor.fromHex('B8E3E8');
  static final panelSubtle = PdfColor.fromHex('F7F9FB');
  static final panelSoft = PdfColor.fromHex('FAFCFD');
  static final panelMuted = PdfColor.fromHex('F6F8FA');
  static final panelNeutral = PdfColor.fromHex('F9F9F9');
  static final panelNeutralAlt = PdfColor.fromHex('F5F5F5');
  static final historyBackground = PdfColor.fromHex('F6F2FA');
  static final darkSurface = PdfColor.fromHex('0A1A20');
  static final darkSurfaceDeep = PdfColor.fromHex('04181D');
  static final cyanOverlay = PdfColor.fromInt(0x330A8E9D);

  // Escala neutra equivalente aos tons usados pelos PDFs legados.
  static final grey50 = PdfColor.fromHex('FAFAFA');
  static final grey100 = PdfColor.fromHex('F5F5F5');
  static final grey300 = PdfColor.fromHex('E0E0E0');
  static final grey500 = PdfColor.fromHex('9E9E9E');
  static final grey600 = PdfColor.fromHex('757575');
  static final grey700 = PdfColor.fromHex('616161');
  static final grey800 = PdfColor.fromHex('424242');
  static final grey900 = PdfColor.fromHex('212121');
}
