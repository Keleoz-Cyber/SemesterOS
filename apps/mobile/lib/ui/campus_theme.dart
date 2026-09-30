import 'package:flutter/material.dart';

abstract final class CampusColors {
  static const background = Color(0xFFF5F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF3D66C1);
  static const teal = Color(0xFF34766F);
  static const blueSoft = Color(0xFFEEF3FC);
  static const tealSoft = Color(0xFFEDF5F2);
  static const ink = Color(0xFF24344D);
  static const muted = Color(0xFF5F6F84);
  static const line = Color(0xFFE3E9F1);
  static const mint = tealSoft;
  static const warning = Color(0xFF866A37);
  static const warningSoft = Color(0xFFFAF6EC);
  static const error = Color(0xFFA35350);
  static const errorSoft = Color(0xFFFBF1F0);
  static const success = Color(0xFF397363);
  static const chartPurple = Color(0xFF8A789F);
  static const chartSand = Color(0xFFA28A60);
}

class CoursePalette {
  final Color background, ink, accent;
  const CoursePalette(this.background, this.ink, this.accent);
  static const values = [
    CoursePalette(Color(0xFFE9F0FB), Color(0xFF365981), Color(0xFF6A8AB8)),
    CoursePalette(Color(0xFFE9F3F0), Color(0xFF396E61), Color(0xFF70A594)),
    CoursePalette(Color(0xFFF1EFF8), Color(0xFF635682), Color(0xFF9A8BB8)),
    CoursePalette(Color(0xFFF6F0E6), Color(0xFF7F6949), Color(0xFFB49A6C)),
    CoursePalette(Color(0xFFEAF2F5), Color(0xFF3F6878), Color(0xFF79A0B1)),
  ];
  static CoursePalette forTitle(String title) =>
      values[title.runes.fold<int>(0, (sum, r) => sum + r) % values.length];
}

ThemeData campusTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: CampusColors.primary).copyWith(
    primary: CampusColors.primary,
    secondary: CampusColors.teal,
    primaryContainer: CampusColors.blueSoft,
    onPrimaryContainer: CampusColors.primary,
    secondaryContainer: CampusColors.tealSoft,
    onSecondaryContainer: CampusColors.teal,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: CampusColors.ink,
    onSurfaceVariant: CampusColors.muted,
    surfaceContainerHighest: CampusColors.blueSoft,
    outlineVariant: CampusColors.line,
    error: CampusColors.error,
    errorContainer: CampusColors.errorSoft,
    onError: Colors.white,
    onErrorContainer: CampusColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CampusColors.background,
    datePickerTheme: DatePickerThemeData(
      backgroundColor: CampusColors.surface,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: CampusColors.primary,
      headerForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: CampusColors.surface,
      dialBackgroundColor: CampusColors.blueSoft,
      dialHandColor: CampusColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: CampusColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: CampusColors.ink,
      ),
      iconTheme: IconThemeData(color: CampusColors.ink),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: CampusColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: CampusColors.muted, fontSize: 14),
      helperStyle: const TextStyle(color: CampusColors.muted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CampusColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CampusColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
      indicatorColor: CampusColors.blueSoft,
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
    chipTheme: ChipThemeData(
      backgroundColor: CampusColors.surface,
      selectedColor: CampusColors.blueSoft,
      secondarySelectedColor: CampusColors.tealSoft,
      side: const BorderSide(color: CampusColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: const TextStyle(fontSize: 13, color: CampusColors.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: CampusColors.muted,
      titleTextStyle: TextStyle(
        fontSize: 16,
        color: CampusColors.ink,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 14,
        color: CampusColors.muted,
        height: 1.4,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CampusColors.ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        fontSize: 16,
        height: 1.45,
        color: CampusColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: CampusColors.ink),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
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
