import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'app_theme_components.dart';
part 'app_theme_status.dart';
part 'app_theme_typography.dart';

class AppTheme {
  /// Azul petroleo profundo, base da identidade tatica.
  static const Color _seed = Color(0xFF004D5A);
  static const Color amber = Color(0xFFFFB300);
  static const Color nightBlue = Color(0xFF050D10);

  // --- Tokens semanticos do design system ---
  /// Background principal do app.
  static const Color background = Color(0xFF050D10);

  /// Ciano institucional - acoes primarias, links, FAB.
  static const Color primary = Color(0xFF4DD0E1);

  /// Verde - status operacional, confirmacoes.
  static const Color success = Color(0xFF2ECC71);

  /// Amarelo - atencao, pendencias, avisos.
  static const Color warning = Color(0xFFF1C40F);

  /// Laranja - nutricao, desenvolvimento, progresso.
  static const Color attention = Color(0xFFE67E22);

  /// Vermelho - critico, saude, erros.
  static const Color error = Color(0xFFE74C3C);

  /// Cinza escuro para bordas e divisores.
  static const Color outline = Color(0xFF2C3B42);

  /// Texto principal (branco).
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Texto secundario (cinza claro).
  static const Color textSecondary = Color(0xFFB0C4CC);

  /// Texto terciario (cinza escuro).
  static const Color textTertiary = Color(0xFF7A8A92);

  /// Texto auxiliar em controles densos e metadados.
  static const Color textMuted = Color(0xFF5A7280);

  /// Texto auxiliar claro para empty states sobre fundo escuro.
  static const Color textSoft = Color(0xFFA7B4BA);

  /// Superficies operacionais escuras usadas em cards e headers.
  static const Color surfacePanel = Color(0xFF0E1A1F);
  static const Color surfacePanelSoft = Color(0xFF0A1418);
  static const Color surfacePanelStrong = Color(0xFF06141A);
  static const Color surfacePanelAlt = Color(0xFF1A2A30);
  static const Color surfaceNavigation = Color(0xFF07141B);

  /// Variantes translúcidas do ciano institucional.
  static const Color primaryOverlay = Color(0x0A4DD0E1);
  static const Color primaryDivider = Color(0x1F4DD0E1);
  static const Color primaryChipBackground = Color(0x144DD0E1);
  static const Color primaryChipBorder = Color(0x334DD0E1);

  /// Divisores translúcidos sobre superfície escura.
  static const Color surfaceWhiteOverlay = Color(0x0DFFFFFF);
  static const Color surfaceWhiteBorder = Color(0x14FFFFFF);

  // --- Status de cao (legado mantido) ---
  static const Color statusActive = Color(0xFF1B8A4C);
  static const Color statusLeave = Color(0xFFC89200);
  static const Color statusRetired = Color(0xFF1A6A9A);
  static const Color statusAlert = Color(0xFFC0392B);
  static const Color statusTraining = Color(0xFF0097A7);
  static const Color statusVet = Color(0xFF7B1FA2);

  /// Alias de compatibilidade com telas antigas.
  static const Color tacticalYellow = amber;

  static ColorScheme get _colorScheme =>
      ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.black,
        secondary: AppTheme.primary,
        onSecondary: const Color(0xFF00363F),
        secondaryContainer: const Color(0xFF004E5B),
        onSecondaryContainer: const Color(0xFFB3EEFF),
        surface: background,
        onSurface: textPrimary,
        surfaceContainerHighest: const Color(0xFF1A2328),
        surfaceContainerHigh: const Color(0xFF141C20),
        outline: const Color(0xFF2C3B42),
        outlineVariant: const Color(0xFF1D2C33),
        error: error,
        onError: Colors.white,
        tertiary: const Color(0xFF80CBC4),
        onTertiary: const Color(0xFF00201D),
      );

  static ThemeData get darkTheme {
    final cs = _colorScheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme: _buildAppTextTheme(cs),
      appBarTheme: _buildAppBarTheme(cs),
      navigationBarTheme: _buildNavigationBarTheme(cs),
      cardTheme: _buildCardTheme(cs),
      elevatedButtonTheme: _buildElevatedButtonTheme(cs),
      filledButtonTheme: _buildFilledButtonTheme(),
      outlinedButtonTheme: _buildOutlinedButtonTheme(cs),
      floatingActionButtonTheme: _buildFloatingActionButtonTheme(cs),
      inputDecorationTheme: _buildInputDecorationTheme(cs),
      chipTheme: _buildChipTheme(cs),
      dividerTheme: _buildDividerTheme(cs),
      listTileTheme: _buildListTileTheme(cs),
    );
  }

  static Color statusColor(String status) => _statusColor(status);

  static Color statusBg(String status) => _statusBg(status);

  static String statusLabel(String status) => _statusLabel(status);

  static IconData statusIcon(String status) => _statusIcon(status);

  static LinearGradient statusGradient(String status) =>
      _statusGradient(status);
}
