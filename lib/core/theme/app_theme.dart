import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

part 'app_theme_components.dart';
part 'app_theme_status.dart';
part 'app_theme_typography.dart';

class AppTheme {
  /// Azul petróleo profundo, base da identidade tática.
  static const Color _seed = Color(0xFF004D5A);
  static const Color amber = Color(0xFFFFB300);
  static const Color nightBlue = Color(0xFF0B1215);

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
        primary: const Color(0xFF00E5FF),
        onPrimary: Colors.black,
        secondary: const Color(0xFF4ECDE4),
        onSecondary: const Color(0xFF00363F),
        secondaryContainer: const Color(0xFF004E5B),
        onSecondaryContainer: const Color(0xFFB3EEFF),
        surface: const Color(0xFF0B1215),
        onSurface: const Color(0xFFDCE4E8),
        surfaceContainerHighest: const Color(0xFF1A2328),
        surfaceContainerHigh: const Color(0xFF141C20),
        outline: const Color(0xFF2C3B42),
        outlineVariant: const Color(0xFF1D2C33),
        error: const Color(0xFFEF5350),
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
