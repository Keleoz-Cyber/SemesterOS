import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../core/api.dart';
import '../../core/device_surfaces.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_text_entry_dialog.dart';

class PersonalDataPage extends StatefulWidget {
  final AppController controller;
  const PersonalDataPage({super.key, required this.controller});
  @override
  State<PersonalDataPage> createState() => _PersonalDataPageState();
}

class _PersonalDataPageState extends State<PersonalDataPage> {
  bool busy = false;
  String? message;
  late final generation = widget.controller.api.generation;
  bool get valid => mounted && generation == widget.controller.api.generation;
  Future<void> export() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final data = await widget.controller.api.request('GET', '/me/export');
      if (!valid) return;
      final saved = await DeviceSurfaces.export(
        Map<String, dynamic>.from(data),
      );
      if (valid) setState(() => message = saved ? '数据已导出到你选择的位置' : '已取消导出');
    } catch (e) {
      if (valid) setState(() => message = userError(e));
    } finally {
      if (valid) setState(() => busy = false);
    }
  }

  Future<void> erase() async {
    final body = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const AppTextEntryDialog(
        title: '删除账号和全部数据',
        confirmLabel: '删除账号',
        description: '课程、日程、任务、对话及附件会被删除，无法撤销。建议先导出需要保留的数据。',
        fields: [
          AppTextEntry('password', '账号密码', obscure: true, maxLength: 200),
          AppTextEntry('confirmation', '输入“删除我的账号”'),
        ],
      ),
    );
    if (body == null || !valid) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.controller.api.request('POST', '/me/erase', data: body);
      if (!valid) return;
      await widget.controller.logout(remote: false);
    } catch (e) {
      if (valid) setState(() => message = userError(e));
    } finally {
      if (valid) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据与隐私')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '你的资料如何使用',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '课表、日程和任务保存在你的账号下。本机缓存用于离线查看。提交给助手的文字以及图片、录音识别结果会用于理解本次请求；读取剪贴板后仍由你决定是否发送。',
        ),
        const SizedBox(height: 12),
        const Text(
          '通知原文和后续补充用于核对安排。删除对话不会删除你已确认保存的日程；删除来源附件也不会取消这些安排。附件可在来源详情中删除。',
        ),
        const SizedBox(height: 12),
        const Text(
          '导出文件包含个人记录和未删除的对话文字，不包含登录凭证。服务器维护备份按部署的保留策略轮换；账号删除不会立即改写已有备份。',
        ),
        const SizedBox(height: 24),
        AppTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('导出个人数据'),
          subtitle: const Text('JSON文件，可自行选择保存位置'),
          onTap: busy ? null : export,
        ),
        AppTile(
          leading: const Icon(Icons.delete_forever_outlined),
          title: const Text('删除账号'),
          subtitle: const Text('删除账号下的所有记录和附件'),
          onTap: busy ? null : erase,
        ),
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
      ],
    ),
  );
}

class FeedbackPage extends StatefulWidget {
  final AppController controller;
  const FeedbackPage({super.key, required this.controller});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final description = TextEditingController(),
      expected = TextEditingController();
  String category = 'other';
  bool busy = false;
  String? message;
  late final generation = widget.controller.api.generation;
  @override
  void dispose() {
    description.dispose();
    expected.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (description.text.trim().length < 3) {
      setState(() => message = '请写下具体遇到了什么');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.controller.api.request(
        'POST',
        '/me/feedback',
        data: {
          'category': category,
          'description': description.text.trim(),
          'expected': expected.text.trim(),
          'app_version': '1.1.1+12',
        },
      );
      if (mounted && generation == widget.controller.api.generation) {
        setState(() => message = '反馈已提交');
        description.clear();
        expected.clear();
      }
    } catch (e) {
      if (mounted) setState(() => message = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('反馈问题')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in const {
              'wrong_answer': '理解错误',
              'save': '保存问题',
              'reminder': '提醒问题',
              'interface': '界面问题',
              'other': '其他',
            }.entries)
              AppFilterChip(
                label: Text(e.value),
                selected: category == e.key,
                onSelected: (_) => setState(() => category = e.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: description,
          maxLines: 5,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: '你做了什么，出现了什么问题'),
        ),
        TextField(
          controller: expected,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: '你希望怎样处理（可不填）'),
        ),
        const Text('只提交你填写的内容，不会自动附上聊天、录音或账号密码。'),
        const SizedBox(height: 16),
        AppButton(onPressed: busy ? null : submit, child: const Text('提交反馈')),
        if (message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(message!)),
      ],
    ),
  );
}
