import 'package:flutter/material.dart';
import '../../ui/accessibility.dart';
import '../../ui/campus_theme.dart';
import '../../ui/v2/shiri_tokens.dart';

/// Progress through the configured academic calendar, with no inferred exam
/// dates or study-completion milestones.
class SemesterProgressCard extends StatelessWidget {
  final Map<String, dynamic>? semester;
  final DateTime now;
  const SemesterProgressCard({
    super.key,
    required this.semester,
    required this.now,
  });
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${semester?['first_monday']}');
    final weeks = semester?['total_weeks'];
    if (date == null || weeks is! int || weeks <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '请补充学期首周与总周数后查看学期进度',
          style: TextStyle(color: CampusColors.muted, fontSize: 13),
        ),
      );
    }
    final start = DateTime.utc(date.year, date.month, date.day);
    final end = start.add(Duration(days: weeks * 7));
    final day = DateTime.utc(now.year, now.month, now.day);
    final wall = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final progress =
        (wall.difference(start).inMinutes / end.difference(start).inMinutes)
            .clamp(0.0, 1.0);
    final currentWeek = day.difference(start).inDays ~/ 7 + 1;
    final label = day.isBefore(start)
        ? '尚未开学'
        : !day.isBefore(end)
        ? '学期已结束'
        : '第$currentWeek周 / 共$weeks周';
    final last = end.subtract(const Duration(days: 1));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: context.shiri.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '学期进度',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (day.isBefore(start) || !day.isBefore(end))
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: CampusColors.primary,
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '第$currentWeek周',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: CampusColors.primary,
                  ),
                ),
                Text(
                  '共$weeks周',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          SemanticProgressBar(
            value: progress,
            label: '学期日历进度',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 26,
                child: CustomPaint(
                  painter: _SemesterRuler(weeks: weeks, progress: progress),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${start.month}月${start.day}日 — ${last.month}月${last.day}日',
            style: const TextStyle(fontSize: 12, color: CampusColors.muted),
          ),
        ],
      ),
    );
  }
}

class _SemesterRuler extends CustomPainter {
  final int weeks;
  final double progress;
  const _SemesterRuler({required this.weeks, required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..color = CampusColors.line
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = CampusColors.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final right = size.width - 4;
    canvas.drawLine(const Offset(4, 18), Offset(right, 18), track);
    canvas.drawLine(
      const Offset(4, 18),
      Offset(4 + (right - 4) * progress, 18),
      active,
    );
    for (var i = 0; i <= weeks; i++) {
      final x = 4 + (right - 4) * i / weeks;
      canvas.drawLine(
        Offset(x, i % 5 == 0 ? 10 : 14),
        Offset(x, 22),
        i / weeks <= progress ? active : track,
      );
    }
    final x = 4 + (right - 4) * progress;
    canvas.drawPath(
      Path()
        ..moveTo(x - 4, 2)
        ..lineTo(x + 4, 2)
        ..lineTo(x, 7)
        ..close(),
      Paint()..color = CampusColors.teal,
    );
  }

  @override
  bool shouldRepaint(_SemesterRuler old) =>
      old.weeks != weeks || old.progress != progress;
}
