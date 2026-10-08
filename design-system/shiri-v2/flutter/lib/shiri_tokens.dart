/// 「晴日」(shiri v2) design tokens.
///
/// Every value in this file comes from
/// `design-system/shiri-v2/tokens/tokens.json` (v2.0.0). The few values the
/// JSON does not define (dark glass border, dark shadows, dark kind/course
/// fills) are marked `Derived:` and computed from token colors, never invented
/// hues.
///
/// Access the brightness-dependent part through the theme:
///
/// ```dart
/// final shiri = context.shiri;          // ShiriTheme extension
/// Text('上午好', style: shiri.text.display);
/// DecoratedBox(decoration: shiri.cardDecoration());
/// ```
///
/// Brightness-independent values (spacing, radius, motion, layout, gradients)
/// are plain `static const` members so they can be used in const contexts.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

/// Semantic color roles (`tokens.color.light` / `tokens.color.dark`).
@immutable
class ShiriColors {
  const ShiriColors({
    required this.brightness,
    required this.bg,
    required this.bgTint,
    required this.surface,
    required this.surfaceSunken,
    required this.surfaceGlass,
    required this.surfaceGlassFallback,
    required this.glassBorder,
    required this.line,
    required this.lineStrong,
    required this.ink900,
    required this.ink700,
    required this.ink500,
    required this.ink400,
    required this.inkInverse,
    required this.primary,
    required this.primaryPressed,
    required this.primarySoft,
    required this.primarySoftStrong,
    required this.onPrimary,
    required this.success,
    required this.successSoft,
    required this.successAccent,
    required this.warning,
    required this.warningSoft,
    required this.warningAccent,
    required this.danger,
    required this.dangerSoft,
    required this.dangerAccent,
    required this.scrim,
    required this.focusRing,
  });

  final Brightness brightness;

  /// Page background.
  final Color bg;

  /// Tinted page band (e.g. behind grouped content).
  final Color bgTint;

  /// Cards, sheets, list surfaces.
  final Color surface;

  /// Inputs, tracks, recessed wells.
  final Color surfaceSunken;

  /// Translucent glass fill, used with a 20 sigma backdrop blur.
  final Color surfaceGlass;

  /// `material.glass.fallback`: glass without blur (low-end devices,
  /// high-contrast mode).
  final Color surfaceGlassFallback;

  /// `material.glass.border` (1dp).
  final Color glassBorder;

  /// Hairlines and dividers.
  final Color line;

  /// Stronger strokes (outlined buttons, dashed outlines).
  final Color lineStrong;

  /// Primary text.
  final Color ink900;

  /// Secondary text.
  final Color ink700;

  /// Tertiary text, icons, unchecked control borders (>= 4.5:1 on surface).
  final Color ink500;

  /// Placeholder / disabled / completed text. Decorative only, below 4.5:1.
  final Color ink400;

  /// Text on dark fills (night sky, inverse snackbars).
  final Color inkInverse;

  final Color primary;
  final Color primaryPressed;
  final Color primarySoft;
  final Color primarySoftStrong;
  final Color onPrimary;
  final Color success;
  final Color successSoft;
  final Color successAccent;
  final Color warning;
  final Color warningSoft;
  final Color warningAccent;
  final Color danger;
  final Color dangerSoft;
  final Color dangerAccent;

  /// Modal barrier color (already translucent).
  final Color scrim;

  /// Keyboard focus ring (already translucent).
  final Color focusRing;

  bool get isDark => brightness == Brightness.dark;

