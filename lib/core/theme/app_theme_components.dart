part of 'app_theme.dart';

AppBarTheme _buildAppBarTheme(ColorScheme cs) {
  return AppBarTheme(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    elevation: 0,
    scrolledUnderElevation: 2,
    centerTitle: true,
    surfaceTintColor: cs.secondary,
    titleTextStyle: GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
      letterSpacing: 0.15,
    ),
  );
}

NavigationBarThemeData _buildNavigationBarTheme(ColorScheme cs) {
  return NavigationBarThemeData(
    backgroundColor: cs.surfaceContainerHighest,
    indicatorColor: cs.secondaryContainer,
    iconTheme: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return IconThemeData(color: cs.onSecondaryContainer, size: 24);
      }
      return IconThemeData(color: cs.onSurfaceVariant, size: 24);
    }),
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final base = GoogleFonts.poppins(fontSize: 12, letterSpacing: 0.5);
      if (states.contains(WidgetState.selected)) {
        return base.copyWith(
          fontWeight: FontWeight.w700,
          color: cs.onSecondaryContainer,
        );
      }
      return base.copyWith(
        fontWeight: FontWeight.w500,
        color: cs.onSurfaceVariant,
      );
    }),
    height: 72,
    elevation: 3,
  );
}

CardThemeData _buildCardTheme(ColorScheme cs) {
  return CardThemeData(
    color: cs.surfaceContainerHighest,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: cs.outlineVariant, width: 0.8),
    ),
    margin: EdgeInsets.zero,
  );
}

ElevatedButtonThemeData _buildElevatedButtonTheme(ColorScheme cs) {
  return ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      elevation: 0,
    ),
  );
}

FilledButtonThemeData _buildFilledButtonTheme() {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF00E5FF),
      foregroundColor: Colors.black,
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700),
    ),
  );
}

OutlinedButtonThemeData _buildOutlinedButtonTheme(ColorScheme cs) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: cs.onSurface,
      side: BorderSide(color: cs.outline, width: 1),
      minimumSize: const Size.fromHeight(56),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );
}

FloatingActionButtonThemeData _buildFloatingActionButtonTheme(ColorScheme cs) {
  return FloatingActionButtonThemeData(
    backgroundColor: cs.secondaryContainer,
    foregroundColor: cs.onSecondaryContainer,
    elevation: 3,
    shape: const CircleBorder(),
  );
}

InputDecorationTheme _buildInputDecorationTheme(ColorScheme cs) {
  return InputDecorationTheme(
    filled: false,
    labelStyle: TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 12,
      letterSpacing: 1.0,
    ),
    hintStyle: TextStyle(color: cs.onSurfaceVariant.withAlpha(153)),
    prefixIconColor: cs.secondary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: _inputBorder(cs.outline),
    enabledBorder: _inputBorder(const Color(0xFF2A2A2A)),
    focusedBorder: _inputBorder(const Color(0xFF00E5FF)),
    errorBorder: _inputBorder(cs.error),
    focusedErrorBorder: _inputBorder(cs.error),
  );
}

OutlineInputBorder _inputBorder(Color color) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: color, width: 1),
  );
}

ChipThemeData _buildChipTheme(ColorScheme cs) {
  return ChipThemeData(
    backgroundColor: cs.surfaceContainerHighest,
    selectedColor: cs.secondaryContainer,
    checkmarkColor: cs.onSecondaryContainer,
    labelStyle: GoogleFonts.poppins(fontSize: 13, color: cs.onSurface),
    side: BorderSide(color: cs.outlineVariant),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  );
}

DividerThemeData _buildDividerTheme(ColorScheme cs) {
  return DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1);
}

ListTileThemeData _buildListTileTheme(ColorScheme cs) {
  return ListTileThemeData(
    tileColor: Colors.transparent,
    iconColor: cs.secondary,
    textColor: cs.onSurface,
    subtitleTextStyle: GoogleFonts.poppins(
      fontSize: 13,
      color: cs.onSurfaceVariant,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
  );
}
