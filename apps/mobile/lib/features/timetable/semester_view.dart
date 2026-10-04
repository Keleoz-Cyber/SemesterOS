import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart' show SectionHeading;
import '../../ui/date_labels.dart' show studentDate;

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
      SectionHeading('学期列表', action: '新建学期', onAction: onCreate),
      Material(
        color: CampusColors.blueSoft,
        borderRadius: BorderRadius.circular(20),
        child: AppTile(
          contentPadding: const EdgeInsets.all(20),
          onTap: () => onSelect(current),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前学期',
                style: TextStyle(
                  fontSize: 12,
                  color: CampusColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${current['name']}',
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第1周 ${studentDate(DateTime.parse(current['first_monday']))}起',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.muted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${current['total_weeks']} 周${(current['periods'] as List? ?? []).isEmpty ? '' : ' · 每天 ${(current['periods'] as List).length} 节'}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CampusColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (semesters.any((s) => s['id'] != current['id'])) ...[
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.only(bottom: 4, top: 4),
          child: Text(
            '其他学期',
            style: TextStyle(fontSize: 13, color: CampusColors.muted),
          ),
        ),
        for (final s in semesters.where((s) => s['id'] != current['id']))
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CampusColors.line)),
            ),
            child: AppTile(
              onTap: () => onSelect(s),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 2,
              ),
              title: Text(
                '${s['name']}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${s['total_weeks']} 周 · ${studentDate(DateTime.parse(s['first_monday']))}起',
                  style: const TextStyle(
                    fontSize: 13,
                    color: CampusColors.muted,
                  ),
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: CampusColors.muted,
              ),
            ),
          ),
      ],
      if (onEdit != null) ...[
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
      ],
      const SectionHeading('管理课表'),
      Column(
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
            subtitle: const Text('先核对差异，再确认保存', style: TextStyle(fontSize: 12)),
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
            subtitle: const Text('设置周次、节次和地点', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onManual,
          ),
        ],
      ),
      if (onDelete != null) ...[
        const SizedBox(height: 24),
        const Divider(height: 1),
        AppTile(
          leading: const Icon(
            Icons.delete_outline_rounded,
            color: CampusColors.muted,
          ),
          title: const Text(
            '删除当前学期',
            style: TextStyle(fontSize: 14, color: CampusColors.muted),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: CampusColors.muted,
          ),
          onTap: onDelete,
        ),
      ],
    ],
  );
}
