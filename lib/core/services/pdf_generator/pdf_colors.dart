import 'package:pdf/pdf.dart';

/// Paleta institucional light mode para PDFs formais.
/// Segue padrão definido em .claude/skills/pdf-generation/SKILL.md
class PdfInstitutionalColors {
  PdfInstitutionalColors._();

  // Fundo e textos
  static final background = PdfColor.fromHex('FFFFFF');
  static final textPrimary = PdfColor.fromHex('1A1A1A');
  static final textSecondary = PdfColor.fromHex('4A5560');
  static final textTertiary = PdfColor.fromHex('6C7A83');

  // Cor identidade por tipo de documento
  static final cyan = PdfColor.fromHex('0A8E9D'); // Ocorrência, Vacinação
  static final blue = PdfColor.fromHex('2C6E91'); // Peso
  static final orange = PdfColor.fromHex('C25E1F'); // Nutrição
  static final purple = PdfColor.fromHex('5A4080'); // Histórico

  // Auxiliares
  static final greenInstitutional = PdfColor.fromHex('2A9D52');
  static final amberWarning = PdfColor.fromHex('B88A0C');
  static final redAlert = PdfColor.fromHex('C0392B');

  // Superfícies
  static final lightGray = PdfColor.fromHex('F8FAFB');
  static final divider = PdfColor.fromHex('D8E0E5');
  static final cardBorder = PdfColor.fromHex('E8EEF1');
}
