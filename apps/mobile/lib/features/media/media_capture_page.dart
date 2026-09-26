import '../calendar/event_form.dart';
import '../../core/api.dart' show userError;
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/campus_widgets.dart';
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
  const MediaCapturePage({
    super.key,
    required this.controller,
    required this.semester,
    this.kind = 'image',
    this.input,
  });
  @override
  State<MediaCapturePage> createState() => _MediaCapturePageState();
}

class _MediaCapturePageState extends State<MediaCapturePage>
    with WidgetsBindingObserver {
  late final input = widget.input ?? DeviceMediaInput();
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
      finished = false;
  int op = 0, seconds = 0;
  DateTime? recordStart;
  Timer? poll, tick, autosave;
  bool get same =>
      generation == widget.controller.api.generation &&
      owner == widget.controller.owner &&
      widget.semester['id'] == widget.controller.semesterId;
  String get draftKey => 'media:${widget.semester['id']}';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(accountChanged);
    restore();
    poll = Timer.periodic(const Duration(seconds: 2), (_) => checkJob());
  }

  void accountChanged() {
    if (!same) {
      op++;
      input.dispose();
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
    if (recording && state != AppLifecycleState.resumed) stopRecording();
  }

  @override
  void dispose() {
    if (same && !finished) saveDraft().catchError((_) {});
    op++;
    poll?.cancel();
    tick?.cancel();
    autosave?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(accountChanged);
    input.dispose();
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
    try {
      final draft = await drafts.read(draftKey);
      if (!mounted || !same) return;
      if (draft != null) {
        setState(() {
          kind = draft['kind'] ?? kind;
          local = draft['local'];
          key = draft['key'] ?? key;
          source = draft['source'] == null
              ? null
              : Map<String, dynamic>.from(draft['source']);
          text.text = draft['text'] ?? '';
          referenceAt = draft['reference_at'] ?? referenceAt;
          dirty = draft['dirty'] == true;
        });
        if (draft['picking'] == true) {
          final file = await input.image(recover: true);
          if (file != null && mounted && same) await adopt(file, 'image');
        }
      }
      await loadRecent();
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

  Future<void> adopt(String path, String type) async {
    if (!same) return;
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
    if (!mounted || !same) {
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
    if (!same) return;
    setState(() => busy = true);
    try {
      await saveDraft(picking: true);
      final file = await input.image();
      if (file != null && mounted && same) await adopt(file, 'image');
      await saveDraft();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startRecording() async {
    if (!same) return;
    setState(() => busy = true);
    try {
      if (!await input.start()) {
        if (mounted) setState(() => error = '麦克风权限未开启，仍可选图或手工填写');
        return;
      }
      if (!mounted || !same) {
        await input.dispose();
        return;
      }
      setState(() {
        recording = true;
        seconds = 0;
        error = null;
      });
      recordStart = DateTime.now();
      tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(
            () => seconds = DateTime.now().difference(recordStart!).inSeconds,
          );
        }
        if (seconds >= 119) stopRecording();
      });
    } catch (e) {
      if (mounted) setState(() => error = '暂时无法开始录音，请检查麦克风权限后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stopRecording() async {
    if (!recording) return;
    tick?.cancel();
    setState(() => recording = false);
    try {
      final file = await input.stop();
      if (file != null && mounted && same) {
        await adopt(file, 'audio');
        await input.release(file);
      }
    } catch (e) {
      if (mounted) setState(() => error = '录音暂时没能保存，请重试。');
    }
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
      });
      await saveDraft();
      await loadRecent();
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
          builder: (ctx) => AlertDialog(
            title: const Text('打开已保存的内容？'),
            content: const Text('当前文字还没保存。继续打开会替换它；你也可以返回，先复制或保存当前文字。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('继续编辑当前文字'),
              ),
              FilledButton(
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
        if (mounted) Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final working = ['queued', 'running'].contains(source?['status']);
    return Scaffold(
      appBar: AppBar(title: Text(kind == 'image' ? '图片通知录入' : '语音快速记录')),
      body: !same
          ? const Center(child: Text('账号或学期已切换，请返回'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const CampusHero(
                  eyebrow: '保留来源',
                  title: '从通知到事项',
                  subtitle: '先识别内容，再对照核对\n只有你确认后才保存事项',
                ),
                const SizedBox(height: 16),
                const SoftNotice(
                  '图片最多10MB，录音最长2分钟。文件上传后会转成文字；你确认的文字和课程名称会发送给AI，用于整理事项。',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy || working || recording
                          ? null
                          : pickImage,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('选择通知图片'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || working
                          ? null
                          : recording
                          ? stopRecording
                          : startRecording,
                      icon: Icon(recording ? Icons.stop : Icons.mic_none),
                      label: Text(recording ? '停止并保存录音（${seconds}s）' : '录一段通知'),
                    ),
                  ],
                ),
                if (recording) const Text('录音中，切到后台将停止录音'),
                if (local != null && kind == 'image')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Image.file(
                      File(local!),
                      cacheWidth: 1400,
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('本机找不到原图，请重新选择，或打开已上传的原图'),
                    ),
                  ),
                if (local != null && kind == 'audio')
                  LocalAudioPreview(key: ValueKey(local), path: local!),
                if (source != null) ...[
                  Text(sourceState(source!['status'])),
                  TextButton(
                    onPressed: () async {
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
                    },
                    child: const Text('查看原图 / 回放原录音'),
                  ),
                ],
                FilledButton(
                  onPressed:
                      busy ||
                          working ||
                          recording ||
                          source?['file_deleted'] == true ||
                          local == null && source == null
                      ? null
                      : uploadAndRecognize,
                  child: Text(source == null ? '上传并识别' : '重新识别原文件'),
                ),
                if (source?['file_deleted'] == true)
                  const SoftNotice('原文件已删除，仍可核对保留文字或手工填写。'),
                if (working || busy) ...[
                  const LinearProgressIndicator(),
                  TextButton(
                    onPressed: cancel,
                    child: const Text('取消当前处理，保留草稿'),
                  ),
                ],
                if (source != null &&
                    (source!['original_text'] as String? ?? '').isNotEmpty)
                  ExpansionTile(
                    title: const Text('查看AI识别的原文'),
                    children: [SelectableText(source!['original_text'])],
                  ),
                const SectionHeading('核对识别文字'),
                TextField(
                  controller: text,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 10000,
                  enabled: !busy && !working,
                  onChanged: textChanged,
                  decoration: const InputDecoration(labelText: '可修正错字、日期与数字'),
                ),
                TextButton(
                  onPressed: busy || working ? null : chooseReference,
                  child: Text('原消息时间：${displayInstant(referenceAt)}'),
                ),
                const Text('本机草稿自动保存；转贴旧通知时请核对原消息时间。'),
                if (error != null) SoftNotice(error!, warning: true),
                FilledButton(
                  onPressed:
                      busy ||
                          working ||
                          source == null ||
                          text.text.trim().isEmpty
                      ? null
                      : () => parse(),
                  child: const Text('用这些文字整理事项'),
                ),
                TextButton(
                  onPressed: busy || working ? null : () => parse(manual: true),
                  child: Text(source == null ? '不上传文件，直接手动填写' : '保存文字并手动填写事项'),
                ),
                TextButton(
                  onPressed: busy || working || source == null
                      ? null
                      : saveOnly,
                  child: const Text('先保存文字，稍后整理'),
                ),
                const SectionHeading('最近上传的图片和录音（最多50份）'),
                for (final row in recent)
                  ListTile(
                    key: ValueKey('source-${row['id']}'),
                    title: Text(
                      '${row['kind'] == 'image' ? '图片通知' : '录音'} · ${sourceState(row['status'])}',
                    ),
                    subtitle: Text(displayInstant(row['created_at'])),
                    onTap: busy || recording ? null : () => selectSource(row),
                  ),
              ],
            ),
    );
  }
}
