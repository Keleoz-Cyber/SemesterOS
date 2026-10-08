/// Material 3 themes for 「晴日」(shiri v2).
///
/// ```dart
/// MaterialApp(
///   theme: shiriLightTheme(),
///   darkTheme: shiriDarkTheme(),
/// );
/// ```
///
/// The [ColorScheme] is built role by role from the tokens (not `fromSeed`), the
/// [ShiriTheme] extension is attached, and stock widgets get 48dp targets.
library;

import 'package:flutter/material.dart';

import 'shiri_tokens.dart';

/// Light theme. [fontFamily] is for tests / explicit overrides; production
/// uses the platform family (Roboto + Noto Sans CJK SC on Android).
ThemeData shiriLightTheme({String? fontFamily}) =>
    shiriThemeFrom(ShiriTheme.light(fontFamily: fontFamily), fontFamily);

/// Dark theme (phase 2 tokens).
ThemeData shiriDarkTheme({String? fontFamily}) =>
    shiriThemeFrom(ShiriTheme.dark(fontFamily: fontFamily), fontFamily);

/// The token-to-Material role mapping. Selection states that M3 paints with
/// `secondaryContainer` (filter chips, segmented buttons) resolve to the soft
/// primary blue, so selection looks the same everywhere.
ColorScheme shiriColorScheme(ShiriColors c) {
  final dark = c.isDark;
  return ColorScheme(
    brightness: c.brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primarySoft,
    onPrimaryContainer: c.primaryPressed,
    secondary: c.ink700,
    onSecondary: c.inkInverse,
    secondaryContainer: c.primarySoftStrong,
    onSecondaryContainer: c.primaryPressed,
    tertiary: c.success,
    onTertiary: c.inkInverse,
    tertiaryContainer: c.successSoft,
    onTertiaryContainer: c.success,
    error: c.danger,
    onError: c.inkInverse,
    errorContainer: c.dangerSoft,
    onErrorContainer: c.danger,
    surface: c.surface,
    onSurface: c.ink900,
    onSurfaceVariant: c.ink500,
    surfaceDim: dark ? c.bg : c.surfaceSunken,
    surfaceBright: c.surface,
    surfaceContainerLowest: dark ? c.bg : c.surface,
    surfaceContainerLow: dark ? c.surfaceSunken : c.bg,
    surfaceContainer: dark ? c.surface : c.surfaceSunken,
    // Derived for dark: midpoint of surface and line.
    surfaceContainerHigh: dark ? const Color(0xFF1A263C) : c.bgTint,
    surfaceContainerHighest: c.line,
    outline: c.ink400,
    outlineVariant: c.line,
    shadow: dark ? const Color(0xFF000000) : c.ink900,
    scrim: dark ? const Color(0xFF000000) : c.ink900,
    inverseSurface: c.ink900,
    onInverseSurface: c.inkInverse,
    inversePrimary: dark ? ShiriColors.light.primary : ShiriColors.dark.primary,
    surfaceTint: const Color(0x00000000),
  );
}

