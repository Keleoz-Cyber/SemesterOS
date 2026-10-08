import 'package:flutter/material.dart';

import '../../app/controller.dart' show schoolTime;
import '../../ui/v2/shiri_tokens.dart';

/// Surfaces are presentation only: confirmation authority remains in the
/// existing preview and receipt widgets.
class AgentSurface extends StatelessWidget {
  final Widget child;
  final bool raised;
  final Color? color;
  final EdgeInsetsGeometry padding;
  const AgentSurface({
    super.key,
    required this.child,
    this.raised = false,
    this.color,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final shiri = context.shiri;
    return Container(
      decoration: BoxDecoration(
        color: color ?? shiri.colors.surface,
        borderRadius: BorderRadius.circular(ShiriRadius.lg),
        boxShadow: raised ? shiri.shadows.raised : shiri.shadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ShiriRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class AssistantMark extends StatelessWidget {
  final double size;
  const AssistantMark({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: ShiriGradients.brand,
        borderRadius: BorderRadius.circular(size * .22),
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * .58,
        color: Colors.white,
      ),
    ),
  );
}

/// A compact track drawn only from the returned clocks. It never invents an
/// event end or treats a candidate as confirmed free time.
class AssistantWindowRow extends StatelessWidget {
  final Map<String, dynamic> window;
  final String label;
  final Map<String, dynamic> dailySearch;
  const AssistantWindowRow({
    super.key,
    required this.window,
    required this.label,
    this.dailySearch = const {},
  });

  int? _clock(dynamic raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('$raw');
    if (match == null) return null;
    final hours = int.tryParse(match.group(1)!);
    final minutes = int.tryParse(match.group(2)!);
    if (hours == null ||
        minutes == null ||
        hours > 24 ||
        minutes > 59 ||
        (hours == 24 && minutes != 0)) {
      return null;
    }
    return hours * 60 + minutes;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shiri.colors;
    final rawStart = window['start_at'] ?? window['start'];
    final rawEnd = window['end_at'] ?? window['end'];
    final start = DateTime.tryParse('$rawStart');
    final end = DateTime.tryParse('$rawEnd');
    final localStart = start == null ? null : schoolTime('$rawStart');
    final localEnd = end == null ? null : schoolTime('$rawEnd');
    final from = _clock(dailySearch['start']);
    final to = _clock(dailySearch['end']);
    final hasTrack =
        localStart != null &&
        localEnd != null &&
        from != null &&
        to != null &&
        to > from &&
        localEnd.isAfter(localStart);
    final candidate = window['needs_check'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                candidate ? Icons.info_outline_rounded : Icons.schedule_rounded,
                size: 20,
                color: candidate ? colors.warning : colors.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: context.shiri.text.bodyStrong),
              ),
            ],
          ),
          if (candidate)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: Text(
                '需核对安排结束时间',
                style: context.shiri.text.bodySmall.copyWith(
                  color: colors.warning,
                ),
              ),
            ),
          if (hasTrack) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final aStart = localStart, bEnd = localEnd;
                  final trackStart = from, trackEnd = to;
                  final a =
                      ((aStart.hour * 60 + aStart.minute - trackStart) /
                              (trackEnd - trackStart))
                          .clamp(0.0, 1.0);
                  final differentDate =
                      aStart.year != bEnd.year ||
                      aStart.month != bEnd.month ||
                      aStart.day != bEnd.day;
                  final endMinutes = differentDate
                      ? 1440
                      : bEnd.hour * 60 + bEnd.minute;
                  final b =
                      ((endMinutes - trackStart) / (trackEnd - trackStart))
                          .clamp(0.0, 1.0);
                  return ExcludeSemantics(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ShiriRadius.xs),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ColoredBox(color: colors.surfaceSunken),
                            ),
                            if (b > a)
                              Positioned(
                                left: bounds.maxWidth * a,
                                width: bounds.maxWidth * (b - a),
                                top: 0,
                                bottom: 0,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: candidate
                                        ? colors.warningAccent
                                        : null,
                                    gradient: candidate
                                        ? null
                                        : ShiriGradients.brand,
                                    borderRadius: BorderRadius.circular(
                                      ShiriRadius.xs,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
