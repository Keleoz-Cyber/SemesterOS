import 'app_controls.dart';
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
    final value = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '通知没有写具体日期？',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ),
            for (final entry in const {
              'week': '按学期周次填写',
              'range': '填写一段日期范围',
              'unknown': '暂不填写时间',
            }.entries)
              AppTile(
                title: Text(entry.value),
                trailing: precision == entry.key
                    ? const Icon(Icons.check)
                    : null,
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
    children: [
      AppTextButton(
        onPressed: onChanged == null
            ? null
            : () => onChanged!(
                precision.startsWith('exact') ? 'date' : exactValue,
              ),
        child: Text(
          precision.startsWith('exact')
              ? '只记日期'
              : precision == 'date'
              ? '添加具体时刻'
              : '添加日期和时间',
        ),
      ),
      AppTextButton(
        onPressed: onChanged == null ? null : () => otherTime(context),
        child: const Text('其他时间写法'),
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
    value: certainty != 'formal',
    onChanged: onChanged == null
        ? null
        : (value) => onChanged!(value ? 'tentative' : 'formal'),
  );
}