/// Builds the full [ThemeData] for a [ShiriTheme].
ThemeData shiriThemeFrom(ShiriTheme shiri, [String? fontFamily]) {
  final c = shiri.colors;
  final t = shiri.text;
  final scheme = shiriColorScheme(c);
  const buttonShape = RoundedRectangleBorder(borderRadius: ShiriRadius.mdAll);

  return ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    colorScheme: scheme,
    fontFamily: fontFamily,
    textTheme: t.toTextTheme(),
    extensions: [shiri],
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    dividerColor: c.line,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    iconTheme: IconThemeData(color: c.ink700, size: 24),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ShiriFadeThroughPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.ink900,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: t.title,
      iconTheme: IconThemeData(color: c.ink900),
    ),

    // Buttons ---------------------------------------------------------------
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        shape: const WidgetStatePropertyAll(buttonShape),
        elevation: const WidgetStatePropertyAll(0),
        textStyle: WidgetStatePropertyAll(t.bodyStrong),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return c.line;
          if (states.contains(WidgetState.pressed)) return c.primaryPressed;
          return c.primary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? c.ink400
              : c.onPrimary,
        ),
        overlayColor: WidgetStatePropertyAll(c.onPrimary.withValues(alpha: .1)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
        shape: const WidgetStatePropertyAll(buttonShape),
        textStyle: WidgetStatePropertyAll(t.bodyStrong),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? c.ink400 : c.primary,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? c.primary
                : c.lineStrong,
            width: states.contains(WidgetState.focused) ? 2 : 1.2,
          ),
        ),
        overlayColor: WidgetStatePropertyAll(c.primary.withValues(alpha: .08)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: ShiriRadius.smAll),
        ),
        textStyle: WidgetStatePropertyAll(
          t.bodySmall.copyWith(fontWeight: FontWeight.w600),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? c.ink400 : c.primary,
        ),
        overlayColor: WidgetStatePropertyAll(c.primary.withValues(alpha: .08)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.square(48)),
        iconSize: const WidgetStatePropertyAll(24),
        tapTargetSize: MaterialTapTargetSize.padded,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? c.ink400 : c.ink700,
        ),
        overlayColor: WidgetStatePropertyAll(c.ink900.withValues(alpha: .06)),
      ),
    ),

    // Inputs and selection ----------------------------------------------------
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surfaceSunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: t.body.copyWith(color: c.ink400),
      labelStyle: t.body.copyWith(color: c.ink500),
      floatingLabelStyle: t.label.copyWith(color: c.primary),
      helperStyle: t.caption.copyWith(color: c.ink500),
      errorStyle: t.caption.copyWith(color: c.danger),
      prefixIconColor: c.ink500,
      suffixIconColor: c.ink500,
      border: const OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide(color: c.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide(color: c.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide(color: c.danger, width: 2),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: ShiriRadius.smAll,
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.primarySoftStrong,
      disabledColor: c.surfaceSunken,
      checkmarkColor: c.primaryPressed,
      showCheckmark: true,
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? c.primarySoftStrong
              : c.line,
        ),
      ),
      shape: const RoundedRectangleBorder(borderRadius: ShiriRadius.smAll),
      labelStyle: t.label.copyWith(color: c.ink700),
      secondaryLabelStyle: t.label.copyWith(color: c.primaryPressed),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      iconTheme: IconThemeData(color: c.ink500, size: 18),
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) {
          return const Color(0x00000000);
        }
        return states.contains(WidgetState.disabled) ? c.ink400 : c.primary;
      }),
      checkColor: WidgetStatePropertyAll(c.onPrimary),
      // Unchecked border uses ink500 (5.4:1) - ink400 misses 3:1 on white.
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const BorderSide(width: 0, color: Color(0x00000000));
        }
        return BorderSide(
          color: states.contains(WidgetState.disabled)
              ? c.lineStrong
              : c.ink500,
          width: 1.6,
        );
      }),
    ),
    switchTheme: SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return c.onPrimary;
        return states.contains(WidgetState.disabled) ? c.lineStrong : c.ink500;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return states.contains(WidgetState.disabled) ? c.line : c.primary;
        }
        return c.surfaceSunken;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0x00000000)
            : c.ink500,
      ),
      // The check keeps "on" readable without relying on color.
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Icon(Icons.check_rounded, size: 16, color: c.primary)
            : null,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.primarySoft,
      circularTrackColor: c.primarySoft,
      linearMinHeight: 6,
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      strokeCap: StrokeCap.round,
    ),

    // Surfaces --------------------------------------------------------------
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: const Color(0x00000000),
      shape: const RoundedRectangleBorder(borderRadius: ShiriRadius.mdAll),
      clipBehavior: Clip.antiAlias,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: const Color(0x00000000),
      modalBarrierColor: c.scrim,
      elevation: 0,
      modalElevation: 0,
      showDragHandle: true,
      dragHandleColor: c.lineStrong,
      dragHandleSize: const Size(36, 4),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShiriRadius.xl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: const Color(0x00000000),
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(borderRadius: ShiriRadius.xlAll),
      titleTextStyle: t.title,
      contentTextStyle: t.body.copyWith(color: c.ink700),
    ),
    dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      minVerticalPadding: 10,
      minTileHeight: 56,
      minLeadingWidth: 24,
      horizontalTitleGap: 12,
      iconColor: c.ink500,
      textColor: c.ink900,
      titleTextStyle: t.bodyStrong,
      subtitleTextStyle: t.bodySmall.copyWith(color: c.ink500),
      leadingAndTrailingTextStyle: t.numS.copyWith(color: c.ink500),
      selectedColor: c.primaryPressed,
      selectedTileColor: c.primarySoft,
      shape: const RoundedRectangleBorder(borderRadius: ShiriRadius.smAll),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink900,
      contentTextStyle: t.bodySmall.copyWith(color: c.inkInverse),
      actionTextColor: c.isDark ? ShiriColors.light.primary : ShiriColors.dark.primaryPressed,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: const RoundedRectangleBorder(borderRadius: ShiriRadius.mdAll),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.ink900.withValues(alpha: .92),
        borderRadius: ShiriRadius.xsAll,
      ),
      textStyle: t.caption.copyWith(color: c.inkInverse),
    ),
  );
}

