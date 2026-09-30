import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'dart:math';
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'risk_widgets.dart';
import 'plan_change_confirmation.dart';

class ProgressPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> item;
  const ProgressPage({super.key, required this.controller, required this.item});
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController remaining;
  final actual = TextEditingController(), note = TextEditingController();
  bool busy = false;
  String? error;
  List<Map<String, dynamic>>? history;
  @override
  void initState() {
    super.initState();
    remaining = TextEditingController(
      text: widget.item['remaining_minutes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    remaining.dispose();
    actual.dispose();
    note.dispose();
    super.dispose();
  }

  String? number(String? value, {bool required = false}) {
    if (value!.trim().isEmpty) return required ? '请确认还需要多少分钟' : null;
    final n = int.tryParse(value);
    return n == null || n < 0 || n > 525600 ? '请输入0至525600之间的整数分钟' : null;
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final input = {
        'expected_version': widget.item['version'],
        'remaining_minutes': int.parse(remaining.text),
        'actual_minutes': actual.text.trim().isEmpty
            ? null
            : int.parse(actual.text),
        'note': note.text.trim(),
      };
      final preview = await widget.controller.previewProgress(
        widget.item['id'],
        input,
      );
      if (!mounted) return;
      final complete = preview['will_complete'] == true;
      final blocks = List<Map<String, dynamic>>.from(
        preview['affected_blocks'] ?? [],
      );
      final selection = blocks.isEmpty
          ? null
          : await confirmPlanChange(
              context,
              title: complete ? '确认任务已经完成' : '确认现在还需要多久',
              message:
                  '原来还需：${minutesLabel(preview['before_remaining_minutes'])}\n现在还需：${minutesLabel(preview['after_remaining_minutes'])}\n实际投入单独记录。',
              confirmLabel: complete ? '确认完成并停止提醒' : '确认更新进度',
              blocks: blocks,
              cancelAll: complete,
              remaining: input['remaining_minutes'] as int,
            );
      if (!mounted) return;
      final yes = blocks.isNotEmpty
          ? selection != null
          : await showDialog<bool>(
              context: context,
              builder: (context) => AppDialog(
                title: Text(complete ? '确认任务已经完成' : '确认现在还需要多久'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.item['title']}'),
                      const SizedBox(height: 12),
                      Text(
                        '原来还需：${minutesLabel(preview['before_remaining_minutes'])}\n现在还需：${minutesLabel(preview['after_remaining_minutes'])}',
                      ),
                      if (preview['actual_minutes'] != null)
                        Text(
                          '本次实际用时：${minutesLabel(preview['actual_minutes'])}',
                        ),
                      const SizedBox(height: 12),
                      Text(complete ? '确认后标记完成，并停用未触发提醒。' : ''),
                    ],
                  ),
                ),
                actions: [
                  AppTextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('返回修改'),
                  ),
                  AppButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(complete ? '确认完成并停止提醒' : '确认更新进度'),
                  ),
                ],
              ),
            );
      if (yes != true || !mounted) return;
      await widget.controller.saveProgress(
        widget.item['id'],
        {
          ...input,
          'expected_revision': preview['base_revision'],
          'confirm_complete': complete,
          ...?selection,
        },
        idempotencyKey:
            'progress-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('更新任务进度')),
    bottomNavigationBar: ActionFooter(
      label: busy ? '正在核对…' : '确认本次进度',
      icon: Icons.fact_check_outlined,
      onPressed: busy ? null : save,
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RecordHeading(
            label: '任务进度',
            icon: Icons.track_changes_rounded,
            title: '${widget.item['title']}',
          ),
          EditorSection(
            title: '剩余工作',
            icon: Icons.timelapse_rounded,
            children: [
              if (widget.item['remaining_minutes'] != null)
                RecordFact(
                  label: '上次记录',
                  value: minutesLabel(widget.item['remaining_minutes']),
                  icon: Icons.history_rounded,
                ),
              const SizedBox(height: 8),
              AppFormField(
                key: const Key('progress-remaining'),
                controller: remaining,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '预计剩余（分钟）',
                  helperText: '填0表示已完成',
                ),
                validator: (v) => number(v, required: true),
              ),
            ],
          ),
          EditorSection(
            title: '本次用时',
            icon: Icons.timer_outlined,
            accent: CampusColors.teal,
            children: [
              AppFormField(
                key: const Key('progress-actual'),
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '实际用时（分钟，选填）'),
                validator: number,
              ),
              const SizedBox(height: 16),
              AppFormField(
                controller: note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: '备注（选填）'),
              ),
            ],
          ),
          if (error != null) ...[
            SoftNotice(error!, warning: true),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
          AppDisclosure(
            title: const Text('查看进度记录'),
            onExpansionChanged: (open) async {
              if (!open) return;
              try {
                final data = await widget.controller.api.request(
                  'GET',
                  '/items/${widget.item['id']}/progress',
                );
                if (mounted) {
                  setState(
                    () => history = List<Map<String, dynamic>>.from(data),
                  );
                }
              } catch (e) {
                if (mounted) setState(() => error = userError(e));
              }
            },
            children: [
              if (history == null)
                const Text('正在读取…')
              else if (history!.isEmpty)
                const Text('尚无单独记录的进度更新'),
              for (final row in history ?? <Map<String, dynamic>>[])
                AppTile(
                  title: Text(
                    '${minutesLabel(row['before_remaining_minutes'])} → ${minutesLabel(row['remaining_minutes'])}',
                  ),
                  subtitle: Text(
                    '${row['undone'] == true ? '已撤销，不计入统计\n' : ''}${displayInstant(row['created_at'])}\n实际投入：${row['actual_minutes'] == null ? '未记录' : minutesLabel(row['actual_minutes'])}\n${row['note']}',
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
