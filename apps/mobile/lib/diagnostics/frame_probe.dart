import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Explicit opt-in device QA, no network telemetry or application content.
/// The buffer is bounded and excluded from normal builds by a const flag.
void installFrameProbe() {
  if (!const bool.fromEnvironment('QA_FRAME_PROBE') || kReleaseMode) return;
  final frames = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback((batch) {
    frames.addAll(batch);
    if (frames.length > 5000) frames.removeRange(0, frames.length - 5000);
  });
  registerExtension('ext.semesteros.frames', (_, params) async {
    if (params['reset'] == 'true') frames.clear();
    Map<String, dynamic> stats(List<double> values) {
      values.sort();
      double? percentile(double q) =>
          values.isEmpty ? null : values[((values.length - 1) * q).round()];
      return {
        'p50_ms': percentile(.5),
        'p90_ms': percentile(.9),
        'p99_ms': percentile(.99),
        'max_ms': values.lastOrNull,
        'over_16_67_ms': values.where((v) => v > 16.67).length,
      };
    }

    return ServiceExtensionResponse.result(
      jsonEncode({
        'mode': kProfileMode ? 'profile' : 'debug',
        'samples': frames.length,
        'build': stats(
          frames.map((f) => f.buildDuration.inMicroseconds / 1000).toList(),
        ),
        'raster': stats(
          frames.map((f) => f.rasterDuration.inMicroseconds / 1000).toList(),
        ),
        'note':
            'Stage durations; threshold counts are not measured OS dropped frames.',
      }),
    );
  });
}
