/// Reduced-motion helpers shared by every shiri v2 animation.
///
/// Same source of truth as the app's `AppMotion`:
/// [MediaQuery.disableAnimationsOf] (Android "Remove animations"). Per
/// `tokens.motion.reducedMotion`: durations become 0 (an opacity change up to
/// 120ms is allowed) and springs, parallax, stagger and the sun-rise intro
/// are skipped.
library;

import 'package:flutter/widgets.dart';

import '../shiri_tokens.dart';

/// Whether the platform asked to reduce motion. Safe without a [MediaQuery].
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [full] normally, [Duration.zero] under reduced motion.
Duration motionDuration(BuildContext context, Duration full) =>
    reduceMotion(context) ? Duration.zero : full;

/// For opacity-only changes: [full] normally, at most
/// [ShiriMotion.reducedFade] (120ms) under reduced motion.
Duration motionFadeDuration(BuildContext context, Duration full) {
  if (!reduceMotion(context)) return full;
  return full < ShiriMotion.reducedFade ? full : ShiriMotion.reducedFade;
}

/// Whether decorative motion may run here: not reduced, and tickers are
/// enabled (the subtree is not offstage, e.g. a hidden tab).
bool motionAllowed(BuildContext context) =>
    !reduceMotion(context) && TickerMode.valuesOf(context).enabled;
