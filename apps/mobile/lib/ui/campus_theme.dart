import 'package:flutter/material.dart';
import 'v2/shiri_theme.dart';
import 'v2/shiri_tokens.dart' as v2;

/// Compatibility names for the v2 token palette.
abstract final class CampusColors {
  static const background = Color(0xFFF3F7FC);
  static const surface = Color(0xFFFFFFFF);
  static const primary = Color(0xFF2E6FE0);
  static const teal = Color(0xFF0F7F63);
  static const blueSoft = Color(0xFFEAF2FF);
  static const tealSoft = Color(0xFFE3F6EE);
  static const ink = Color(0xFF142238);
  static const muted = Color(0xFF5B6B82);
  static const line = Color(0xFFE4ECF5);
  static const mint = Color(0xFFE3F6EE);
  static const warning = Color(0xFF96620A);
  static const warningSoft = Color(0xFFFFF4D6);
  static const error = Color(0xFFC2412D);
  static const errorSoft = Color(0xFFFDECE8);
  static const success = Color(0xFF0F7F63);
  static const chartPurple = Color(0xFF5B6B82);
  static const chartSand = Color(0xFF96620A);
  static const timeFuture = Color(0xFF2E6FE0);
  static const timeSoon = Color(0xFF96620A);
  static const timeUrgent = Color(0xFFC2412D);
  static const timeNow = Color(0xFF96620A);
  static const timePast = Color(0xFF8291A7);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const surfaceOverlay = Color(0xFFF3F7FC);
  static List<BoxShadow> elevation(int level, {Color? color}) =>
      level <= 1 ? v2.ShiriShadows.light.card : v2.ShiriShadows.light.raised;
}

class CoursePalette {
  final Color background, ink, accent;
  const CoursePalette(this.background, this.ink, this.accent);
  Color get foreground => ink;
  static const values = [
    CoursePalette(Color(0xFFE8F2FF), Color(0xFF1D5BB5), Color(0xFF4A90F0)),
    CoursePalette(Color(0xFFE4F6EF), Color(0xFF0F7656), Color(0xFF3DBE8B)),
    CoursePalette(Color(0xFFE3F6FA), Color(0xFF0E6F85), Color(0xFF33B5CF)),
    CoursePalette(Color(0xFFEFECFF), Color(0xFF5443BE), Color(0xFF8C7BF0)),
    CoursePalette(Color(0xFFFFF0E6), Color(0xFFA9501F), Color(0xFFF39A62)),
    CoursePalette(Color(0xFFFDECF2), Color(0xFFA83A61), Color(0xFFE7779D)),
    CoursePalette(Color(0xFFFFF6DD), Color(0xFF8A6100), Color(0xFFE5B23C)),
    CoursePalette(Color(0xFFEDF1F6), Color(0xFF44566E), Color(0xFF8193AB)),
  ];
  static CoursePalette forTitle(String title) {
    final p = v2.CoursePalette.forTitle(title);
    return CoursePalette(p.background, p.foreground, p.accent);
  }
}

ThemeData campusTheme() => shiriLightTheme();

/// Stronger campus light tokens; leaves text scaling to MediaQuery.
ThemeData campusHighContrastTheme({ThemeData? base}) {
  final theme = base ?? campusTheme();
  const ink = Color(0xFF142238);
  const muted = Color(0xFF384B63);
  const primary = Color(0xFF244B9F);
  const outline = Color(0xFF68788B);
  final scheme = theme.colorScheme.copyWith(
    primary: primary,
    onPrimary: Colors.white,
    secondary: const Color(0xFF205D4E),
    onSecondary: Colors.white,
    onPrimaryContainer: primary,
    onSecondaryContainer: const Color(0xFF205D4E),
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: outline,
    error: const Color(0xFF8D2927),
    onErrorContainer: const Color(0xFF8D2927),
  );
  return theme.copyWith(
    colorScheme: scheme,
    textTheme: theme.textTheme.apply(bodyColor: ink, displayColor: ink),
    appBarTheme: theme.appBarTheme.copyWith(
      foregroundColor: ink,
      iconTheme: const IconThemeData(color: ink),
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(color: ink),
    ),
    cardTheme: theme.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: outline, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: outline, thickness: 1.5),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle: theme.inputDecorationTheme.labelStyle?.copyWith(color: muted),
      helperStyle: theme.inputDecorationTheme.helperStyle?.copyWith(
        color: muted,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: outline, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: primary,
        side: const BorderSide(color: outline, width: 1.5),
      ),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      iconColor: muted,
      titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(color: ink),
      subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
        color: muted,
      ),
    ),
  );
}
