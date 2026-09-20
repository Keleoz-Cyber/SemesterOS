import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'dart:async';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_form.dart';
import 'item_widgets.dart';
import '../changes/changes_page.dart';
import '../media/drafts.dart';
import '../operations/operation_page.dart';

class CapturePage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  const CapturePage({
    super.key,
    required this.controller,
    required this.semester,
  });
  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  final text = TextEditingController();
  String referenceAt = DateTime.now().toUtc().toIso8601String();
  bool busy = false;
  String? error;
  Timer? autosave;
  bool completed = false;
  late final generation = widget.controller.api.generation;
  late final drafts = CaptureDrafts(
    widget.controller.cache,
    widget.controller.owner!,
    () => generation == widget.controller.api.generation,
  );
  String get draftKey => 'text:${widget.semester['id']}';
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final data = await drafts.read(draftKey);
    if (mounted &&
        generation == widget.controller.api.generation &&
        text.text.isEmpty &&
        data != null) {
      setState(() {
        text.text = data['text'] ?? '';
        referenceAt = data['reference_at'] ?? referenceAt;
      });
    }
  }

  Future<void> saveDraft() =>
      drafts.save(draftKey, {'text': text.text, 'reference_at': referenceAt});
  @override
  void dispose() {
    autosave?.cancel();
    if (!completed) saveDraft();
    text.dispose();
    super.dispose();
  }

  Future<void> openForm({Map<String, dynamic>? candidate}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ItemFormPage(
          controller: widget.controller,
          semester: widget.semester,
          candidate:
              candidate ??
              {
                'item': {'source_text': text.text},
              },
        ),
      ),
    );
    if (mounted && result == true) {
      completed = true;
      autosave?.cancel();
      await drafts.save(draftKey, null);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> parse() async {
    if (text.text.trim().isEmpty) {
      setState(() => error = '先写下想记录的事情');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final candidate = await widget.controller.parse(
        text.text.trim(),
        referenceAt,
      );
      if (!mounted) return;
      if ([
        'update_task',
        'update_reminder',
        'request_plan',
      ].contains(candidate['intent'])) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OperationPage(
              controller: widget.controller,
              initialText: text.text,
              referenceAt: referenceAt,
            ),
          ),
        );
        return;
      }
      if (candidate['intent'] == 'report_change') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangesPage(
              controller: widget.controller,
              initialText: text.text,
              initialReferenceAt: referenceAt,
            ),
          ),
        );
        return;
      }
      if (candidate['intent'] != 'create_item' || candidate['item'] == null) {
        setState(
          () => error =
              '${(candidate['questions'] as List? ?? []).join('；')}\n请明确一条事项；若是修改已有内容，可以进入下方修改入口。',
        );
        return;
      }
      await openForm(candidate: candidate);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseReference() async {
    final current = schoolTime(referenceAt);
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (time != null && mounted) {
      setState(
        () => referenceAt =
            '${date.toIso8601String().substring(0, 10)}T${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00+08:00',
      );
      await saveDraft();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文字快速记录')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CampusHero(
          eyebrow: '一句话记录',
          title: '把通知变成事项',
          subtitle: 'AI帮你整理\n你确认后再保存',
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('capture-text'),
          controller: text,
          onChanged: (_) {
            autosave?.cancel();
            autosave = Timer(
              const Duration(milliseconds: 350),
              () => saveDraft(),
            );
          },
          maxLines: 7,
          maxLength: 10000,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: '想记录什么？',
            hintText: '例如：9月25日23:59前交Java报告，预计3小时',
          ),
        ),
        TextButton.icon(
          onPressed: busy ? null : chooseReference,
          icon: const Icon(Icons.history),
          label: Text('原消息时间：${displayInstant(referenceAt)}'),
        ),
        const Text(
          '转贴旧通知时，请修改原消息时间，便于解释“明天”“下周五”。',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 16),
        const SoftNotice('这段文字和本学期的课程名称会发送给AI，用于整理事项。请只粘贴本次需要记录的内容。'),
        const SizedBox(height: 16),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 12),
                Text('AI正在整理事项、时间和提醒…'),
              ],
            ),
          ),
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: busy ? null : parse,
          child: const Text('让AI整理'),
        ),
        TextButton(
          onPressed: busy ? null : () => openForm(),
          child: const Text('直接手工填写，保留原文'),
        ),
        TextButton(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OperationPage(
                      controller: widget.controller,
                      initialText: text.text,
                      referenceAt: referenceAt,
                    ),
                  ),
                ),
          child: const Text('用这段文字修改已有事项 / 提醒'),
        ),
      ],
    ),
  );
}
