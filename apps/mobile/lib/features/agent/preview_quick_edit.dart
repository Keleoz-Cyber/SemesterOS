import 'package:flutter/material.dart';
import '../../app/controller.dart' show schoolNow, schoolTime;
import '../../ui/app_controls.dart';
import '../../ui/app_text_entry_dialog.dart';
import '../../ui/app_date_time_picker.dart';
import '../notices/notice_fields.dart';
import 'agent_controller.dart';

class PreviewQuickEdit extends StatelessWidget {
  final AgentController controller;
  final Map<String, dynamic> run;
  const PreviewQuickEdit({
    super.key,
    required this.controller,
    required this.run,
  });
  Future<void> textField(BuildContext context, String key, String label) async {
    final after = run['preview']['after'] as Map;
    final edited = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => AppTextEntryDialog(
        title: '修改$label',
        confirmLabel: '更新预览',
        fields: [AppTextEntry(key, label, initial: '${after[key] ?? ''}')],
      ),
    );
    final value = edited?[key];
    if (value != null && controller.active) {
      await controller.editPreview(run, {key: value});
    }
  }

  Future<void> timeField(BuildContext context, {bool ending = false}) async {
    final time = Map<String, dynamic>.from(
      run['preview']['after']['time'] ?? {},
    );
    final at = time[ending ? 'end_at' : 'at'];
    final initial = at is String
        ? schoolTime(at)
        : time['date'] is String
        ? DateTime.parse(time['date'])
        : schoolNow();
    final picked = await showAppDateTimePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: ending ? '结束时间' : '开始或截止时间',
    );
    if (picked == null || !controller.active) return;
    final instant = DateTime.utc(
      picked.year,
      picked.month,
      picked.day,
      picked.hour,
      picked.minute,
    ).subtract(const Duration(hours: 8)).toIso8601String();
    await controller.editPreview(run, {
      'time': {
        'precision': 'exact',
        'meaning': time['meaning'] == 'deadline'
            ? 'deadline'
            : time['meaning'] == 'window'
            ? 'window'
            : 'start',
        'at': ending ? time['at'] : instant,
        'end_at': ending ? instant : time['end_at'],
        'expression': '',
      },
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = run['preview'] as Map;
    if (run['status'] != 'needs_confirmation' ||
        !{'event', 'item'}.contains(p['kind']) ||
        !{'create', 'update'}.contains(p['action'])) {
      return const SizedBox.shrink();
    }
    final after = p['after'] as Map, time = after['time'] as Map? ?? {};
    final before = p['previous_draft'] as Map?;
    final disabled =
        controller.busy ||
        controller.processing ||
        controller.uncertainDecisions.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (before != null) ...[
          const Text('本次调整', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final key in (p['edited_fields'] as List? ?? []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                key == 'time'
                    ? '${noticeTime(before[key])} → ${noticeTime(after[key])}'
                    : '${const {'title': '名称', 'location': '地点'}[key]}：${before[key] ?? '未填写'} → ${after[key] == '' ? '未填写' : after[key]}',
              ),
            ),
        ],
        Wrap(
          spacing: 4,
          children: [
            AppTextButton(
              onPressed: disabled
                  ? null
                  : () => textField(context, 'title', '名称'),
              child: const Text('改名称'),
            ),
            AppTextButton(
              onPressed: disabled
                  ? null
                  : () => textField(context, 'location', '地点'),
              child: const Text('改地点'),
            ),
            AppTextButton(
              onPressed: disabled ? null : () => timeField(context),
              child: const Text('改时间'),
            ),
            if (p['kind'] == 'event' && time['at'] != null)
              AppTextButton(
                onPressed: disabled
                    ? null
                    : () => timeField(context, ending: true),
                child: Text(time['end_at'] == null ? '补结束时间' : '改结束时间'),
              ),
            if (time['end_at'] != null)
              AppTextButton(
                onPressed: disabled
                    ? null
                    : () => controller.editPreview(run, {
                        'time': {...time, 'end_at': null},
                      }),
                child: const Text('结束时间未定'),
              ),
          ],
        ),
      ],
    );
  }
}
