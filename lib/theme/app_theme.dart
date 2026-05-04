import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Seed & Palette ─────────────────────────────────────────────────────────
  /// Azul petróleo profundo — identidade tática
  static const Color _seed       = Color(0xFF004D5A);
  static const Color amber       = Color(0xFFFFB300); // accent KPI / highlights
  static const Color nightBlue   = Color(0xFF0B1215); // alias compat

  // ── Status operacional (3 níveis) ──────────────────────────────────────────
  static const Color statusActive   = Color(0xFF1B8A4C); // verde — pronto
  static const Color statusLeave    = Color(0xFFC89200); // amarelo — reciclagem
  static const Color statusRetired  = Color(0xFF1A6A9A); // azul — aposentado
  static const Color statusAlert    = Color(0xFFC0392B); // vermelho — baixa/médica
  static const Color statusTraining = Color(0xFF0097A7); // ciano — em treino
  static const Color statusVet      = Color(0xFF7B1FA2); // roxo — veterinário

  /// Backward-compat alias
  static const Color tacticalYellow = amber;

  // ── Color Scheme (M3 tonal — petroleum seed) ──────────────────────────────
  static ColorScheme get _colorScheme => ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  ).copyWith(
    // Brand accent alterado para Ciano Neon
    primary:           const Color(0xFF00E5FF),
    onPrimary:         Colors.black,
    // Secondary → teal petróleo (do seed)
    secondary:         const Color(0xFF4ECDE4),
    onSecondary:       const Color(0xFF00363F),
    secondaryContainer: const Color(0xFF004E5B),
    onSecondaryContainer: const Color(0xFFB3EEFF),
    // Surfaces — preto azulado profundo
    surface:           const Color(0xFF0B1215),
    onSurface:         const Color(0xFFDCE4E8),
    surfaceContainerHighest: const Color(0xFF1A2328),
    surfaceContainerHigh:    const Color(0xFF141C20),
    // Outlines — cinza azulado
    outline:           const Color(0xFF2C3B42),
    outlineVariant:    const Color(0xFF1D2C33),
    // Error
    error:             const Color(0xFFEF5350),
    onError:           Colors.white,
    tertiary:          const Color(0xFF80CBC4),
    onTertiary:        const Color(0xFF00201D),
  );

  // ── Typography (Poppins) ──────────────────────────────────────────────────
  static TextTheme _buildTextTheme(ColorScheme cs) =>
    GoogleFonts.poppinsTextTheme(
      TextTheme(
        displayLarge:   TextStyle(fontSize: 57, fontWeight: FontWeight.w700, color: cs.onSurface),
        displayMedium:  TextStyle(fontSize: 45, fontWeight: FontWeight.w700, color: cs.onSurface),
        headlineLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: cs.onSurface),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: cs.onSurface),
        headlineSmall:  TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleLarge:     TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: cs.onSurface),
        titleMedium:    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: cs.onSurface, letterSpacing: 0.15),
        titleSmall:     TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cs.onSurface, letterSpacing: 0.1),
        bodyLarge:      TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: cs.onSurface),
        bodyMedium:     TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant),
        bodySmall:      TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant),
        labelLarge:     TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface, letterSpacing: 0.1),
        labelMedium:    TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface, letterSpacing: 0.5),
        labelSmall:     TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: cs.onSurface, letterSpacing: 0.5),
      ),
    );

  // ── Main Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    final cs = _colorScheme;
    return ThemeData(
      useMaterial3:            true,
      brightness:              Brightness.dark,
      colorScheme:             cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme:               _buildTextTheme(cs),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor:         cs.surface,
        foregroundColor:         cs.onSurface,
        elevation:               0,
        scrolledUnderElevation:  2,
        centerTitle:             true,
        surfaceTintColor:        cs.secondary,
        titleTextStyle:          GoogleFonts.poppins(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: cs.onSurface, letterSpacing: 0.15,
        ),
      ),

      // NavigationBar (M3 bottom nav)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:  cs.surfaceContainerHighest,
        indicatorColor:   cs.secondaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.onSecondaryContainer, size: 24);
          }
          return IconThemeData(color: cs.onSurfaceVariant, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final base = GoogleFonts.poppins(fontSize: 12, letterSpacing: 0.5);
          if (states.contains(WidgetState.selected)) {
            return base.copyWith(fontWeight: FontWeight.w700, color: cs.onSecondaryContainer);
          }
          return base.copyWith(fontWeight: FontWeight.w500, color: cs.onSurfaceVariant);
        }),
        height:    72,
        elevation: 3,
      ),

      // Cards — M3 outlined, elevation 0
      cardTheme: CardThemeData(
        color:     cs.surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: cs.outlineVariant, width: 0.8),
        ),
        margin: EdgeInsets.zero,
      ),

      // ElevatedButton → filled tonal (secondary container)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize:     const Size.fromHeight(56),
          shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle:       GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
          elevation:       0,
        ),
      ),

      // FilledButton → standard ciano accent (CTA primário)
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF),
          foregroundColor: Colors.black,
          minimumSize:     const Size.fromHeight(56),
          shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle:       GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side:            BorderSide(color: cs.outline, width: 1),
          minimumSize:     const Size.fromHeight(56),
          shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle:       GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        elevation:       3,
        shape:           const CircleBorder(),
      ),

      // Input fields — M3 outlined style
      inputDecorationTheme: InputDecorationTheme(
        filled:          false,
        labelStyle:      TextStyle(color: cs.onSurfaceVariant, fontSize: 12, letterSpacing: 1.0),
        hintStyle:       TextStyle(color: cs.onSurfaceVariant.withAlpha(153)),
        prefixIconColor: cs.secondary,
        contentPadding:  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:   BorderSide(color: cs.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:   const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:   const BorderSide(color: Color(0xFF00E5FF), width: 1),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:   BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide:   BorderSide(color: cs.error, width: 1),
        ),
      ),

      // Chips
      chipTheme: ChipThemeData(
        backgroundColor:  cs.surfaceContainerHighest,
        selectedColor:    cs.secondaryContainer,
        checkmarkColor:   cs.onSecondaryContainer,
        labelStyle:       GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
        side:             BorderSide(color: cs.outlineVariant),
        shape:            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding:          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color:     cs.outlineVariant,
        thickness: 1,
        space:     1,
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        tileColor:         Colors.transparent,
        iconColor:         cs.secondary,
        textColor:         cs.onSurface,
        subtitleTextStyle: GoogleFonts.poppins(fontSize: 13, color: cs.onSurfaceVariant),
        contentPadding:    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape:             RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Color statusColor(String status) {
    switch (status) {
      case 'Ativo':       return statusActive;
      case 'Em Treino':   return statusTraining;
      case 'Licença':     return statusLeave;
      case 'Aposentado':  return statusRetired;
      case 'Veterinário': return statusVet;
      case 'Baixa':       return statusAlert;
      default:            return const Color(0xFF546E7A);
    }
  }

  static Color statusBg(String status) {
    switch (status) {
      case 'Ativo':       return const Color(0xFF0A1E12);
      case 'Em Treino':   return const Color(0xFF00151A);
      case 'Licença':     return const Color(0xFF1A1400);
      case 'Aposentado':  return const Color(0xFF05111A);
      case 'Veterinário': return const Color(0xFF12001E);
      case 'Baixa':       return const Color(0xFF1E0505);
      default:            return const Color(0xFF0B1215);
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'Ativo':       return 'ATIVO';
      case 'Em Treino':   return 'EM TREINO';
      case 'Licença':     return 'LICENÇA';
      case 'Aposentado':  return 'APOSENTADO';
      case 'Veterinário': return 'VETERINÁRIO';
      case 'Baixa':       return 'BAIXA MÉD.';
      default:            return status.toUpperCase();
    }
  }

  static IconData statusIcon(String status) {
    switch (status) {
      case 'Ativo':       return Icons.check_circle_rounded;
      case 'Em Treino':   return Icons.fitness_center_rounded;
      case 'Licença':     return Icons.pause_circle_rounded;
      case 'Aposentado':  return Icons.archive_rounded;
      case 'Veterinário': return Icons.medical_services_rounded;
      case 'Baixa':       return Icons.personal_injury_rounded;
      default:            return Icons.help_outline_rounded;
    }
  }

  static LinearGradient statusGradient(String status) {
    switch (status) {
      case 'Ativo':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E3A), Color(0xFF0A3320)],
        );
      case 'Em Treino':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF004D5A), Color(0xFF002830)],
        );
      case 'Licença':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF7A5800), Color(0xFF3D2C00)],
        );
      case 'Aposentado':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0D3B5C), Color(0xFF051D30)],
        );
      case 'Veterinário':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF4A0072), Color(0xFF230036)],
        );
      case 'Baixa':
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF7A1A1A), Color(0xFF3D0000)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1A2328), Color(0xFF0B1215)],
        );
    }
  }
}
