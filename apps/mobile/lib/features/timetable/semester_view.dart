import '../../ui/app_controls.dart';
import '../../ui/detail_widgets.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';

class SemesterView extends StatelessWidget {
  final List<Map<String, dynamic>> semesters;
  final Map<String, dynamic> current;
  final void Function(Map<String, dynamic>) onSelect;
  final VoidCallback onCreate, onImport, onManual;
  final VoidCallback? onEdit, onDelete;
  const SemesterView({
    super.key,
    required this.semesters,
    required this.current,
    required this.onSelect,
    required this.onCreate,
    required this.onImport,
    required this.onManual,
    this.onEdit,
    this.onDelete,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const RecordHeading(
        title: '我的学期',
        label: '学期与课表',
        icon: Icons.auto_stories_outlined,
        subtitle: '切换学期后，课表、事项和计划会一起切换。',
      ),
      SectionHeading('学期列表', action: '新建学期', onAction: onCreate),
      for (final s in semesters) ...[
        Material(
          color: s['id'] == current['id']
              ? CampusColors.blueSoft
              : CampusColors.surface,
          borderRadius: BorderRadius.circular(14),
          child: AppTile(
            contentPadding: const EdgeInsets.all(16),
            onTap: () => onSelect(s),
            selected: s['id'] == current['id'],
            leading: const Icon(
              Icons.auto_stories_outlined,
              color: CampusColors.primary,
            ),
            title: Text(
              '${s['name']}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '共${s['total_weeks']}周 · 第一周周一 ${s['first_monday']}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                  if (s['id'] == current['id'])
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        '当前学期',
                        style: TextStyle(
                          fontSize: 12,
                          color: CampusColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing: Icon(
              s['id'] == current['id']
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: s['id'] == current['id']
                  ? CampusColors.primary
                  : CampusColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      if (onEdit != null || onDelete != null) ...[
        const SectionHeading('学期设置'),
        if (onEdit != null)
          AppTile(
            leading: const Icon(
              Icons.edit_calendar_outlined,
              color: CampusColors.primary,
            ),
            title: const Text('修改校历与节次'),
            subtitle: const Text('修正开学日期、周数或上课时间'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onEdit,
          ),
        if (onDelete != null)
          AppTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: CampusColors.error,
            ),
            title: const Text(
              '删除当前学期',
              style: TextStyle(color: CampusColors.error),
            ),
            subtitle: const Text('先查看会一并删除的内容'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onDelete,
          ),
      ],
      const SectionHeading('管理课表'),
      CampusPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            AppTile(
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
            AppTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.edit_calendar_outlined,
                color: CampusColors.teal,
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