/// The optional `gradient.primaryButton` sheen for the one primary action of a
/// screen: `FilledButton(style: shiriSheenButtonStyle(), ...)`.
///
/// Not part of the global theme on purpose: `FilledButton.tonal` shares the
/// filled-button theme and must stay flat. The gradient is painted with [Ink]
/// so the ripple stays visible; the button clips it to its shape.
ButtonStyle shiriSheenButtonStyle() => ButtonStyle(
  backgroundBuilder: (context, states, child) {
    if (states.contains(WidgetState.disabled) ||
        states.contains(WidgetState.pressed)) {
      return child ?? const SizedBox.shrink();
    }
    return Ink(
      decoration: const BoxDecoration(gradient: ShiriGradients.primaryButton),
      child: child,
    );
  },
);

/// Android page transition: a fade-through.
///
/// The outgoing page fades out over the first 90ms (accelerate); the incoming
/// page then fades in and scales 0.98 -> 1 over 260ms (decelerate), on top of
/// the scaffold color, so two pages' text never overlap (MASTER). Pops play
/// the same sequence. Under reduced motion pages swap without a transition;
/// the widget tree is identical either way, so toggling the setting keeps
/// page state.
class ShiriFadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const ShiriFadeThroughPageTransitionsBuilder();

  static const Duration fadeOut = ShiriMotion.tap;
  static const Duration fadeIn = ShiriMotion.standard;

  @override
  Duration get transitionDuration => fadeOut + fadeIn;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return _FadeThrough(
      animation: reduce ? kAlwaysCompleteAnimation : animation,
      secondaryAnimation: reduce
          ? kAlwaysDismissedAnimation
          : secondaryAnimation,
      fillColor: Theme.of(context).scaffoldBackgroundColor,
      child: child,
    );
  }
}

class _FadeThrough extends StatelessWidget {
  const _FadeThrough({
    required this.animation,
    required this.secondaryAnimation,
    required this.fillColor,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Color fillColor;
  final Widget child;

  static final double _split =
      ShiriFadeThroughPageTransitionsBuilder.fadeOut.inMicroseconds /
      (ShiriFadeThroughPageTransitionsBuilder.fadeOut +
              ShiriFadeThroughPageTransitionsBuilder.fadeIn)
          .inMicroseconds;

  static final Animatable<double> _fadeIn = CurveTween(
    curve: Interval(_split, 1, curve: ShiriMotion.easeDecelerate),
  );
  static final Animatable<double> _scaleIn = Tween<double>(
    begin: 0.98,
    end: 1,
  ).chain(_fadeIn);
  static final Animatable<double> _fadeOut = Tween<double>(
    begin: 1,
    end: 0,
  ).chain(CurveTween(curve: Interval(0, _split, curve: ShiriMotion.easeAccelerate)));

  static Widget _in(BuildContext context, Animation<double> a, Widget? child) =>
      FadeTransition(
        opacity: a.drive(_fadeIn),
        child: ScaleTransition(scale: a.drive(_scaleIn), child: child),
      );

  // DualTransitionBuilder hands the reverse builder a time-forward 0 -> 1
  // animation, so the fade-out maps the first 90ms of it.
  static Widget _out(BuildContext context, Animation<double> a, Widget? child) =>
      FadeTransition(opacity: a.drive(_fadeOut), child: child);

  @override
  Widget build(BuildContext context) {
    // Outer pair: this route entering / leaving. Inner pair: a route above it
    // covering / uncovering it. The fill sits between them, so a covered page
    // fades to the scaffold color instead of to whatever is behind the
    // navigator.
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: _in,
      reverseBuilder: _out,
      child: ColoredBox(
        color: fillColor,
        child: DualTransitionBuilder(
          animation: ReverseAnimation(secondaryAnimation),
          forwardBuilder: _in,
          reverseBuilder: _out,
          child: child,
        ),
      ),
    );
  }
}
