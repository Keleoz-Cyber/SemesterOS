import '../../ui/app_controls.dart';
import 'hold_voice_button.dart';
import '../calendar/event_form.dart';
import '../../core/api.dart' show userError;
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../items/items_controller.dart';
import '../items/item_form.dart';
import '../items/item_widgets.dart';
import '../changes/changes_page.dart';
import 'drafts.dart';
import 'media_input.dart';
import 'source_view.dart';
import '../operations/operation_page.dart';

String sourceState(String? state) => switch (state) {
  'queued' => '等待识别',
  'running' => '正在识别',
  'recognized' => '识别完成，待核对',
  'failed' => '识别未完成',
  'cancelled' => '已取消',
  _ => '已保存来源',
};
String mediaKey() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class MediaCapturePage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String kind;
  final MediaInput? input;
  final bool returnSource;
  final String? initialAudioPath;
  const MediaCapturePage({
    super.key,
    required this.controller,
    required this.semester,
    this.kind = 'image',
    this.input,
    this.returnSource = false,
    this.initialAudioPath,
  });
  @override
  State<MediaCapturePage> createState() => _MediaCapturePageState();
}

class _MediaCapturePageState extends State<MediaCapturePage>
    with WidgetsBindingObserver {
  MediaInput? imageInput;
  MediaInput get input => imageInput ??= widget.kind == 'audio'
      ? DeviceMediaInput()
      : widget.input ?? DeviceMediaInput();
  late final generation = widget.controller.api.generation;
  late final owner = widget.controller.owner!;
  late final drafts = CaptureDrafts(widget.controller.cache, owner, () => same);
  final text = TextEditingController();
  late String kind = widget.kind;
  String key = mediaKey(),
      referenceAt = DateTime.now().toUtc().toIso8601String();
  String? local, error;
  Map<String, dynamic>? source;
  List<Map<String, dynamic>> recent = [];
  bool busy = false,
      recording = false,
      dirty = false,
      loading = false,
      finished = false,
      restored = false;
  late bool foreground;
  int op = 0, audioEpoch = 0;
  Timer? poll, autosave;
  bool get same =>
      generation == widget.controller.api.generation &&
      owner == widget.controller.owner &&
      widget.semester['id'] == widget.controller.semesterId;
  String get legacyDraftKey => 'media:${widget.semester['id']}';
  String get draftKey => '$legacyDraftKey:$kind';
  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    foreground =
        lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(accountChanged);
    restore();
    poll = Timer.periodic(const Duration(seconds: 2), (_) => checkJob());
  }

  void accountChanged() {
    if (!same) {
      op++;
      autosave?.cancel();
      imageInput?.dispose();
      if (mounted) {
        setState(() {
          source = null;
          local = null;
          text.clear();
          recording = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (!foreground) audioEpoch++;
  }

  @override
  void dispose() {
    if (same && restored && !finished) saveDraft().catchError((_) {});
    op++;
    poll?.cancel();
    autosave?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(accountChanged);
    imageInput?.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> saveDraft({bool picking = false}) => drafts.save(draftKey, {
    'kind': kind,
    'local': local,
    'key': key,
    'source': source,
    'text': text.text,
    'reference_at': referenceAt,
    'dirty': dirty,
    'picking': picking,
  });
  void textChanged(String value) {
    setState(() => dirty = true);
    autosave?.cancel();
    autosave = Timer(
      const Duration(milliseconds: 350),
      () => saveDraft().catchError((_) {
        if (mounted) setState(() => error = '本机草稿未保存，请保留原文后重试');
      }),
    );
  }

  Future<void> restore() async {
    final stamp = op;
    final allowAutomaticCapture = foreground;
    final entryEpoch = audioEpoch;
    try {
      var draft = await drafts.read(draftKey);
      if (!mounted || !same || stamp != op) return;
      if (draft == null) {
        final legacy = await drafts.read(legacyDraftKey);
        if (!mounted || !same || stamp != op) return;
        if (legacy?['kind'] == kind) {
          await drafts.save(draftKey, legacy);
          await drafts.save(legacyDraftKey, null);
          draft = legacy;
        }
      }
      if (!mounted || !same || stamp != op) return;
      setState(() => restored = true);
      final savedDraft = draft;
      if (widget.initialAudioPath != null) {
        setState(() => busy = true);
        try {
          await adopt(widget.initialAudioPath!, 'audio', stamp);
        } finally {
          if (mounted && same && stamp == op) setState(() => busy = false);
        }
        if (mounted && same && stamp == op) await uploadAndRecognize();
      } else if (savedDraft != null) {
        setState(() {
          local = savedDraft['local'];
          key = savedDraft['key'] ?? key;
          source = savedDraft['source'] == null
              ? null
              : Map<String, dynamic>.from(savedDraft['source']);
          text.text = savedDraft['text'] ?? '';
          referenceAt = savedDraft['reference_at'] ?? referenceAt;
          dirty = savedDraft['dirty'] == true;
        });
        if (savedDraft['picking'] == true) {
          final file = await input.image(recover: true);
          if (file != null && mounted && same && stamp == op) {
            await adopt(file, 'image', stamp);
            if (widget.returnSource && mounted && same && stamp == op) {
              await uploadAndRecognize();
            }
          }
        }
      } else if (widget.returnSource &&
          allowAutomaticCapture &&
          foreground &&
          entryEpoch == audioEpoch) {
        if (kind == 'image') {
          await pickImage();
        }
      }
      if (!widget.returnSource) await loadRecent();
      await checkJob(force: true);
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  Future<void> loadRecent() async {
    try {
      final r = await widget.controller.api.request(
        'GET',
        '/semesters/${widget.semester['id']}/sources',
      );
      if (mounted && same) setState(() => recent = widget.controller.rows(r));
    } catch (_) {
      if (mounted && same) setState(() => error = '暂时加载不了上传记录，你可以继续编辑本机草稿');
    }
  }

  Future<void> adopt(String path, String type, int stamp) async {
    if (!mounted || !same || stamp != op) return;
    final file = File(path);
    final limit = (type == 'image' ? 10 : 20) * 1024 * 1024;
    if (await file.length() > limit) {
      throw Exception(type == 'image' ? '图片超过10MB，请先裁剪' : '录音超过20MB，请缩短');
    }
    final folder = await CaptureDrafts.folder(owner);
    await folder.create(recursive: true);
    final saved = await file.copy(
      '${folder.path}/${mediaKey()}.${type == 'audio' ? 'wav' : 'image'}',
    );
    if (!mounted || !same || stamp != op) {
      await saved.delete();
      return;
    }
    setState(() {
      kind = type;
      local = saved.path;
      source = null;
      key = mediaKey();
      text.clear();
      dirty = false;
      error = null;
    });
    await saveDraft();
  }

  Future<void> pickImage() async {
    if (!same || busy || recording) return;
    final stamp = ++op;
    var selected = false;
    setState(() => busy = true);
    try {
      await saveDraft(picking: true);
      if (!mounted || !same || stamp != op) return;
      final file = await input.image();
      if (!mounted || !same || stamp != op) return;
      if (file != null) {
        await adopt(file, 'image', stamp);
        selected = true;
      }
      await saveDraft();
    } catch (e) {
      if (mounted && same && stamp == op) setState(() => error = userError(e));
    } finally {
      if (mounted && stamp == op) setState(() => busy = false);
    }
    if (selected && mounted && same && stamp == op) {
      await uploadAndRecognize();
    }
  }

  Future<void> recorded(String path) async {
    if (!mounted || !same || busy) return;
    final stamp = ++op;
    setState(() => busy = true);
    try {
      await adopt(path, 'audio', stamp);
    } catch (e) {
      if (mounted && same && stamp == op) setState(() => error = userError(e));
      return;
    } finally {
      if (mounted && stamp == op) setState(() => busy = false);
    }
    if (mounted && same && stamp == op) await uploadAndRecognize();
  }

  Future<void> checkJob({bool force = false}) async {
    if (!same ||
        source == null ||
        loading ||
        busy ||
        (!force && !['queued', 'running'].contains(source!['status']))) {
      return;
    }
    loading = true;
    final stamp = op, id = source!['id'];
    try {
      final r = Map<String, dynamic>.from(
        await widget.controller.api.request('GET', '/sources/$id'),
      );
      if (!mounted || !same || stamp != op || source?['id'] != id) return;
      if (dirty && r['version'] != source!['version']) {
        setState(() => error = '这份内容在其他地方被修改了。本机文字已保留，请从上传记录打开最新内容再保存。');
        return;
      }
      setState(() {
        source = r;
        if (!dirty) {
          text.text = r['text'] ?? '';
          referenceAt = r['reference_at'];
        }
        if (r['status'] == 'failed') {
          error =
              '识别未完成，可重试或手工校对文字。${r['error_code'] == 'MODEL_OR_FILE_MISSING' ? '识别服务暂不可用，请稍后重试。' : ''}';
        }
      });
      await saveDraft();
    } catch (_) {
      if (mounted && same && stamp == op) {
        setState(() => error = '暂时无法获取识别状态，网络恢复后会继续检查');
      }
    } finally {
      loading = false;
    }
  }

  Future<void> uploadAndRecognize() async {
    if (!same || local == null && source == null) return;
    final stamp = ++op;
    var reconcile = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (source == null) {
        final data = await File(local!).readAsBytes();
        if (!mounted || !same || stamp != op) return;
        final r = Map<String, dynamic>.from(
          await widget.controller.api.request(
            'POST',
            '/semesters/${widget.semester['id']}/sources?kind=$kind',
            data: data,
            contentType: 'application/octet-stream',
            idempotencyKey: key,
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        if (!mounted || !same || stamp != op) return;
        setState(() => source = r);
        await saveDraft();
      }
      if (!mounted || !same || stamp != op) return;
      final r = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'POST',
          '/sources/${source!['id']}/recognize',
          data: {'expected_version': source!['version']},
        ),
      );
      if (!mounted || !same || stamp != op) return;
      setState(() {
        source = r;
        dirty = false;
        text.text = r['text'] ?? '';
        referenceAt = r['reference_at'] ?? referenceAt;
      });
      await saveDraft();
      if (!widget.returnSource) await loadRecent();
    } catch (e) {
      reconcile = true;
      if (mounted && same && stamp == op) setState(() => error = userError(e));
    } finally {
      if (mounted && stamp == op) setState(() => busy = false);
    }
    if (reconcile && mounted && same && stamp == op) {
      await loadRecent();
      await checkJob(force: true);
    }
  }

  Future<void> cancel() async {
    final stamp = ++op;
    setState(() => busy = false);
    if (source != null) {
      try {
        final r = Map<String, dynamic>.from(
          await widget.controller.api.request(
            'POST',
            '/sources/${source!['id']}/cancel',
            data: {'expected_version': source!['version']},
          ),
        );
        if (mounted && same && stamp == op) setState(() => source = r);
      } catch (e) {
        if (mounted && same) setState(() => error = userError(e));
      }
    }
    await saveDraft();
  }

  Future<void> saveText() async {
    if (source == null) throw Exception('请先上传来源，或改用文字快速记录');
    final id = source!['id'],
        stamp = op,
        content = text.text,
        reference = referenceAt;
    final r = Map<String, dynamic>.from(
      await widget.controller.api.request(
        'PATCH',
        '/sources/$id',
        data: {
          'expected_version': source!['version'],
          'text': content,
          'reference_at': reference,
        },
      ),
    );
    if (!mounted || !same || op != stamp || source?['id'] != id) return;
    setState(() {
      source = r;
      if (text.text == content && referenceAt == reference) {
        referenceAt = r['reference_at'];
        dirty = false;
      }
    });
    await saveDraft();
  }

  Future<void> saveOnly() async {
    if (!same) return;
    setState(() => busy = true);
    try {
      await saveText();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> selectSource(Map<String, dynamic> row) async {
    if (dirty) {
      await saveOnly();
      if (dirty && mounted) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AppDialog(
            title: const Text('打开已保存的内容？'),
            content: const Text('当前文字还没保存。继续打开会替换它；你也可以返回，先复制或保存当前文字。'),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑当前文字'),
              ),
              AppButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放弃当前修改并打开'),
              ),
            ],
          ),
        );
        if (discard != true) return;
      }
    }
    if (!mounted || !same) return;
    op++;
    setState(() {
      source = row;
      kind = row['kind'];
      local = null;
      text.text = row['text'];
      referenceAt = row['reference_at'];
      dirty = false;
      error = null;
    });
    await saveDraft();
    await checkJob(force: true);
  }

  Future<void> parse({bool manual = false}) async {
    if (!same) return;
    final stamp = ++op;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (source != null || !manual) await saveText();
      if (!mounted || !same || stamp != op) return;
      if (widget.returnSource && !manual) {
        if (dirty || source == null) throw Exception('文字还没保存，请重试');
        final result = Map<String, dynamic>.from(source!);
        autosave?.cancel();
        await drafts.save(draftKey, null);
        if (!mounted || !same || stamp != op) return;
        finished = true;
        Navigator.pop(context, result);
        return;
      }
      Map<String, dynamic>? candidate;
      if (!manual) {
        candidate = Map<String, dynamic>.from(
          await widget.controller.api.request(
            'POST',
            '/capture/text',
            data: {
              'semester_id': widget.semester['id'],
              'text': text.text,
              'reference_at': referenceAt,
              if (source != null) 'source_id': source!['id'],
              'source_version': source!['version'],
            },
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        if (!mounted || !same || stamp != op) return;
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
                sourceId: source!['id'],
                sourceVersion: source!['version'],
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
                initialSourceId: source!['id'],
                initialReferenceAt: referenceAt,
              ),
            ),
          );
          return;
        }
        if (!((candidate['intent'] == 'create_item' &&
                candidate['item'] != null) ||
            (candidate['intent'] == 'create_event' &&
                candidate['event'] != null))) {
          throw Exception(
            '请拆成一条通知或补充信息：${(candidate['questions'] as List? ?? []).join('；')}',
          );
        }
      }
      if (!mounted || !same || stamp != op) return;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => candidate?['intent'] == 'create_event'
              ? EventFormPage(
                  controller: widget.controller,
                  semester: widget.semester,
                  candidate: candidate,
                )
              : ItemFormPage(
                  kind: 'task',
                  controller: widget.controller,
                  semester: widget.semester,
                  candidate:
                      candidate ??
                      {
                        'item': {
                          'source_text': text.text,
                          if (source != null) 'source_id': source!['id'],
                        },
                      },
                ),
        ),
      );
      if (saved == true) {
        finished = true;
        autosave?.cancel();
        await drafts.save(draftKey, null);
        if (mounted) Navigator.pop(context, widget.returnSource ? null : true);
      }
    } catch (e) {
      if (mounted && same && stamp == op) setState(() => error = userError(e));
    } finally {
      if (mounted && stamp == op) setState(() => busy = false);
    }
  }

  Future<void> chooseReference() async {
    final current = schoolTime(referenceAt);
    final day = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (t != null && mounted) {
      setState(() {
        dirty = true;
        referenceAt = DateTime.parse(
          '${day.toIso8601String().substring(0, 10)}T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00+08:00',
        ).toUtc().toIso8601String();
      });
      await saveDraft();
    }
  }

  Future<void> showRecent() async {
    await loadRecent();
    if (!mounted || !same) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .55,
          child: recent.isEmpty
              ? const Center(child: Text('还没有上传记录'))
              : ListView(
                  children: [
                    for (final row in recent)
                      AppTile(
                        key: ValueKey('source-${row['id']}'),
                        leading: Icon(
                          row['kind'] == 'image'
                              ? Icons.image_outlined
                              : Icons.mic_none_rounded,
                        ),
                        title: Text(
                          (row['text'] as String? ?? '').isEmpty
                              ? sourceState(row['status'])
                              : row['text'],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(displayInstant(row['created_at'])),
                        onTap: () => Navigator.pop(context, row),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (selected != null && mounted && same) await selectSource(selected);
  }

  Future<void> moreAction(String action) async {
    switch (action) {
      case 'reference':
        await chooseReference();
      case 'retry':
        await uploadAndRecognize();
      case 'manual':
        await parse(manual: true);
      case 'save':
        await saveOnly();
      case 'recent':
        await showRecent();
      case 'source':
        if (source == null) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SourceViewPage(
              controller: widget.controller,
              id: source!['id'],
            ),
          ),
        );
        await checkJob(force: true);
      case 'play':
        if (local == null) return;
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LocalAudioPreview(path: local!),
            ),
          ),
        );
      case 'draft':
        await restore();
    }
  }

  Future<void> showMore() async {
    final actions = <(String, String, IconData)>[
      if (!restored) ('draft', '重新读取草稿', Icons.restore_rounded),
      (
        'reference',
        '原消息时间：${displayInstant(referenceAt)}',
        Icons.schedule_rounded,
      ),
      if (source?['file_deleted'] != true && (local != null || source != null))
        ('retry', '重试识别', Icons.refresh_rounded),
      ('manual', '手动填写事项', Icons.edit_outlined),
      if (local != null && kind == 'audio')
        ('play', '回放录音', Icons.play_circle_outline_rounded),
      if (source != null) ...[
        ('save', '保存文字，稍后整理', Icons.save_outlined),
        ('source', '查看原始内容', Icons.description_outlined),
      ],
      ('recent', '最近上传', Icons.history_rounded),
    ];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              for (final action in actions)
                AppTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  leading: Icon(action.$3),
                  title: Text(action.$2),
                  onTap: () => Navigator.pop(context, action.$1),
                ),
            ],
          ),
        ),
      ),
    );
    if (action != null && mounted && same) await moreAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final working = ['queued', 'running'].contains(source?['status']);
    final locked = busy || working || recording || !restored || !same;
    final hasText = text.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(kind == 'image' ? '图片通知' : '语音输入'),
        actions: [
          AppIconButton(
            tooltip: '更多操作',
            onPressed: !locked || (!restored && error != null)
                ? showMore
                : null,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: !same
          ? const Center(child: Text('账号或学期已切换，请返回'))
          : SafeArea(
              top: false,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      children: [
                        if (kind == 'image' && local != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(local!),
                              cacheWidth: 1400,
                              height: 180,
                              fit: BoxFit.contain,
                              errorBuilder: (_, _, _) =>
                                  const Text('原图暂不可用，可重新选择'),
                            ),
                          ),
                        if (kind == 'image')
                          AppOutlineButton.icon(
                            onPressed: locked ? null : pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: Text(local == null ? '选择通知图片' : '重新选图'),
                          ),
                        if (busy || working) ...[
                          const SizedBox(height: 12),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(working ? '正在转成文字…' : '正在处理…'),
                          AppTextButton(
                            onPressed: cancel,
                            child: const Text('取消当前处理，保留草稿'),
                          ),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (source?['file_deleted'] == true)
                          const Text('原文件已删除，保留的文字仍可使用。'),
                        const SizedBox(height: 12),
                        AppField(
                          key: const Key('media-transcript'),
                          controller: text,
                          minLines: 4,
                          maxLines: 10,
                          maxLength: 10000,
                          enabled: !locked,
                          onChanged: textChanged,
                          decoration: InputDecoration(
                            labelText: '通知文字',
                            hintText: kind == 'audio'
                                ? (widget.initialAudioPath == null
                                      ? '按住下方说话，松开后文字会出现在这里'
                                      : '识别出的文字会出现在这里')
                                : '图片里的文字会出现在这里，可修改错字',
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        if (hasText)
                          Text(
                            '可以修改错字和时间。',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (kind == 'audio' &&
                            widget.initialAudioPath == null) ...[
                          Text(
                            recording ? '上滑取消' : '松开完成 · 上滑取消',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          HoldVoiceButton(
                            input: widget.kind == 'audio' ? widget.input : null,
                            enabled: !busy && !working && restored && same,
                            onRecorded: recorded,
                            onError: (message) {
                              if (mounted) setState(() => error = message);
                            },
                            onRecordingChanged: (value) {
                              if (mounted) setState(() => recording = value);
                            },
                          ),
                        ],
                        if (hasText || kind == 'image') ...[
                          const SizedBox(height: 10),
                          AppButton(
                            onPressed: locked || source == null || !hasText
                                ? null
                                : () => parse(),
                            child: Text(widget.returnSource ? '发送' : '整理日程'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
