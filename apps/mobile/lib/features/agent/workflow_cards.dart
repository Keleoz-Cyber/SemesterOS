import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/motion.dart' show AppMotion;
import '../../core/api.dart' show userError;
import '../items/items_controller.dart';
import '../planning/schedule_page.dart';
import '../planning/schedule_setup_actions.dart';

class ForwardingDraftCard extends StatefulWidget {
  final String text;
  const ForwardingDraftCard({super.key, required this.text});
  @override
  State<ForwardingDraftCard> createState() => _ForwardingDraftCardState();
}

class _ForwardingDraftCardState extends State<ForwardingDraftCard> {
  late final text = TextEditingController(text: widget.text);
  bool copied = false;
  @override
  void didUpdateWidget(covariant ForwardingDraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && text.text == oldWidget.text) {
      text.text = widget.text;
      copied = false;
    }
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: CampusColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('转发文案', style: TextStyle(fontWeight: FontWeight.w700)),
        const Divider(height: 24),
        FTextField(
          control: FTextFieldControl.managed(
            controller: text,
            onChange: (_) {
              if (copied) setState(() => copied = false);
            },
          ),
          minLines: 3,
          maxLines: 9,
          style: FTextFieldStyleDelta.delta(
            border: FVariants(InputBorder.none, variants: {}),
            color: FVariants(Colors.transparent, variants: {}),
            contentPadding: const EdgeInsetsGeometryDelta.value(
              EdgeInsets.zero,
            ),
            contentTextStyle: FVariants(
              TextStyle(
                fontSize: 16,
                height: 1.6,
                color: CampusColors.ink,
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
              ),
              variants: {},
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: AppTextButton.icon(
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text.text));
              if (mounted) setState(() => copied = true);
            },
            label: AnimatedSwitcher(
              duration: AppMotion.allowed(context)
                  ? const Duration(milliseconds: 180)
                  : Duration.zero,
              child: Text(copied ? '已复制' : '复制文案', key: ValueKey(copied)),
            ),
          ),
        ),
      ],
    ),
  );
}

class ScheduleSetupCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final ItemsController controller;
  final Future<void> Function() onReady;
  const ScheduleSetupCard({
    super.key,
    required this.data,
    required this.controller,
    required this.onReady,
  });
  @override
  State<ScheduleSetupCard> createState() => _ScheduleSetupCardState();
}

class _ScheduleSetupCardState extends State<ScheduleSetupCard> {
  late final tasks = widget.controller
      .rows(widget.data['tasks'])
      .where((t) => t['can_schedule'] != false)
      .toList();
  final inputs = <String, TextEditingController>{};
  bool busy = false, used = false;
  String? error;
  @override
  void initState() {
    super.initState();
    for (final t in tasks) {
      inputs['${t['id']}'] = TextEditingController(
        text:
            '${t['remaining_minutes'] ?? t['duration_suggestion_minutes'] ?? 45}',
      );
    }
  }

  @override
  void dispose() {
    for (final v in inputs.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> use() async {
    final values = <String, int>{};
    for (final t in tasks) {
      final n = int.tryParse(inputs['${t['id']}']!.text);
      if (n == null || n < 1) {
        setState(() => error = '请填写预计分钟数');
        return;
      }
      values['${t['id']}'] = n;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await confirmScheduleSetup(widget.controller, widget.data, tasks, values);
      if (!mounted) return;
      setState(() => used = true);
      await widget.onReady();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = widget.data['availability'];
    final weekly = widget.controller.rows(hours?['candidate']?['weekly']);
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CampusColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            used ? '预计用时已确认' : '核对预计用时',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (!used) ...[
            for (final t in tasks)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final duration = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Semantics(
                            label: '${t['title']}预计用时',
                            child: AppField(
                              controller: inputs['${t['id']}'],
                              enabled: !busy,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('分钟', style: TextStyle(fontSize: 14)),
                      ],
                    );
                    final title = Text('${t['title']}');
                    if (constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(16) > 21) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 6), duration],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 12),
                        duration,
                      ],
                    );
                  },
                ),
              ),
            if (hours?['needs_confirmation'] == true) ...[
              const SizedBox(height: 12),
              const Text(
                '建议学习时段',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final r in weekly)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '周${'一二三四五六日'[(r['weekday'] as int) - 1]}  ${r['start']}—${r['end']}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                ),
            ],
            if (error != null)
              Text(error!, style: const TextStyle(color: CampusColors.warning)),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              children: [
                AppTextButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SchedulePage(controller: widget.controller),
                          ),
                        ),
                  child: const Text('调整'),
                ),
                AppButton(
                  onPressed: busy || tasks.isEmpty ? null : use,
                  child: Text(busy ? '正在生成…' : '生成安排'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
