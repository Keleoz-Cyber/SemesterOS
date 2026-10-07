import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/campus_theme.dart';
import '../items/item_widgets.dart';
import '../items/task_surfaces.dart';

Future<String?> showPlanBlock(
  BuildContext context,
  Map<String, dynamic> block, {
  bool conflict = false,
}) => showAppSheet<String>(
  context: context,
  builder: (sheet) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetHeading(
            title: '${block['title']}',
            closeLabel: '关闭安排详情',
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          TaskFactStrip(
            label: block['locked'] == true ? '已固定时间' : '学习时间',
            value: displayInterval(block['start_at'], block['end_at']),
            icon: block['locked'] == true
                ? Icons.lock_outline_rounded
                : Icons.schedule_rounded,
            accent: CampusColors.teal,
          ),
          if (conflict)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                '与其他安排重叠',
                style: TextStyle(color: CampusColors.warning),
              ),
            ),
          const SizedBox(height: 16),
          AppTile(
            title: const Text('查看任务'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(sheet);
              context.push('/items/${block['item_id']}');
            },
          ),
          if (DateTime.parse(block['end_at']).isAfter(DateTime.now())) ...[
            AppTile(
              title: Text(block['locked'] == true ? '允许调整时间' : '固定这段时间'),
              leading: Icon(
                block['locked'] == true
                    ? Icons.lock_open_rounded
                    : Icons.lock_outline_rounded,
              ),
              onTap: () => Navigator.pop(sheet, 'lock'),
            ),
            AppTile(
              title: const Text(
                '取消这段安排',
                style: TextStyle(color: CampusColors.error),
              ),
              leading: const Icon(
                Icons.event_busy_outlined,
                color: CampusColors.error,
              ),
              onTap: () => Navigator.pop(sheet, 'cancel'),
            ),
          ],
        ],
      ),
    ),
  ),
);
