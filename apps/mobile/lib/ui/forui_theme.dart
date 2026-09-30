import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'campus_theme.dart';

/// Forui and Material share the same campus palette, rather than mixing themes.
FThemeData campusForuiTheme({String? fontFamily}) {
  final colors = FColors.neutralLight.copyWith(
    background: CampusColors.surface,
    foreground: CampusColors.ink,
    primary: CampusColors.primary,
    primaryForeground: Colors.white,
    secondary: CampusColors.blueSoft,
    secondaryForeground: CampusColors.primary,
    muted: CampusColors.background,
    mutedForeground: CampusColors.muted,
    card: CampusColors.surface,
    border: CampusColors.line,
    destructive: CampusColors.error,
    destructiveForeground: Colors.white,
    error: CampusColors.error,
    errorForeground: Colors.white,
  );
  final typeface = FTypeface.inherit(
    colors: colors,
    touch: true,
    fontFamily: fontFamily ?? FTypeface.defaultFontFamily,
  );
  final typography = FTypography(body: typeface, display: typeface);
  return FThemeData(
    debugLabel: '拾日 · 校园蓝绿',
    colors: colors,
    touch: true,
    typography: typography,
    style: FStyle.inherit(colors: colors, typography: typography, touch: true)
        .copyWith(
          borderRadius: const FBorderRadius(
            md: BorderRadius.all(Radius.circular(14)),
            lg: BorderRadius.all(Radius.circular(18)),
          ),
          // Avoid scaling whole rows/buttons on press; state colors convey feedback.
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
  Widget build(BuildContext context) => FTheme(
    data: campusForuiTheme(
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
    ),
    child: child,
  );
}
