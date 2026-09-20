import 'package:flutter/material.dart';

abstract final class CampusColors {
  static const background = Color(0xFFF6F8FC);
  static const primary = Color(0xFF4F46E5);
  static const ink = Color(0xFF202B46);
  static const muted = Color(0xFF68748C);
  static const line = Color(0xFFE8EDF5);
  static const mint = Color(0xFFE0F6ED);
}

class CoursePalette {
  final Color background, ink, accent;
  const CoursePalette(this.background, this.ink, this.accent);
  static const values = [
    CoursePalette(Color(0xFFECE7FF), Color(0xFF514084), Color(0xFF9280DB)),
    CoursePalette(Color(0xFFDEF5EA), Color(0xFF176348), Color(0xFF5FB99B)),
    CoursePalette(Color(0xFFFFE8DF), Color(0xFF913E29), Color(0xFFE8A185)),
    CoursePalette(Color(0xFFFFF2CD), Color(0xFF745000), Color(0xFFD8B15A)),
    CoursePalette(Color(0xFFE4EEFF), Color(0xFF254A91), Color(0xFF7FA5E4)),
  ];
  static CoursePalette forTitle(String title) =>
      values[title.runes.fold<int>(0, (sum, r) => sum + r) % values.length];
}

ThemeData campusTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: CampusColors.primary).copyWith(
    primary: CampusColors.primary,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: CampusColors.ink,
    onSurfaceVariant: CampusColors.muted,
    outlineVariant: CampusColors.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CampusColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: CampusColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        color: CampusColors.ink,
      ),
      iconTheme: IconThemeData(color: CampusColors.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: CampusColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      labelStyle: const TextStyle(color: CampusColors.muted, fontSize: 14),
      helperStyle: const TextStyle(color: CampusColors.muted, fontSize: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CampusColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CampusColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: CampusColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Color(0xFFD8DFF0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: CampusColors.primary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      height: 74,
      indicatorColor: const Color(0xFFEEEBFF),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 13,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? CampusColors.primary
              : CampusColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 25,
          color: states.contains(WidgetState.selected)
              ? CampusColors.primary
              : CampusColors.muted,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CampusColors.background,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: CampusColors.line,
      thickness: 1,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        fontSize: 15,
        height: 1.45,
        color: CampusColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: CampusColors.ink),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w800,
        color: CampusColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w700,
        color: CampusColors.ink,
      ),
    ),
  );
}
