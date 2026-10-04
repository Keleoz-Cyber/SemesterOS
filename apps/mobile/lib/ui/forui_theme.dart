import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'campus_theme.dart';
import 'accessibility.dart';

/// Forui and Material share the same campus palette, rather than mixing themes.
FThemeData campusForuiTheme({
  String? fontFamily,
  ThemeData? materialTheme,
  bool highContrast = false,
}) {
  final base = materialTheme ?? campusTheme();
  final theme = highContrast ? campusHighContrastTheme(base: base) : base;
  final scheme = theme.colorScheme;
  final colors =
      (theme.brightness == Brightness.dark
              ? FColors.neutralDark
              : FColors.neutralLight)
          .copyWith(
            background: scheme.surface,
            foreground: scheme.onSurface,
            primary: scheme.primary,
            primaryForeground: scheme.onPrimary,
            secondary: scheme.primaryContainer,
            secondaryForeground: scheme.onPrimaryContainer,
            muted: theme.scaffoldBackgroundColor,
            mutedForeground: scheme.onSurfaceVariant,
            card: scheme.surface,
            border: scheme.outlineVariant,
            destructive: scheme.error,
            destructiveForeground: scheme.onError,
            error: scheme.error,
            errorForeground: scheme.onError,
          );
  final typeface = FTypeface.inherit(
    colors: colors,
    touch: true,
    fontFamily: fontFamily ?? FTypeface.defaultFontFamily,
  );
  final typography = FTypography(body: typeface, display: typeface);
  return FThemeData(
    debugLabel: highContrast ? '拾日 · 校园高对比度' : '拾日 · 校园蓝绿',
    colors: colors,
    touch: true,
    typography: typography,
    style: FStyle.inherit(colors: colors, typography: typography, touch: true)
        .copyWith(
          borderRadius: const FBorderRadius(
            md: BorderRadius.all(Radius.circular(14)),
            lg: BorderRadius.all(Radius.circular(18)),
          ),
          // Rows remain still; compact buttons opt into a bounded press response.
          tappableStyle: const FTappableStyleDelta.delta(
            motion: FTappableMotion.none,
          ),
        ),
  );
}

class ShiriForuiTheme extends StatelessWidget {
  final Widget child;
  const ShiriForuiTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) => HighContrastDetector(
    child: child,
    builder: (context, highContrast) => FTheme(
      data: campusForuiTheme(
        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        materialTheme: Theme.of(context),
        highContrast: highContrast,
      ),
      child: child,
    ),
  );
}