  /// `tokens.color.light`.
  static const ShiriColors light = ShiriColors(
    brightness: Brightness.light,
    bg: Color(0xFFF3F7FC),
    bgTint: Color(0xFFEAF3FD),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEF3F9),
    surfaceGlass: Color.fromRGBO(255, 255, 255, 0.74),
    surfaceGlassFallback: Color.fromRGBO(255, 255, 255, 0.94),
    glassBorder: Color.fromRGBO(255, 255, 255, 0.65),
    line: Color(0xFFE4ECF5),
    lineStrong: Color(0xFFD2DDEA),
    ink900: Color(0xFF142238),
    ink700: Color(0xFF33435C),
    ink500: Color(0xFF5B6B82),
    ink400: Color(0xFF8291A7),
    inkInverse: Color(0xFFFFFFFF),
    primary: Color(0xFF2E6FE0),
    primaryPressed: Color(0xFF2459BD),
    primarySoft: Color(0xFFEAF2FF),
    primarySoftStrong: Color(0xFFD7E7FF),
    onPrimary: Color(0xFFFFFFFF),
    success: Color(0xFF0F7F63),
    successSoft: Color(0xFFE3F6EE),
    successAccent: Color(0xFF3FBF8F),
    warning: Color(0xFF96620A),
    warningSoft: Color(0xFFFFF4D6),
    warningAccent: Color(0xFFF2B33D),
    danger: Color(0xFFC2412D),
    dangerSoft: Color(0xFFFDECE8),
    dangerAccent: Color(0xFFF0705A),
    scrim: Color.fromRGBO(20, 34, 56, 0.32),
    focusRing: Color.fromRGBO(46, 111, 224, 0.40),
  );

  /// `tokens.color.dark` (phase 2, same roles as light).
  static const ShiriColors dark = ShiriColors(
    brightness: Brightness.dark,
    bg: Color(0xFF0B1220),
    bgTint: Color(0xFF0F1A2E),
    surface: Color(0xFF121C2F),
    surfaceSunken: Color(0xFF0E1727),
    surfaceGlass: Color.fromRGBO(18, 28, 47, 0.72),
    // Derived: dark surface at the light fallback's 0.94 opacity.
    surfaceGlassFallback: Color.fromRGBO(18, 28, 47, 0.94),
    // Derived: a faint white rim reads as the same glass edge on dark.
    glassBorder: Color.fromRGBO(255, 255, 255, 0.10),
    line: Color(0xFF22304A),
    lineStrong: Color(0xFF2C3C5A),
    ink900: Color(0xFFEEF3FA),
    ink700: Color(0xFFC9D4E4),
    ink500: Color(0xFF9AA9BF),
    ink400: Color(0xFF74839A),
    inkInverse: Color(0xFF0B1220),
    primary: Color(0xFF6FA8FF),
    primaryPressed: Color(0xFF8AB8FF),
    primarySoft: Color(0xFF17284A),
    primarySoftStrong: Color(0xFF1F3560),
    onPrimary: Color(0xFF0B1220),
    success: Color(0xFF5ED1A6),
    successSoft: Color(0xFF12322A),
    successAccent: Color(0xFF3FBF8F),
    warning: Color(0xFFF2C96B),
    warningSoft: Color(0xFF33280F),
    warningAccent: Color(0xFFF2B33D),
    danger: Color(0xFFFF8E7A),
    dangerSoft: Color(0xFF3A1D19),
    dangerAccent: Color(0xFFF0705A),
    scrim: Color.fromRGBO(0, 0, 0, 0.48),
    focusRing: Color.fromRGBO(111, 168, 255, 0.45),
  );

  /// Linear interpolation, used by [ShiriTheme.lerp] when the theme animates.
  static ShiriColors lerp(ShiriColors a, ShiriColors b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return ShiriColors(
      brightness: t < 0.5 ? a.brightness : b.brightness,
      bg: c(a.bg, b.bg),
      bgTint: c(a.bgTint, b.bgTint),
      surface: c(a.surface, b.surface),
      surfaceSunken: c(a.surfaceSunken, b.surfaceSunken),
      surfaceGlass: c(a.surfaceGlass, b.surfaceGlass),
      surfaceGlassFallback: c(a.surfaceGlassFallback, b.surfaceGlassFallback),
      glassBorder: c(a.glassBorder, b.glassBorder),
      line: c(a.line, b.line),
      lineStrong: c(a.lineStrong, b.lineStrong),
      ink900: c(a.ink900, b.ink900),
      ink700: c(a.ink700, b.ink700),
      ink500: c(a.ink500, b.ink500),
      ink400: c(a.ink400, b.ink400),
      inkInverse: c(a.inkInverse, b.inkInverse),
      primary: c(a.primary, b.primary),
      primaryPressed: c(a.primaryPressed, b.primaryPressed),
      primarySoft: c(a.primarySoft, b.primarySoft),
      primarySoftStrong: c(a.primarySoftStrong, b.primarySoftStrong),
      onPrimary: c(a.onPrimary, b.onPrimary),
      success: c(a.success, b.success),
      successSoft: c(a.successSoft, b.successSoft),
      successAccent: c(a.successAccent, b.successAccent),
      warning: c(a.warning, b.warning),
      warningSoft: c(a.warningSoft, b.warningSoft),
      warningAccent: c(a.warningAccent, b.warningAccent),
      danger: c(a.danger, b.danger),
      dangerSoft: c(a.dangerSoft, b.dangerSoft),
      dangerAccent: c(a.dangerAccent, b.dangerAccent),
      scrim: c(a.scrim, b.scrim),
      focusRing: c(a.focusRing, b.focusRing),
    );
  }
}

/// Brand hues sampled from the app icon (`tokens.color.brand`).
abstract final class ShiriBrand {
  static const Color sky = Color(0xFF4CA4FF);
  static const Color cyan = Color(0xFF63CFE9);
  static const Color mint = Color(0xFF8DE0B2);
  static const Color sun300 = Color(0xFFFFEBA6);
  static const Color sun500 = Color(0xFFF6C86B);
  static const Color sunInk = Color(0xFF96620A);
  static const Color tileTop = Color(0xFFF8FCFF);
  static const Color tileMid = Color(0xFFFFFEFC);
  static const Color tileBottom = Color(0xFFF0F8FF);
}

// ---------------------------------------------------------------------------
// Gradients and the time-of-day sky
// ---------------------------------------------------------------------------

/// The four sky phases of the Today hero (`tokens.gradient.sky`).
///
/// Boundaries are Beijing wall-clock minutes. [night] wraps past midnight.
enum SkyPhase {
  dawn(startMinute: 5 * 60, endMinute: 8 * 60),
  day(startMinute: 8 * 60, endMinute: 16 * 60 + 30),
  dusk(startMinute: 16 * 60 + 30, endMinute: 19 * 60),
  night(startMinute: 19 * 60, endMinute: 5 * 60);

  const SkyPhase({required this.startMinute, required this.endMinute});

  /// Inclusive start, minutes after 00:00.
  final int startMinute;

  /// Exclusive end, minutes after 00:00.
  final int endMinute;
}

