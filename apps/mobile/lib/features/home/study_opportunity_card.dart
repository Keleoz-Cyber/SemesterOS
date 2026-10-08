import 'package:flutter/material.dart';
import '../../app/controller.dart' show schoolTime, hhmm;
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/motion.dart';
import '../../ui/v2/shiri_tokens.dart';
import '../../ui/v2/widgets/gap_slot_bar.dart';

class StudyOpportunityCard extends StatelessWidget {
  final Map<String, dynamic> value;
  final DateTime now;
  final bool ready, busy;
  final VoidCallback onArrange, onOpen;
  final Widget? preview;
  final bool saved;
  const StudyOpportunityCard({
    super.key,
    required this.value,
    required this.now,
    required this.ready,
    required this.busy,
    required this.onArrange,
    required this.onOpen,
    this.preview,
    this.saved = false,
  });

  @override
  Widget build(BuildContext context) {
    final start = schoolTime(value['start_at']),
        end = schoolTime(value['end_at']);
    final latest = schoolTime(value['latest_start_at']);
    final effective = saved
        ? start
        : now.isAfter(start)
        ? now
        : start;
    final minutes = end.difference(effective).inMinutes;
    final target = value['target_minutes'] as int;
    if (!saved &&
        preview == null &&
        (now.isAfter(latest) || minutes < target)) {
      return const SizedBox.shrink();
    }
    final pending = value['needs_check'] == true;
    final heading = saved
        ? '学习安排'
        : value['display_phase'] == 'proposal'
        ? '本次安排'
        : pending
        ? '候选空档'
        : value['before_kind'] == 'course'
        ? '课前空档'
        : '可利用的空档';
    return AppContentTransition(
      value: '${value['item_id']}/${value['start_at']}',
      child: Container(
        key: const Key('study-opportunity'),
        margin: const EdgeInsets.only(bottom: ShiriSpace.sectionGap),
        padding: const EdgeInsets.all(20),
        decoration: context.shiri.brandSoftDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ExcludeSemantics(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CustomPaint(painter: _GapGlyph()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    heading,
                    style: const TextStyle(
                      color: CampusColors.teal,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$minutes分钟',
                  style: const TextStyle(
                    color: CampusColors.teal,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GapSlotBar(
              start: hhmm(effective),
              end: hhmm(end),
              gapMinutes: minutes > 0 ? minutes : target,
              taskTitle: '${value['title']}',
              taskMinutes: target,
              filled: saved,
            ),
            const SizedBox(height: 16),
            Text(
              '${value['title']}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (value['already_planned_minutes'] as num? ?? 0) > 0
                  ? '还有$target分钟未安排'
                  : saved
                  ? '已安排$target分钟'
                  : '预计需要$target分钟',
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
            const SizedBox(height: 8),
            if (pending)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '相关安排时间待核对',
                  style: TextStyle(fontSize: 13, color: CampusColors.muted),
                ),
              ),
            if (preview != null)
              preview!
            else if (!saved)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  AppButton.icon(
                    key: const Key('opportunity-arrange'),
                    onPressed: ready && !busy ? onArrange : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(busy ? '正在生成预览' : '安排这项'),
                  ),
                  AppTextButton(
                    onPressed: busy ? null : onOpen,
                    child: const Text('查看任务'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GapGlyph extends CustomPainter {
  const _GapGlyph();
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = CampusColors.teal
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(3, 5), const Offset(10, 5), pen);
    canvas.drawLine(const Offset(18, 23), const Offset(25, 23), pen);
    canvas.drawPath(
      Path()
        ..moveTo(10, 5)
        ..cubicTo(24, 5, 4, 23, 18, 23),
      pen,
    );
    canvas.drawCircle(
      const Offset(3, 5),
      2,
      Paint()..color = CampusColors.teal,
    );
    canvas.drawCircle(
      const Offset(25, 23),
      2,
      Paint()..color = CampusColors.teal,
    );
  }

  @override
  bool shouldRepaint(covariant _GapGlyph oldDelegate) => false;
}
