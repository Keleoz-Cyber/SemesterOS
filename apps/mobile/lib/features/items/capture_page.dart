import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
import 'items_controller.dart';
import 'item_form.dart';
import 'item_widgets.dart';

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
  @override
  void dispose() {
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
    if (mounted && result == true) Navigator.pop(context, true);
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
      if (candidate['intent'] != 'create_item' || candidate['item'] == null) {
        setState(
          () => error =
              '当前文字入口支持新增一条事项。${(candidate['questions'] as List? ?? []).join('；')}\n修改已有事项请从详情进入，多条通知请分开记录。',
        );
        return;
      }
      await openForm(candidate: candidate);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
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
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文字快速记录')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CampusHero(
          eyebrow: 'CAPTURE / 一句话记录',
          title: '把通知变成事项',
          subtitle: '先解析，再核对\n确认后才会保存',
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('capture-text'),
          controller: text,
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
        const SoftNotice('本次文字和当前学期课程候选会发送至DeepSeek进行解析。请只粘贴需要记录的通知内容。'),
        const SizedBox(height: 16),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                LinearProgressIndicator(),
                SizedBox(height: 12),
                Text('正在解析文字并核对字段…'),
              ],
            ),
          ),
        if (error != null) ...[
          SoftNotice(error!, warning: true),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: busy ? null : parse,
          child: const Text('解析并核对'),
        ),
        TextButton(
          onPressed: busy ? null : () => openForm(),
          child: const Text('直接手工填写，保留原文'),
        ),
      ],
    ),
  );
}