/// Gradient tokens plus the time-driven sky helpers.
///
/// CSS-style angles from the JSON are converted to [Alignment] pairs:
/// 135deg = top-left to bottom-right, 160deg = mostly downward, 180deg = top
/// to bottom.
abstract final class ShiriGradients {
  /// Decorative only: progress, active indicators, icon duotone, hero
  /// accents, illustrations. Never behind small text.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4CA4FF), Color(0xFF63CFE9), Color(0xFF8DE0B2)],
    stops: [0, 0.52, 1],
  );

  /// Tinted card / section backgrounds.
  static const LinearGradient brandSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEAF4FF), Color(0xFFE6F8FB), Color(0xFFEAF8F0)],
    stops: [0, 0.52, 1],
  );

  /// Today / now highlights, sun and moon, celebration accents (small doses).
  static const LinearGradient sun = LinearGradient(
    begin: Alignment(-0.364, -1),
    end: Alignment(0.364, 1),
    colors: [Color(0xFFFFEBA6), Color(0xFFF6C86B)],
  );

  /// Optional filled-button sheen. White label contrast >= 4.5:1 at center.
  static const LinearGradient primaryButton = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3A7FEA), Color(0xFF2A64D2)],
  );

  static const LinearGradient skyDawn = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFE7C2), Color(0xFFFFF3E2), Color(0xFFEEF5FF)],
    stops: [0, 0.45, 1],
  );

  static const LinearGradient skyDay = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFD6EAFF), Color(0xFFEAF4FF), Color(0xFFF6FAFF)],
    stops: [0, 0.5, 1],
  );

  static const LinearGradient skyDusk = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFDCCB), Color(0xFFF3E6FF), Color(0xFFEAF0FF)],
    stops: [0, 0.5, 1],
  );

  static const LinearGradient skyNight = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1B2747), Color(0xFF263A66), Color(0xFF34507F)],
    stops: [0, 0.55, 1],
  );

  /// Back wave layer (`gradient.wave.back`), painted at [waveBackOpacity].
  static const LinearGradient waveBack = LinearGradient(
    colors: [Color(0xFFD5EFEA), Color(0xFFD8EAFB)],
  );
  static const double waveBackOpacity = 0.82;

  /// Front wave layer (`gradient.wave.front`), painted at [waveFrontOpacity].
  static const LinearGradient waveFront = LinearGradient(
    colors: [Color(0xFFCFEDE9), Color(0xFFCDE2F8)],
  );
  static const double waveFrontOpacity = 0.88;

  /// Derived: dark-theme waves keep the mint-to-blue drift of the light
  /// tokens, blended into the dark page background so the hero still melts
  /// into the page.
  static const LinearGradient waveBackDark = LinearGradient(
    colors: [Color(0xFF16323A), Color(0xFF172B47)],
  );
  static const LinearGradient waveFrontDark = LinearGradient(
    colors: [Color(0xFF122A33), Color(0xFF13233D)],
  );

  /// `material.sheen`: white 0.55 -> 0 over the top 40% of hero surfaces.
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment(0, -0.2),
    colors: [Color.fromRGBO(255, 255, 255, 0.55), Color(0x00FFFFFF)],
  );

  /// Width of the sky cross-fade centered on each phase boundary.
  static const Duration skyCrossFade = Duration(minutes: 20);

  /// Converts an instant to Beijing wall-clock time (UTC+08:00, no DST).
  ///
  /// The result is a UTC [DateTime] whose fields read as Beijing local time,
  /// so it is independent of the device time zone (MASTER: 学校日期与钟点明确按
  /// UTC+08:00 转换).
  static DateTime beijingTime(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));

  /// The phase containing [beijingTime]; boundaries are hard switches.
  static SkyPhase phaseAt(DateTime beijingTime) {
    final minute = beijingTime.hour * 60 + beijingTime.minute;
    for (final phase in SkyPhase.values) {
      final start = phase.startMinute, end = phase.endMinute;
      final inside = start < end
          ? minute >= start && minute < end
          : minute >= start || minute < end;
      if (inside) return phase;
    }
    return SkyPhase.night;
  }

  /// The stops of one phase.
  static LinearGradient skyFor(SkyPhase phase) => switch (phase) {
    SkyPhase.dawn => skyDawn,
    SkyPhase.day => skyDay,
    SkyPhase.dusk => skyDusk,
    SkyPhase.night => skyNight,
  };

  /// The hero sky at [t] (Beijing time). Within ten minutes either side of a
  /// phase boundary the two phases cross-fade (ease-in-out over ~20 minutes),
  /// so a clock-driven header never jumps.
  static LinearGradient skyGradient(DateTime t) {
    final blend = skyBlendAt(t);
    if (blend.t <= 0) return skyFor(blend.from);
    if (blend.t >= 1) return skyFor(blend.to);
    return LinearGradient.lerp(skyFor(blend.from), skyFor(blend.to), blend.t)!;
  }

  /// Foreground for content on the sky at [t]: ink900 on dawn/day/dusk,
  /// white on night. During a cross-fade it switches where the two choices
  /// have equal contrast against the upper half of the sky (luminance 0.21),
  /// so text never sits on a background it cannot be read on.
  static Color onSky(DateTime t) {
    final sky = skyGradient(t);
    final upper =
        (sky.colors.first.computeLuminance() +
            sky.colors[1].computeLuminance()) /
        2;
    return upper < 0.21
        ? ShiriColors.light.inkInverse
        : ShiriColors.light.ink900;
  }

  /// 1 at night, 0 by day, continuous through the dusk/dawn cross-fades.
  /// Drives sun/moon swaps and the sheen strength.
  static double nightAmount(DateTime t) {
    final blend = skyBlendAt(t);
    double night(SkyPhase p) => p == SkyPhase.night ? 1 : 0;
    return night(blend.from) + (night(blend.to) - night(blend.from)) * blend.t;
  }

  /// Which two phases are visible at [t] and how far the cross-fade is.
  static SkyBlend skyBlendAt(DateTime t) {
    final minute = t.hour * 60 + t.minute + t.second / 60;
    final half = skyCrossFade.inSeconds / 120; // minutes on each side
    const boundaries = [
      (SkyPhase.night, SkyPhase.dawn, 5 * 60),
      (SkyPhase.dawn, SkyPhase.day, 8 * 60),
      (SkyPhase.day, SkyPhase.dusk, 16 * 60 + 30),
      (SkyPhase.dusk, SkyPhase.night, 19 * 60),
    ];
    for (final (from, to, at) in boundaries) {
      var delta = minute - at;
      if (delta > 720) delta -= 1440;
      if (delta < -720) delta += 1440;
      if (delta.abs() < half) {
        final linear = (delta + half) / (2 * half);
        return SkyBlend(from, to, Curves.easeInOut.transform(linear));
      }
    }
    final phase = phaseAt(t);
    return SkyBlend(phase, phase, 0);
  }
}

