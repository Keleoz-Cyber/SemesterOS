import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';

class SemesterView extends StatelessWidget {
  final List<Map<String, dynamic>> semesters;
  final Map<String, dynamic> current;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onCreate, onImport, onManual;
  const SemesterView({
    super.key,
    required this.semesters,
    required this.current,
    required this.onSelect,
    required this.onCreate,
    required this.onImport,
    required this.onManual,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const CampusHero(
        eyebrow: '我的时间',
        title: '我的学期',
        subtitle: '从第一周开始\n把每一段安排放好',
      ),
      SectionHeading('学期列表', action: '新建学期', onAction: onCreate),
      for (final s in semesters) ...[
        Material(
          color: s['id'] == current['id']
              ? const Color(0xFFEFEDFF)
              : Colors.white,
          borderRadius: BorderRadius.circular(21),
          child: InkWell(
            onTap: () => onSelect(s),
            borderRadius: BorderRadius.circular(21),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.auto_stories_outlined,
                          color: CampusColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${s['name']}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (s['id'] == current['id'])
                        const Icon(
                          Icons.check_circle_rounded,
                          color: CampusColors.primary,
                          size: 23,
                        ),
                    ],
                  ),
                  const SizedBox(height: 17),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusPill(
                        '共${s['total_weeks']}周',
                        background: Colors.white.withValues(alpha: .7),
                        foreground: CampusColors.muted,
                      ),
                      if (s['id'] == current['id']) const StatusPill('当前学期'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '第一周周一  ${s['first_monday']}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      const SectionHeading('管理课表'),
      CampusPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.cloud_download_outlined,
                color: CampusColors.primary,
              ),
              title: const Text(
                '重新导入教务课表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                '先核对差异，再确认保存',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onImport,
            ),
            const Divider(height: 1, indent: 58, endIndent: 18),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.edit_calendar_outlined,
                color: Color(0xFF328774),
              ),
              title: const Text(
                '手工补充课程',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                '设置周次、节次和地点',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onManual,
            ),
          ],
        ),
      ),
    ],
  );
}
