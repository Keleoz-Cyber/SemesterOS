import 'app_controls.dart';
import 'app_sheet.dart';
import 'campus_theme.dart';
import 'package:flutter/material.dart';

/// Ordinary date/time fields stay on the page. Less common ways of recording
/// an incomplete notice are available on demand, without inventing a date.
class TimeInputOptions extends StatelessWidget {
  final String precision;
  final ValueChanged<String>? onChanged;
  final String exactValue;
  const TimeInputOptions({
    super.key,
    required this.precision,
    required this.onChanged,
    this.exactValue = 'exact',
  });

  Future<void> otherTime(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = await showAppSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHeading(title: '时间方式'),
            for (final entry in const {
              'week': '按学期周次',
              'range': '日期范围',
              'unknown': '暂不填写时间',
            }.entries)
              AppTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                selected: precision == entry.key,
                leading: Icon(switch (entry.key) {
                  'week' => Icons.date_range_outlined,
                  'range' => Icons.unfold_more_rounded,
                  _ => Icons.event_busy_outlined,
                }, color: CampusColors.teal),
                title: Text(entry.value),
                trailing: precision == entry.key
                    ? const Text(
                        '当前',
                        style: TextStyle(
                          fontSize: 12,
                          color: CampusColors.teal,
                        ),
                      )
                    : const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: CampusColors.muted,
                      ),
                onTap: () => Navigator.pop(context, entry.key),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (value != null && context.mounted) onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      AppTextButton.icon(
        onPressed: onChanged == null
            ? null
            : () => onChanged!(
                precision.startsWith('exact')
                    ? 'date'
                    : precision == 'date'
                    ? exactValue
                    : 'date',
              ),
        icon: Icon(
          precision.startsWith('exact')
              ? Icons.event_available_outlined
              : precision == 'date'
              ? Icons.more_time_rounded
              : Icons.calendar_today_outlined,
          size: 18,
          color: CampusColors.teal,
        ),
        label: Text(
          precision.startsWith('exact')
              ? '只记日期'
              : precision == 'date'
              ? '添加具体时刻'
              : '添加日期',
        ),
      ),
      AppTextButton.icon(
        onPressed: onChanged == null ? null : () => otherTime(context),
        icon: const Icon(
          Icons.tune_rounded,
          size: 18,
          color: CampusColors.muted,
        ),
        label: const Text('时间方式'),
      ),
    ],
  );
}

/// Legacy unknown/tentative values remain distinct in storage, but users only
/// need to indicate whether the arrangement is provisional.
class TentativeSwitch extends StatelessWidget {
  final String certainty;
  final ValueChanged<String>? onChanged;
  const TentativeSwitch({
    super.key,
    required this.certainty,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => AppSwitchRow(
    contentPadding: EdgeInsets.zero,
    title: const Text('暂定安排'),
    value: certainty == 'tentative',
    onChanged: onChanged == null
        ? null
        : (value) => onChanged!(value ? 'tentative' : 'formal'),
  );
}