/// A moment in the sky cross-fade: [from] blended toward [to] by [t].
@immutable
class SkyBlend {
  const SkyBlend(this.from, this.to, this.t);
  final SkyPhase from;
  final SkyPhase to;
  final double t;

  /// The phase that dominates the blend.
  SkyPhase get dominant => t < 0.5 ? from : to;
}

// ---------------------------------------------------------------------------
// Course palettes and schedule kinds
// ---------------------------------------------------------------------------

/// One of the eight course palettes (`tokens.coursePalettes`).
///
/// Keeps the v1 shape (`background` / `accent` + text color) so call sites of
/// `campus_theme.dart`'s `CoursePalette` migrate by changing the import.
@immutable
class CoursePalette {
  const CoursePalette({
    required this.id,
    required this.name,
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final String id;

  /// Chinese display name (for a palette picker).
  final String name;

  /// Block fill.
  final Color background;

  /// Text on [background] (>= 4.5:1).
  final Color foreground;

  /// 3dp accent bar, dots, chart series.
  final Color accent;

  /// v1 name of [foreground], kept so existing `.ink` call sites compile.
  Color get ink => foreground;

  static const sky = CoursePalette(
    id: 'sky',
    name: '晴蓝',
    background: Color(0xFFE8F2FF),
    foreground: Color(0xFF1D5BB5),
    accent: Color(0xFF4A90F0),
  );
  static const mint = CoursePalette(
    id: 'mint',
    name: '薄荷',
    background: Color(0xFFE4F6EF),
    foreground: Color(0xFF0F7656),
    accent: Color(0xFF3DBE8B),
  );
  static const aqua = CoursePalette(
    id: 'aqua',
    name: '青湖',
    background: Color(0xFFE3F6FA),
    foreground: Color(0xFF0E6F85),
    accent: Color(0xFF33B5CF),
  );
  static const lilac = CoursePalette(
    id: 'lilac',
    name: '藤紫',
    background: Color(0xFFEFECFF),
    foreground: Color(0xFF5443BE),
    accent: Color(0xFF8C7BF0),
  );
  static const apricot = CoursePalette(
    id: 'apricot',
    name: '杏橙',
    background: Color(0xFFFFF0E6),
    foreground: Color(0xFFA9501F),
    accent: Color(0xFFF39A62),
  );
  static const blossom = CoursePalette(
    id: 'blossom',
    name: '樱粉',
    background: Color(0xFFFDECF2),
    foreground: Color(0xFFA83A61),
    accent: Color(0xFFE7779D),
  );
  static const wheat = CoursePalette(
    id: 'wheat',
    name: '麦黄',
    background: Color(0xFFFFF6DD),
    foreground: Color(0xFF8A6100),
    accent: Color(0xFFE5B23C),
  );
  static const mist = CoursePalette(
    id: 'mist',
    name: '雾灰',
    background: Color(0xFFEDF1F6),
    foreground: Color(0xFF44566E),
    accent: Color(0xFF8193AB),
  );

  static const List<CoursePalette> values = [
    sky,
    mint,
    aqua,
    lilac,
    apricot,
    blossom,
    wheat,
    mist,
  ];

  /// A palette that stays the same for a title across launches, devices and
  /// app versions (32-bit FNV-1a over the trimmed UTF-16 code units). Unlike
  /// v1's rune sum, anagrams and near-identical names spread across palettes.
  static CoursePalette forTitle(String title) {
    var hash = 0x811C9DC5;
    for (final unit in title.trim().codeUnits) {
      hash ^= unit;
      // hash * 16777619 (FNV prime) mod 2^32, written with shifts so the
      // result is identical on 64-bit native ints and on the web.
      hash =
          (hash +
              (hash << 1) +
              (hash << 4) +
              (hash << 7) +
              (hash << 8) +
              (hash << 24)) &
          0xFFFFFFFF;
    }
    return values[hash % values.length];
  }

  /// Derived dark variant: the accent tinted into the dark surface, with a
  /// lightened accent for text (>= 7:1 on the fill).
  CoursePalette onDark() => CoursePalette(
    id: id,
    name: name,
    background: Color.alphaBlend(
      accent.withValues(alpha: 0.20),
      ShiriColors.dark.surface,
    ),
    foreground: Color.lerp(accent, const Color(0xFFFFFFFF), 0.55)!,
    accent: accent,
  );

  /// The palette to paint with for [brightness].
  CoursePalette resolve(Brightness brightness) =>
      brightness == Brightness.dark ? onDark() : this;
}

/// Kinds of things on the timetable (`tokens.kindStyles`).
enum ScheduleKind { course, event, plan, exam, deadline }

/// How a [ScheduleKind] is drawn. Per the MASTER rule a kind is never shown by
/// color alone: each kind also differs in fill/border style, icon or badge.
@immutable
class KindStyle {
  const KindStyle({
    required this.kind,
    required this.fill,
    required this.accent,
    required this.foreground,
    this.accentGradient,
    this.border,
    this.borderWidth = 0,
    this.dashed = false,
    this.dash = 4,
    this.gap = 3,
    this.badge,
    this.icon,
  });

  final ScheduleKind kind;

  /// Block fill (transparent for deadlines, which are line markers).
  final Color fill;

  /// Solid accent (3dp bar, deadline line). For plans this is the middle
  /// stop of [accentGradient], for places that cannot paint a gradient.
  final Color accent;

  /// Accent bar gradient, when the kind uses one (plan).
  final Gradient? accentGradient;

  /// Title / location color on [fill].
  final Color foreground;

  final Color? border;
  final double borderWidth;

  /// Whether [border] is dashed ([dash] on, [gap] off).
  final bool dashed;
  final double dash;
  final double gap;

  /// Text badge shown with the title (计划 / 考试).
  final String? badge;

  /// Leading icon (event, deadline flag).
  final IconData? icon;

  /// Width of the left accent bar.
  static const double accentBarWidth = 3;

  /// Width of the deadline time marker line.
  static const double deadlineLineWidth = 2;

  /// The token style for [kind]. Courses need their [palette] (defaults to
  /// [CoursePalette.mist]). Dark styles are derived from the light tokens.
  static KindStyle of(
    ScheduleKind kind, {
    CoursePalette? palette,
    Brightness brightness = Brightness.light,
  }) {
    final light = _light(kind, palette ?? CoursePalette.mist);
    return brightness == Brightness.dark ? light._onDark() : light;
  }

  static KindStyle _light(ScheduleKind kind, CoursePalette palette) =>
      switch (kind) {
        ScheduleKind.course => KindStyle(
          kind: kind,
          fill: palette.background,
          accent: palette.accent,
          foreground: palette.foreground,
        ),
        ScheduleKind.event => const KindStyle(
          kind: ScheduleKind.event,
          fill: Color(0xFFFFFFFF),
          accent: Color(0xFF3FBF8F),
          foreground: Color(0xFF0F6B52),
          border: Color(0xFFBFE9D6),
          borderWidth: 1.5,
          icon: Icons.event_rounded,
        ),
        ScheduleKind.plan => const KindStyle(
          kind: ScheduleKind.plan,
          fill: Color(0xFFEAF2FF),
          accent: Color(0xFF63CFE9),
          accentGradient: ShiriGradients.brand,
          foreground: Color(0xFF1D5BB5),
          border: Color(0xFF8DBBF5),
          borderWidth: 1.5,
          dashed: true,
          badge: '计划',
        ),
        ScheduleKind.exam => const KindStyle(
          kind: ScheduleKind.exam,
          fill: Color(0xFFFDECE8),
          accent: Color(0xFFF0705A),
          foreground: Color(0xFFB03A26),
          badge: '考试',
        ),
        ScheduleKind.deadline => const KindStyle(
          kind: ScheduleKind.deadline,
          fill: Color(0x00000000),
          accent: Color(0xFFF2B33D),
          foreground: Color(0xFF8A6100),
          icon: Icons.flag_rounded,
        ),
      };

  /// Derived dark variant: accent tinted into the dark surface; text is the
  /// accent lightened toward white; borders keep the accent hue.
  KindStyle _onDark() {
    final surface = ShiriColors.dark.surface;
    return KindStyle(
      kind: kind,
      fill: kind == ScheduleKind.deadline
          ? fill
          : Color.alphaBlend(accent.withValues(alpha: 0.18), surface),
      accent: accent,
      accentGradient: accentGradient,
      foreground: Color.lerp(accent, const Color(0xFFFFFFFF), 0.55)!,
      border: border == null ? null : accent.withValues(alpha: 0.55),
      borderWidth: borderWidth,
      dashed: dashed,
      dash: dash,
      gap: gap,
      badge: badge,
      icon: icon,
    );
  }
}

// ---------------------------------------------------------------------------
// Typography
// ---------------------------------------------------------------------------

/// Text styles (`tokens.typography.styles`).
///
/// Line heights are expressed as multipliers with even leading, so CJK glyphs
/// sit centered in their line box. Numeric styles use tabular figures. The
/// family is the platform default (Roboto + Noto Sans CJK SC on Android); pass
/// a family through [apply] only for tests or explicit overrides.
@immutable
class ShiriType {
  const ShiriType({
    required this.display,
    required this.headline,
    required this.title,
    required this.titleSmall,
    required this.body,
    required this.bodyStrong,
    required this.bodySmall,
    required this.label,
    required this.caption,
    required this.numXL,
    required this.numL,
    required this.numM,
    required this.numS,
  });

  /// 34/40 w700. Greeting on the Today hero.
  final TextStyle display;

  /// 26/32 w700. Page titles.
  final TextStyle headline;

  /// 20/26 w600. Section and sheet titles.
  final TextStyle title;

  /// 17/24 w600. Card titles.
  final TextStyle titleSmall;

  /// 16/24 w400. Body copy.
  final TextStyle body;

  /// 16/24 w600. Emphasized body, buttons.
  final TextStyle bodyStrong;

  /// 14/20 w400. Secondary copy.
  final TextStyle bodySmall;

  /// 13/18 w600 +0.2. Chips, badges, block titles.
  final TextStyle label;

  /// 12/16 w500 +0.2. Meta text, time-axis labels.
  final TextStyle caption;

  /// 44/48 w700 tabular. Hero counters.
  final TextStyle numXL;

  /// 28/32 w700 tabular. Stat tiles.
  final TextStyle numL;

  /// 17/22 w600 tabular. Inline times.
  final TextStyle numM;

  /// 13/16 w600 tabular. Axis ticks, counts.
  final TextStyle numS;

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// The token styles without color or family.
  static const ShiriType base = ShiriType(
    display: TextStyle(
      fontSize: 34,
      height: 40 / 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    headline: TextStyle(
      fontSize: 26,
      height: 32 / 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    title: TextStyle(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    titleSmall: TextStyle(
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    body: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodyStrong: TextStyle(
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    bodySmall: TextStyle(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    label: TextStyle(
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    caption: TextStyle(
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    numXL: TextStyle(
      fontSize: 44,
      height: 48 / 44,
      fontWeight: FontWeight.w700,
      letterSpacing: -1.2,
      fontFeatures: _tabular,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    numL: TextStyle(
      fontSize: 28,
      height: 32 / 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      fontFeatures: _tabular,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    numM: TextStyle(
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      fontFeatures: _tabular,
      leadingDistribution: TextLeadingDistribution.even,
    ),
    numS: TextStyle(
      fontSize: 13,
      height: 16 / 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      fontFeatures: _tabular,
      leadingDistribution: TextLeadingDistribution.even,
    ),
  );

  /// Applies [color] and/or [fontFamily] to every style.
  ShiriType apply({Color? color, String? fontFamily}) {
    TextStyle a(TextStyle s) => s.apply(color: color, fontFamily: fontFamily);
    return ShiriType(
      display: a(display),
      headline: a(headline),
      title: a(title),
      titleSmall: a(titleSmall),
      body: a(body),
      bodyStrong: a(bodyStrong),
      bodySmall: a(bodySmall),
      label: a(label),
      caption: a(caption),
      numXL: a(numXL),
      numL: a(numL),
      numM: a(numM),
      numS: a(numS),
    );
  }

  static ShiriType lerp(ShiriType a, ShiriType b, double t) {
    TextStyle l(TextStyle x, TextStyle y) => TextStyle.lerp(x, y, t)!;
    return ShiriType(
      display: l(a.display, b.display),
      headline: l(a.headline, b.headline),
      title: l(a.title, b.title),
      titleSmall: l(a.titleSmall, b.titleSmall),
      body: l(a.body, b.body),
      bodyStrong: l(a.bodyStrong, b.bodyStrong),
      bodySmall: l(a.bodySmall, b.bodySmall),
      label: l(a.label, b.label),
      caption: l(a.caption, b.caption),
      numXL: l(a.numXL, b.numXL),
      numL: l(a.numL, b.numL),
      numM: l(a.numM, b.numM),
      numS: l(a.numS, b.numS),
    );
  }

  /// Maps the tokens onto Material roles so stock widgets pick them up.
  /// bodyMedium (the default [Text] style) is the 16sp body, as in MASTER.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: headline,
    headlineLarge: headline,
    headlineMedium: headline,
    headlineSmall: title,
    titleLarge: title,
    titleMedium: titleSmall,
    titleSmall: bodySmall.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: body,
    bodyMedium: body,
    bodySmall: bodySmall,
    labelLarge: bodySmall.copyWith(fontWeight: FontWeight.w600),
    labelMedium: label,
    labelSmall: caption,
  );
}

// ---------------------------------------------------------------------------
// Space, radius, shadow, layout
// ---------------------------------------------------------------------------

/// Spacing (`tokens.space`). Scale steps are named by their value.
abstract final class ShiriSpace {
  static const List<double> scale = [0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 56, 72];
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s56 = 56;
  static const double s72 = 72;

  /// Page side padding.
  static const double page = 20;

  /// Page side padding on narrow (<= 360dp) screens.
  static const double pageCompact = 16;
  static const double card = 16;
  static const double cardLoose = 20;
  static const double sectionGap = 28;
  static const double itemGap = 12;
}

/// Corner radii (`tokens.radius`).
abstract final class ShiriRadius {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  /// App-icon style tiles: radius = side * 0.22.
  static const double iconTileRatio = 0.22;

  static const BorderRadius xsAll = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Elevation (`tokens.shadow`). Cards and floating layers only, never on every
/// list row; blur <= 36.
@immutable
class ShiriShadows {
  const ShiriShadows({
    required this.card,
    required this.raised,
    required this.floating,
    required this.glowBrand,
    required this.glowSun,
  });

  final List<BoxShadow> card;
  final List<BoxShadow> raised;
  final List<BoxShadow> floating;
  final List<BoxShadow> glowBrand;
  final List<BoxShadow> glowSun;

  static const ShiriShadows light = ShiriShadows(
    card: [
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        color: Color.fromRGBO(20, 34, 56, 0.04),
      ),
      BoxShadow(
        offset: Offset(0, 6),
        blurRadius: 16,
        color: Color.fromRGBO(20, 34, 56, 0.06),
      ),
    ],
    raised: [
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 6,
        color: Color.fromRGBO(20, 34, 56, 0.05),
      ),
      BoxShadow(
        offset: Offset(0, 14),
        blurRadius: 32,
        color: Color.fromRGBO(46, 111, 224, 0.12),
      ),
    ],
    floating: [
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 8,
        color: Color.fromRGBO(20, 34, 56, 0.06),
      ),
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 36,
        color: Color.fromRGBO(20, 34, 56, 0.14),
      ),
    ],
    glowBrand: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        color: Color.fromRGBO(76, 164, 255, 0.32),
      ),
    ],
    glowSun: [
      BoxShadow(
        offset: Offset(0, 6),
        blurRadius: 20,
        color: Color.fromRGBO(246, 200, 107, 0.45),
      ),
    ],
  );

  /// Derived: same geometry, black ink at higher alpha so depth still reads
  /// on dark surfaces; glows are toned down.
  static const ShiriShadows dark = ShiriShadows(
    card: [
      BoxShadow(
        offset: Offset(0, 1),
        blurRadius: 2,
        color: Color.fromRGBO(0, 0, 0, 0.24),
      ),
      BoxShadow(
        offset: Offset(0, 6),
        blurRadius: 16,
        color: Color.fromRGBO(0, 0, 0, 0.28),
      ),
    ],
    raised: [
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 6,
        color: Color.fromRGBO(0, 0, 0, 0.30),
      ),
      BoxShadow(
        offset: Offset(0, 14),
        blurRadius: 32,
        color: Color.fromRGBO(0, 0, 0, 0.36),
      ),
    ],
    floating: [
      BoxShadow(
        offset: Offset(0, 2),
        blurRadius: 8,
        color: Color.fromRGBO(0, 0, 0, 0.32),
      ),
      BoxShadow(
        offset: Offset(0, 10),
        blurRadius: 36,
        color: Color.fromRGBO(0, 0, 0, 0.44),
      ),
    ],
    glowBrand: [
      BoxShadow(
        offset: Offset(0, 8),
        blurRadius: 24,
        color: Color.fromRGBO(111, 168, 255, 0.22),
      ),
    ],
    glowSun: [
      BoxShadow(
        offset: Offset(0, 6),
        blurRadius: 20,
        color: Color.fromRGBO(246, 200, 107, 0.30),
      ),
    ],
  );

  static ShiriShadows lerp(ShiriShadows a, ShiriShadows b, double t) =>
      ShiriShadows(
        card: BoxShadow.lerpList(a.card, b.card, t)!,
        raised: BoxShadow.lerpList(a.raised, b.raised, t)!,
        floating: BoxShadow.lerpList(a.floating, b.floating, t)!,
        glowBrand: BoxShadow.lerpList(a.glowBrand, b.glowBrand, t)!,
        glowSun: BoxShadow.lerpList(a.glowSun, b.glowSun, t)!,
      );
}

/// Component geometry (`tokens.layout`, `tokens.material`).
abstract final class ShiriLayout {
  static const double touchTarget = 48;

  static const double dockHeight = 64;
  static const double dockRadius = 28;
  static const double dockSideInset = 12;
  static const double dockBottomInset = 12;
  static const double dockIndicatorWidth = 56;
  static const double dockIndicatorHeight = 32;
  static const double dockIndicatorRadius = 16;

  static const double pillHeight = 52;
  static const double pillRadius = 26;
  static const double pillCollapsed = 52;
  static const double pillGapAboveDock = 10;

  static const double heroExpanded = 236;
  static const double heroCollapsed = 92;
  static const double heroOverlapNextCard = 28;

  static const double weekTimeAxis = 44;
  static const double weekPeriodRow = 56;
  static const double weekMinBlock = 44;
  static const double weekDayHeader = 56;

  /// `material.glass.blur`, used as the Gaussian sigma.
  static const double glassBlurSigma = 20;

  /// Space the floating dock + pill occupy above the bottom safe area, for
  /// page bottom padding: dock + insets + gap + pill.
  static const double dockReserve =
      dockHeight + dockBottomInset + pillGapAboveDock + pillHeight;
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Motion tokens (`tokens.motion`).
///
/// Rule of thumb: enter = [easeDecelerate], exit = [easeAccelerate],
/// move/resize = [easeStandard], text and card reveals = [easeReveal]; linear
/// only for shimmer and progress. Under reduced motion durations are 0 (an
/// opacity change up to [reducedFade] is allowed) and springs, parallax,
/// stagger and the sun-rise intro are skipped.
abstract final class ShiriMotion {
  static const Duration tap = Duration(milliseconds: 90);
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration standard = Duration(milliseconds: 260);
  static const Duration emphasized = Duration(milliseconds: 380);
  static const Duration slow = Duration(milliseconds: 520);
  static const Duration stagger = Duration(milliseconds: 36);
  static const int maxStaggerItems = 8;
  static const Duration shimmerLoop = Duration(milliseconds: 1200);

  /// Longest opacity-only change allowed under reduced motion.
  static const Duration reducedFade = Duration(milliseconds: 120);

  static const Cubic easeStandard = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Cubic easeDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const Cubic easeAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);
  static const Cubic easeReveal = Cubic(0.16, 1.0, 0.3, 1.0);

  /// Selection indicators, tab pill, segmented control, chips.
  static const SpringDescription snappy = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 38,
  );

  /// Sheets, cards settling after drag, dock collapse.
  static const SpringDescription gentle = SpringDescription(
    mass: 1,
    stiffness: 260,
    damping: 26,
  );

  /// Completion check pop only.
  static const SpringDescription pop = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 20,
  );
}

// ---------------------------------------------------------------------------
// Theme extension
// ---------------------------------------------------------------------------

/// The brightness-dependent tokens, attached to [ThemeData.extensions] by
/// `shiriLightTheme()` / `shiriDarkTheme()`. Read it with `context.shiri`.
@immutable
class ShiriTheme extends ThemeExtension<ShiriTheme> {
  const ShiriTheme({
    required this.colors,
    required this.text,
    required this.shadows,
  });

  /// Light tokens; [fontFamily] is for tests and explicit overrides only.
  factory ShiriTheme.light({String? fontFamily}) => ShiriTheme(
    colors: ShiriColors.light,
    text: ShiriType.base.apply(
      color: ShiriColors.light.ink900,
      fontFamily: fontFamily,
    ),
    shadows: ShiriShadows.light,
  );

  /// Dark tokens (phase 2).
  factory ShiriTheme.dark({String? fontFamily}) => ShiriTheme(
    colors: ShiriColors.dark,
    text: ShiriType.base.apply(
      color: ShiriColors.dark.ink900,
      fontFamily: fontFamily,
    ),
    shadows: ShiriShadows.dark,
  );

  final ShiriColors colors;

  /// Token styles colored with [ShiriColors.ink900].
  final ShiriType text;
  final ShiriShadows shadows;

  bool get isDark => colors.isDark;

  /// White card with the card shadow.
  BoxDecoration cardDecoration({BorderRadius borderRadius = ShiriRadius.mdAll}) =>
      BoxDecoration(
        color: colors.surface,
        borderRadius: borderRadius,
        boxShadow: shadows.card,
      );

  /// Hero and highlighted cards.
  BoxDecoration raisedDecoration({
    BorderRadius borderRadius = ShiriRadius.lgAll,
  }) => BoxDecoration(
    color: colors.surface,
    borderRadius: borderRadius,
    boxShadow: shadows.raised,
  );

  /// Opaque floating layers (menus, popovers). Glass layers use their own
  /// painter so the shadow does not tint the translucent fill.
  BoxDecoration floatingDecoration({
    BorderRadius borderRadius = ShiriRadius.xlAll,
  }) => BoxDecoration(
    color: colors.surface,
    borderRadius: borderRadius,
    boxShadow: shadows.floating,
  );

  /// Recessed well (inputs, segmented tracks).
  BoxDecoration sunkenDecoration({
    BorderRadius borderRadius = ShiriRadius.smAll,
  }) => BoxDecoration(color: colors.surfaceSunken, borderRadius: borderRadius);

  /// Tinted section background.
  BoxDecoration brandSoftDecoration({
    BorderRadius borderRadius = ShiriRadius.lgAll,
  }) => BoxDecoration(
    gradient: isDark ? null : ShiriGradients.brandSoft,
    color: isDark ? colors.bgTint : null,
    borderRadius: borderRadius,
  );

  @override
  ShiriTheme copyWith({
    ShiriColors? colors,
    ShiriType? text,
    ShiriShadows? shadows,
  }) => ShiriTheme(
    colors: colors ?? this.colors,
    text: text ?? this.text,
    shadows: shadows ?? this.shadows,
  );

  @override
  ShiriTheme lerp(covariant ThemeExtension<ShiriTheme>? other, double t) {
    if (other is! ShiriTheme) return this;
    return ShiriTheme(
      colors: ShiriColors.lerp(colors, other.colors, t),
      text: ShiriType.lerp(text, other.text, t),
      shadows: ShiriShadows.lerp(shadows, other.shadows, t),
    );
  }

  /// Used when no [ShiriTheme] is attached (e.g. isolated widget tests).
  static final ShiriTheme fallback = ShiriTheme.light();
}

/// `context.shiri` — the [ShiriTheme] of the nearest [Theme].
extension ShiriThemeContext on BuildContext {
  ShiriTheme get shiri =>
      Theme.of(this).extension<ShiriTheme>() ?? ShiriTheme.fallback;
}
