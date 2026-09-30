import '../../ui/app_controls.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import 'agent_controller.dart';
import 'agent_answer.dart';
import 'change_confirmation.dart';
import '../media/inline_capture_controller.dart';
import '../media/media_input.dart';
import '../planning/date_time_picker.dart';
import '../media/hold_voice_button.dart';
import '../media/source_view.dart';
import '../insights/insights_controller.dart' show insightHours;
import '../media/drafts.dart';

class AgentPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String? initialMediaKind;
  final String? initialText;
  final bool embedded, autoSubmit, autofocus;
  final MediaInput? voiceInput, imageInput;
  const AgentPage({
    super.key,
    required this.controller,
    required this.semester,
    this.initialMediaKind,
    this.initialText,
    this.embedded = false,
    this.autoSubmit = false,
    this.autofocus = false,
    this.voiceInput,
    this.imageInput,
  });
  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> with WidgetsBindingObserver {
  late final AgentController c;
  late final InlineCaptureController media;
  MediaInput? gallery;
  bool restoringMedia = false, sendingMedia = false, pickingImage = false;
  bool pendingMediaDraft = false;
  bool expandedImagePreview = false;
  String? transcriptAck;
  int captureEpoch = 0;
  String? captureError;
  bool get mediaWorking =>
      media.busy ||
      ['uploading', 'queued', 'running', 'recognizing'].contains(media.phase);
  bool get conversationLocked =>
      !readyForDraft ||
      c.loading ||
      c.busy ||
      sendingMedia ||
      mediaWorking ||
      pickingImage ||
      voiceRecording ||
      pendingMediaDraft ||
      media.hasPending;
  final input = TextEditingController();
  final composerFocus = FocusNode();
  final conversationScroll = ScrollController();
  Timer? draftTimer;
  late final CaptureDrafts drafts;
  late String draftKey;
  late final String baseDraftKey, contextPointerKey;
  bool readyForDraft = false;
  late bool voiceMode = widget.initialMediaKind == 'audio';
  bool voiceRecording = false;
  Map<String, dynamic>? attachment;
  bool detachedSource = false;
  Map<String, dynamic>? get currentSource =>
      attachment ?? (detachedSource ? null : c.activeSource);
  final Set<String> partialAcknowledged = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = AgentController(widget.controller, widget.semester['id']);
    media = InlineCaptureController(
      controller: widget.controller,
      semesterId: widget.semester['id'],
      onTranscript: (value) {
        if (!mounted || !c.active || value.trim().isEmpty) return;
        final source = media.source;
        final token = '${source?['id']}:${source?['version']}';
        // The acknowledgement and composer text are saved together. Reopening
        // an edited draft must not append the original transcript again.
        if (transcriptAck != token) {
          final existing = input.text.trim();
          if (!restoringMedia || !existing.endsWith(value.trim())) {
            input.text = [
              if (existing.isNotEmpty) existing,
              value.trim(),
            ].join('\n');
          }
          input.selection = TextSelection.collapsed(offset: input.text.length);
          transcriptAck = token;
        }
        setState(() => voiceMode = false);
        scheduleDraft();
      },
    )..addListener(mediaChanged);
    final generation = widget.controller.api.generation,
        sid = widget.semester['id'];
    drafts = CaptureDrafts(
      widget.controller.cache,
      widget.controller.owner!,
      () =>
          generation == widget.controller.api.generation &&
          sid == widget.controller.semesterId,
    );
    baseDraftKey = 'assistant:$sid';
    contextPointerKey = 'assistant-context-latest:$sid';
    draftKey = widget.initialText == null
        ? baseDraftKey
        : 'assistant-context:$sid:${base64Url.encode(utf8.encode(widget.initialText!))}';
    input.text = widget.initialText ?? '';
    input.addListener(scheduleDraft);
    initialize();
  }

  Future<void> initialize() async {
    Map<String, dynamic>? saved;
    try {
      if (widget.initialText == null) {
        final pointer = await drafts.read(contextPointerKey);
        if (pointer?['key'] is String) {
          final candidate = await drafts.read(pointer!['key']);
          if (candidate != null &&
              ('${candidate['text'] ?? ''}'.isNotEmpty ||
                  candidate['source'] != null ||
                  candidate['pending_media'] == true ||
                  candidate['picking_image'] == true)) {
            draftKey = pointer['key'];
            saved = candidate;
          }
        }
      }
      saved ??= await drafts.read(draftKey);
      if (widget.initialText != null &&
          saved != null &&
          '${saved['text'] ?? ''}'.isEmpty &&
          saved['source'] == null &&
          saved['pending_media'] != true &&
          saved['picking_image'] != true) {
        saved = null;
      }
    } catch (_) {
      /* Local storage failure does not disable online input. */
    }
    if (!mounted || !c.active) return;
    await c.open(
      id: saved?['thread_id'],
      fresh: widget.initialText != null && saved?['thread_id'] == null,
    );
    if (!mounted || !c.active) return;
    if (saved != null) {
      input.text = saved['text'] ?? '';
      attachment = saved['source'] is Map
          ? Map<String, dynamic>.from(saved['source'])
          : null;
      detachedSource = saved['detached'] == true;
      mediaReferenceOverride = saved['media_reference_override'];
      transcriptAck = saved['media_transcript_ack'];
      pendingMediaDraft = saved['pending_media'] == true;
    }
    readyForDraft = true;
    restoringMedia = true;
    try {
      await media.restore(scope: draftKey);
    } finally {
      restoringMedia = false;
    }
    if (!mounted || !c.active) return;
    pendingMediaDraft = media.hasPending;
    setState(() {});
    if (saved?['picking_image'] == true) {
      // Recover only inside the resolved conversation draft scope. Do not
      // launch a fresh picker, which would consume Android's lost result.
      if (!media.hasPending) await attach('image', recoverImage: true);
      if (!mounted || !c.active) return;
      await saveDraft();
    } else if (widget.initialMediaKind == 'image' && !media.hasPending) {
      await attach('image');
    } else if (widget.autoSubmit &&
        saved == null &&
        input.text.trim().isNotEmpty) {
      await send();
    } else if (widget.autofocus && !voiceMode) {
      composerFocus.requestFocus();
    }
  }

  void mediaChanged() {
    if (mounted) setState(() {});
  }

  void scheduleDraft() {
    if (!readyForDraft) return;
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 350), () => saveDraft());
  }

  Future<void> saveDraft() async {
    final value = {
      'text': input.text,
      'source': attachment,
      'detached': detachedSource,
      'thread_id': c.threadId,
      'media_reference_override': mediaReferenceOverride,
      'media_transcript_ack': transcriptAck,
      'pending_media': pendingMediaDraft || media.hasPending,
      'picking_image': pickingImage,
    };
    final key = draftKey;
    try {
      await drafts.save(
        key,
        value,
        pointerKey: key == baseDraftKey ? null : contextPointerKey,
        activatePointer:
            (value['text'] as String).isNotEmpty ||
            value['source'] != null ||
            value['pending_media'] == true ||
            value['picking_image'] == true,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('草稿未能保存，请保留输入内容')));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.poll();
      media.checkJob(force: true);
    }
  }

  @override
  void dispose() {
    draftTimer?.cancel();
    if (readyForDraft) saveDraft();
    input.removeListener(scheduleDraft);
    composerFocus.dispose();
    conversationScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    media.removeListener(mediaChanged);
    media.dispose();
    gallery?.dispose();
    c.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!readyForDraft ||
        !c.active ||
        c.loading ||
        c.busy ||
        c.processing ||
        mediaWorking ||
        pickingImage ||
        sendingMedia ||
        voiceRecording) {
      return;
    }
    final value = input.text.trim();
    if (value.isEmpty) return;
    final intendedThread = c.threadId;
    setState(() => sendingMedia = true);
    try {
      if (media.hasPending) {
        final confirmed = await media.confirmText(
          value,
          referenceAt: mediaReferenceOverride,
        );
        if (!mounted || !c.active || confirmed == null) return;
        attachment = confirmed;
        detachedSource = false;
      }
      if (c.threadId != intendedThread || c.loading) return;
      await submit(value, reviewedCapture: true);
    } finally {
      if (mounted) setState(() => sendingMedia = false);
    }
  }

  Future<void> submit(
    String text, {
    List<String> selectedRecordIds = const [],
    bool reviewedCapture = false,
  }) async {
    if (!c.active ||
        c.loading ||
        mediaWorking ||
        pickingImage ||
        voiceRecording ||
        (!reviewedCapture &&
            (sendingMedia || media.hasPending || pendingMediaDraft))) {
      return;
    }
    final source = currentSource;
    final submittedMediaId = reviewedCapture ? (media.source?['id']) : null;
    if (await c.send(
          text,
          source: source,
          detachSource: detachedSource,
          selectedRecordIds: selectedRecordIds,
        ) &&
        mounted) {
      if (input.text.trim() == text) input.clear();
      if (submittedMediaId != null && media.source?['id'] == submittedMediaId) {
        await media.detach();
      }
      if (!mounted || !c.active) return;
      setState(() {
        attachment = null;
        detachedSource = false;
        mediaReferenceOverride = null;
        pendingMediaDraft = media.hasPending;
        if (!pendingMediaDraft) transcriptAck = null;
      });
      if (readyForDraft) await saveDraft();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && conversationScroll.hasClients) {
          conversationScroll.jumpTo(0);
        }
      });
    }
  }

  Future<void> attach(
    String kind, {
    String? audioPath,
    bool recoverImage = false,
  }) async {
    if (!readyForDraft ||
        !c.active ||
        c.loading ||
        c.busy ||
        c.processing ||
        mediaWorking ||
        sendingMedia ||
        pickingImage) {
      return;
    }
    final epoch = ++captureEpoch;
    composerFocus.unfocus();
    mediaReferenceOverride = null;
    setState(() => captureError = null);
    String? path = audioPath;
    if (kind == 'image') {
      setState(() => pickingImage = true);
      try {
        await saveDraft();
        if (!mounted || !c.active || epoch != captureEpoch) return;
        gallery ??= widget.imageInput ?? DeviceMediaInput();
        path = await gallery!.image(recover: recoverImage);
      } catch (_) {
        if (mounted) setState(() => captureError = '图片未能打开，请重试');
      } finally {
        if (mounted && epoch == captureEpoch) {
          setState(() => pickingImage = false);
        }
      }
    }
    if (!mounted || !c.active || epoch != captureEpoch) return;
    if (path == null) {
      await saveDraft();
      return;
    }
    attachment = null;
    detachedSource = true;
    transcriptAck = null;
    expandedImagePreview = false;
    pendingMediaDraft = true;
    // Keep the picker recovery flag until capture has durably copied the file.
    pickingImage = kind == 'image';
    await saveDraft();
    if (!mounted || !c.active || epoch != captureEpoch) return;
    await media.capture(path, kind);
    if (!mounted || !c.active || epoch != captureEpoch) return;
    pickingImage = false;
    pendingMediaDraft = media.hasPending;
    setState(() {});
    await saveDraft();
  }

  Future<void> removeCapture() async {
    captureEpoch++;
    if (mediaWorking) await media.cancel();
    await media.detach();
    if (!mounted) return;
    setState(() {
      attachment = null;
      detachedSource = true;
      captureError = null;
      voiceMode = false;
      pickingImage = false;
      pendingMediaDraft = false;
      transcriptAck = null;
    });
    scheduleDraft();
  }

  Future<void> captureReference() async {
    final initial = DateTime.tryParse(media.referenceAt);
    final selected = await pickSchoolDateTime(context, initial: initial);
    if (!mounted || selected == null) return;
    // Preserve source versioning; changing the reference is confirmed on send.
    mediaReferenceOverride = selected.toUtc().toIso8601String();
    setState(() {});
    scheduleDraft();
  }

  String? mediaReferenceOverride;

  Widget captureStatus() {
    final failed = media.error ?? captureError;
    final emptyVoice =
        media.kind == 'audio' &&
        const [
          'NO_USABLE_TEXT',
          'EMPTY_TRANSCRIPT',
        ].contains(media.source?['error_code']);
    final status = pickingImage
        ? '正在选择图片…'
        : mediaWorking
        ? (media.phase == 'uploading' ? '正在上传…' : '正在识别…')
        : failed ?? (media.kind == 'audio' ? '语音已转成文字' : '图片文字已提取');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: failed == null ? CampusColors.blueSoft : CampusColors.errorSoft,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (media.kind == 'image' && media.local != null)
                InkWell(
                  onTap: () => setState(
                    () => expandedImagePreview = !expandedImagePreview,
                  ),
                  child: AnimatedSize(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Image.file(
                      File(media.local!),
                      height: expandedImagePreview ? 220 : 96,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      semanticLabel: '原始图片，点击展开或收起',
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Row(
                children: [
                  Icon(
                    media.kind == 'image'
                        ? Icons.image_outlined
                        : Icons.mic_none_rounded,
                    size: 20,
                    color: CampusColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(status, style: const TextStyle(fontSize: 14)),
                  ),
                  AppIconButton(
                    tooltip: '移除本次附件',
                    onPressed: sendingMedia ? null : removeCapture,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              if (mediaWorking) const LinearProgressIndicator(minHeight: 2),
              if (!mediaWorking && failed != null)
                Wrap(
                  spacing: 8,
                  children: [
                    if (media.hasPending)
                      AppTextButton(
                        onPressed: sendingMedia
                            ? null
                            : emptyVoice
                            ? () async {
                                await removeCapture();
                                if (mounted) setState(() => voiceMode = true);
                              }
                            : media.retry,
                        child: Text(emptyVoice ? '重新录音' : '重试识别'),
                      ),
                    AppTextButton(
                      onPressed: () async {
                        await removeCapture();
                        if (mounted) composerFocus.requestFocus();
                      },
                      child: const Text('直接输入'),
                    ),
                  ],
                ),
              if (!mediaWorking &&
                  media.source != null &&
                  failed == null &&
                  media.kind == 'image')
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppTextButton(
                    onPressed: sendingMedia ? null : captureReference,
                    child: Text(
                      '消息时间 ${displayInstant(mediaReferenceOverride ?? media.referenceAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> moreInput() async {
    composerFocus.unfocus();
    final value = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final choice in const [
              ('image', '从图片导入', Icons.image_outlined),
              ('event', '添加日程', Icons.event_outlined),
              ('item', '添加待办', Icons.checklist_rounded),
              ('exam', '添加考试', Icons.school_outlined),
            ])
              AppTile(
                leading: Icon(choice.$3),
                title: Text(choice.$2),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, choice.$1),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    if (value == 'image') {
      await attach('image');
      return;
    }
    await context.push(
      value == 'event'
          ? '/events/new'
          : '/items/new?kind=${value == 'exam' ? 'exam' : 'task'}',
    );
  }

  void sourceView(Map source) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          SourceViewPage(controller: widget.controller, id: source['id']),
    ),
  );

  Future<void> history() async {
    if (conversationLocked) return;
    await c.open(id: c.threadId);
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '最近对话',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          for (final t in c.threads)
            AppTile(
              title: Text(t['title']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, t['id'] as String),
            ),
          if (c.threads.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('还没有对话')),
        ],
      ),
    );
    if (selected != null && !conversationLocked) {
      await c.open(id: selected);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && conversationScroll.hasClients) {
          conversationScroll.jumpTo(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        leading: widget.embedded
            ? AppIconButton(
                tooltip: '收起输入',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              )
            : null,
        title: Text(widget.embedded ? '智能输入' : '日程助手'),
        actions: [
          AppIconButton(
            tooltip: '最近对话',
            onPressed: conversationLocked ? null : history,
            icon: const Icon(Icons.history_rounded),
          ),
          AppIconButton(
            tooltip: '新对话',
            onPressed: conversationLocked ? null : () => c.open(fresh: true),
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (MediaQuery.viewInsetsOf(context).bottom == 0 &&
                MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom >
                    360)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  widget.semester['name'] ?? '当前学期',
                  style: const TextStyle(
                    color: CampusColors.muted,
                    fontSize: 13,
                  ),
                ),
              ),
            Expanded(
              child: c.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: conversationScroll,
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      children: [
                        if (c.runs.isEmpty &&
                            !media.hasPending &&
                            captureError == null &&
                            !pickingImage) ...[
                          const SizedBox(height: 20),
                          const Text(
                            '记录与查询',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: CampusColors.ink,
                            ),
                          ),
                          const SizedBox(height: 20),
                          for (final example in [
                            '我今天有哪些安排？',
                            '这周哪天有一小时空闲？',
                            '明天下午3点到4点开组会，提前30分钟提醒',
                          ])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: AppTile(
                                onTap: () => input.text = example,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 6,
                                ),
                                leading: const Icon(
                                  Icons.arrow_outward_rounded,
                                  size: 20,
                                  color: CampusColors.primary,
                                ),
                                title: Text(example),
                              ),
                            ),
                        ],
                        if (c.runs.length > 1)
                          AppDisclosure(
                            key: ValueKey('earlier-${c.runs.last['id']}'),
                            title: Text('历史消息 · ${c.runs.length - 1}'),
                            children: [
                              for (final run in c.runs.take(c.runs.length - 1))
                                turnView(run),
                            ],
                          ),
                        if (c.runs.isNotEmpty) turnView(c.runs.last),
                        if (media.hasPending ||
                            media.error != null ||
                            captureError != null ||
                            pickingImage)
                          captureStatus(),
                      ],
                    ),
            ),
            if (c.error != null)
              Container(
                color: CampusColors.warningSoft,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(c.error!)),
                    AppTextButton(
                      onPressed: () =>
                          c.processing ? c.poll() : c.open(id: c.threadId),
                      child: const Text('重新读取'),
                    ),
                  ],
                ),
              ),
            if (currentSource != null && !media.hasPending)
              AppTile(
                dense: true,
                leading: Icon(
                  currentSource!['kind'] == 'image'
                      ? Icons.image_outlined
                      : Icons.mic_none,
                ),
                title: Text(
                  '${currentSource!['text']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                onTap: () => sourceView(currentSource!),
                trailing: AppIconButton(
                  tooltip: '移除本次附件',
                  onPressed: c.busy
                      ? null
                      : () => setState(() {
                          attachment = null;
                          detachedSource = true;
                          if (input.text == '请根据这份通知整理安排，先给我预览') input.clear();
                        }),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (voiceRecording)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '上滑取消',
                  style: TextStyle(fontSize: 13, color: CampusColors.muted),
                ),
              ),
            composer(),
          ],
        ),
      ),
    ),
  );

  Widget composer() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final blocked =
        c.busy ||
        c.processing ||
        voiceRecording ||
        mediaWorking ||
        pickingImage ||
        sendingMedia;
    final field = FTextField(
      control: FTextFieldControl.managed(controller: input),
      focusNode: composerFocus,
      minLines: 1,
      maxLines: landscape || MediaQuery.sizeOf(context).height < 300
          ? 1
          : MediaQuery.viewInsetsOf(context).bottom > 0 ||
                MediaQuery.sizeOf(context).height < 500
          ? 2
          : 4,
      enabled: !c.loading && !media.busy && !sendingMedia,
      maxLength: 10000,
      hint: '输入通知或日程问题',
      counterBuilder: (_, _, _, _) => null,
    );
    final toggle = AppIconButton(
      tooltip: voiceMode ? '切换键盘输入' : '切换语音输入',
      onPressed: blocked
          ? null
          : () {
              setState(() => voiceMode = !voiceMode);
              if (voiceMode) {
                composerFocus.unfocus();
              } else {
                composerFocus.requestFocus();
              }
            },
      icon: Icon(voiceMode ? Icons.keyboard_outlined : Icons.mic_none_rounded),
    );
    final more = AppIconButton(
      tooltip: '添加图片或手动记录',
      onPressed: blocked ? null : moreInput,
      icon: const Icon(Icons.add_circle_outline_rounded),
    );
    final submit = ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (_, value, _) => AppIconButton.filled(
        tooltip: '发送',
        onPressed: c.loading || blocked || value.text.trim().isEmpty
            ? null
            : send,
        icon: const Icon(Icons.arrow_upward_rounded),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: CampusColors.surface,
        border: Border(top: BorderSide(color: CampusColors.line)),
      ),
      child: voiceMode
          ? Row(
              children: [
                toggle,
                Expanded(
                  child: HoldVoiceButton(
                    enabled:
                        c.active &&
                        readyForDraft &&
                        !c.loading &&
                        !c.busy &&
                        !c.processing &&
                        !mediaWorking &&
                        !pickingImage &&
                        !sendingMedia,
                    input: widget.voiceInput,
                    onRecorded: (path) => attach('audio', audioPath: path),
                    onRecordingChanged: (value) {
                      if (mounted) setState(() => voiceRecording = value);
                    },
                    onError: (message) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(message)));
                      }
                    },
                  ),
                ),
                more,
              ],
            )
          : landscape
          ? Row(
              children: [
                toggle,
                Expanded(child: field),
                more,
                submit,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                field,
                Row(children: [toggle, const Spacer(), more, submit]),
              ],
            ),
    );
  }

  Widget turnView(Map<String, dynamic> run) {
    final working = run['status'] == 'queued' || run['status'] == 'running';
    final p = run['preview'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(left: 35, bottom: 18),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CampusColors.blueSoft,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(5),
                ),
              ),
              child: Text(
                run['source'] is Map && run['text'] == '请根据这份通知整理安排，先给我预览'
                    ? (run['source']['kind'] == 'image' ? '图片通知' : '语音记录')
                    : run['text'],
                style: const TextStyle(
                  color: CampusColors.ink,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ),
          if (working)
            Row(
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(run['stage'] ?? '正在处理')),
                AppTextButton(
                  onPressed: () => c.stop(run),
                  child: const Text('停止'),
                ),
              ],
            ),
          if (run['source'] is Map)
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton.icon(
                onPressed: () => sourceView(run['source']),
                icon: const Icon(Icons.description_outlined, size: 17),
                label: const Text('查看原始来源'),
              ),
            ),
          if ((run['answer'] ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AgentAnswer(run['answer']),
            ),
          if (p is Map)
            p['kind'] == 'plan'
                ? planPreview(run, Map<String, dynamic>.from(p))
                : {
                    'course_change',
                    'exam_change',
                    'batch',
                    'undo',
                  }.contains(p['kind'])
                ? ChangeConfirmation(
                    key: ValueKey(p['token']),
                    run: run,
                    controller: c,
                    details: (child) => changeDetails(run, child),
                  )
                : previewCard(run, Map<String, dynamic>.from(p)),
          if (run['status'] == 'applied' && run['undo_available'] == true)
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton.icon(
                onPressed: conversationLocked || c.processing
                    ? null
                    : () => c.requestUndo(run),
                icon: const Icon(Icons.undo_rounded),
                label: const Text('撤销这次操作'),
              ),
            ),
          if (run['undone_by'] != null) const Text('这次操作已撤销'),
          if (p is Map && rows(run['cards']).isNotEmpty)
            AppDisclosure(
              title: const Text('查看参考安排'),
              children: [for (final card in rows(run['cards'])) factCard(card)],
            )
          else
            for (final card in rows(run['cards'])) factCard(card),
          if (run['error'] != null)
            Text(
              run['error'],
              style: const TextStyle(color: Color(0xFF9A5C13)),
            ),
          if (run['status'] == 'cancelled')
            const Text(
              '已停止，未保存这次修改',
              style: TextStyle(color: CampusColors.muted),
            ),
          if (run['status'] == 'superseded')
            const Text(
              '已按后续消息重新处理，这份预览未保存',
              style: TextStyle(color: CampusColors.muted),
            ),
        ],
      ),
    );
  }

  Widget panel(Widget child, {Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );

  Widget factCard(Map<String, dynamic> card) {
    final d = Map<String, dynamic>.from(card['data'] ?? {});
    final kind = card['kind'];
    if (kind == 'insights') {
      final summary = Map<String, dynamic>.from(d['summary'] ?? {}),
          filters = Map<String, dynamic>.from(d['filters'] ?? {});
      final link = Uri(
        path: '/insights',
        queryParameters: {
          'from': '${d['from_date']}',
          'to': '${d['to_date']}',
          if (filters['category_id'] != null)
            'category': '${filters['category_id']}',
          if ((filters['tag_ids'] as List? ?? []).isNotEmpty)
            'tags': (filters['tag_ids'] as List).join(','),
        },
      ).toString();
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '统计依据',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              '${d['from_date']} — ${d['to_date']}',
              style: const TextStyle(color: CampusColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                metric(
                  '固定安排',
                  insightHours(summary['fixed_scheduled_minutes']),
                ),
                metric(
                  '个人计划',
                  insightHours(summary['personal_planned_minutes']),
                ),
                metric('实际记录', insightHours(summary['actual_minutes'])),
              ],
            ),
            const SizedBox(height: 12),
            AppTextButton.icon(
              onPressed: () => context.push(link),
              icon: const Icon(Icons.bar_chart),
              label: const Text('查看这组统计'),
            ),
          ],
        ),
        color: CampusColors.blueSoft,
      );
    }
    if (kind == 'planning_result') {
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '暂时无法生成可保存的计划',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            for (final message in (d['messages'] as List? ?? []))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('$message'),
              ),
          ],
        ),
      );
    }
    if (kind == 'calendar' ||
        kind == 'records' ||
        kind == 'course_occurrences') {
      final entries = rows(
        d[kind == 'calendar'
            ? 'entries'
            : kind == 'course_occurrences'
            ? 'occurrences'
            : 'records'],
      );
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              kind == 'calendar' ? '查到的安排' : '匹配的事项',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (kind == 'calendar')
              Text(
                '${d['from_date']} — ${d['to_date']}',
                style: const TextStyle(color: CampusColors.muted, fontSize: 12),
              ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('没有查到匹配的安排'),
              ),
            if (kind == 'course_occurrences' &&
                entries.length > 1 &&
                c.runs.isNotEmpty &&
                entries.every(
                  (e) => (c.runs.last['ambiguous_ids'] as List? ?? []).contains(
                    e['id'],
                  ),
                ))
              AppTextButton(
                onPressed: conversationLocked || c.processing
                    ? null
                    : () => submit(
                        '我已核对以上 ${entries.length} 个课次，按这组课次继续刚才的操作。',
                        selectedRecordIds: entries
                            .map((e) => e['id'] as String)
                            .toList(),
                      ),
                child: Text('选择以上 ${entries.length} 个课次'),
              ),
            for (final e in entries)
              AppTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(e['title'] ?? '日程'),
                subtitle: Text(
                  entryTime(e) +
                      (e['location'] != null && e['location'] != ''
                          ? ' · ${e['location']}'
                          : ''),
                ),
                trailing:
                    c.runs.isNotEmpty &&
                        (c.runs.last['ambiguous_ids'] as List? ?? []).contains(
                          e['id'],
                        )
                    ? AppTextButton(
                        onPressed: conversationLocked || c.processing
                            ? null
                            : () => submit(
                                '选择「${e['title']}」（${entryTime(e)}），继续刚才的操作。',
                                selectedRecordIds: [e['id']],
                              ),
                        child: const Text('选这条'),
                      )
                    : const Icon(Icons.chevron_right, size: 20),
                onTap: () => openRecord(e),
              ),
            if (rows(d['undated']).isNotEmpty)
              Text(
                '另有${rows(d['undated']).length}项时间待确认',
                style: const TextStyle(color: CampusColors.muted),
              ),
          ],
        ),
      );
    }
    if (kind == 'analysis') {
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '安排概况',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                metric(
                  '占用时间',
                  '${(d['occupied_union_minutes'] as num? ?? 0) / 60}h',
                ),
                metric(
                  '个人计划',
                  '${(d['personal_planned_minutes'] as num? ?? 0) / 60}h',
                ),
                metric('实际投入', '未统计'),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '占用时间已扣除重叠部分。${d['undated_count'] ?? 0}项日期待确认。',
              style: const TextStyle(color: CampusColors.muted, fontSize: 13),
            ),
          ],
        ),
        color: CampusColors.blueSoft,
      );
    }
    if (kind == 'windows') {
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可用时段',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            for (final e in rows(d['windows']))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(entryTime(e)),
              ),
            if (rows(d['windows']).isEmpty)
              Text(
                rows(d['needs_input']).isNotEmpty
                    ? '有固定安排尚未确定起止时间，补齐后才能确认空闲时段。'
                    : '当前学习时间设置内没有找到足够长的空闲时段。',
              ),
          ],
        ),
        color: CampusColors.mint,
      );
    }
    return const SizedBox();
  }

  Widget metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      Text(
        label,
        style: const TextStyle(color: CampusColors.muted, fontSize: 12),
      ),
    ],
  );
  void openRecord(Map<String, dynamic> e) {
    final id = e['resource_type'] == 'course_occurrence'
        ? e['course_id']
        : e['resource_id'] ?? e['id'];
    if (id == null) return;
    final type = e['resource_type'];
    final route = type == 'event'
        ? '/events/$id'
        : type == 'course' || type == 'course_occurrence'
        ? '/courses/$id'
        : type == 'exam'
        ? '/exams/$id'
        : '/items/$id';
    context.push(route);
  }

  String entryTime(Map<String, dynamic> e) {
    if (e['start_at'] != null) {
      return '${displayInstant(e['start_at'])}${e['end_at'] != null ? ' — ${displayInstant(e['end_at'])}' : ''}';
    }
    if (e['due_at'] != null) return '${displayInstant(e['due_at'])}截止';
    final t = Map<String, dynamic>.from(e['time'] ?? {});
    if (t['at'] != null) {
      return '${displayInstant(t['at'])}${t['end_at'] != null ? ' — ${displayInstant(t['end_at'])}' : ''}';
    }
    if ((t['date'] ?? e['date']) != null) {
      final end = t['end_date'] ?? e['end_date'];
      return '${t['date'] ?? e['date']}${end != null ? ' 至 $end' : ''}';
    }
    if ((t['week'] ?? e['week']) != null) return '第${t['week'] ?? e['week']}周';
    return '时间待确认';
  }

  Widget changeDetails(Map<String, dynamic> run, Map<String, dynamic> p) {
    final detailRun = <String, dynamic>{
      ...run,
      'status': 'detail',
      'preview': p,
    };
    if (p['kind'] == 'course_change' ||
        p['kind'] == 'exam_change' && run['preview']['kind'] == 'batch') {
      return ChangeConfirmation(
        run: detailRun,
        controller: c,
        details: (child) => previewCard(detailRun, child),
      );
    }
    return previewCard(detailRun, p);
  }

  Widget previewCard(Map<String, dynamic> run, Map<String, dynamic> p) {
    final before = Map<String, dynamic>.from(p['before'] ?? {}),
        after = Map<String, dynamic>.from(p['after'] ?? {});
    final pending = run['status'] == 'needs_confirmation',
        applied = run['status'] == 'applied';
    final action = p['action'];
    final create = action == 'create';
    final title = after['title'] ?? before['title'] ?? p['title'] ?? '修改提醒';
    final labels = {
      'title': '名称',
      'time': '时间',
      'location': '地点',
      'reminder_minutes': '提醒',
      'remaining_minutes': '预计剩余',
      'splittable': '允许分段安排',
      'category_id': '分类',
      'tags': '标签',
      'priority': '优先级',
      'notes': '备注',
      'trigger_at': '提醒时刻',
      'lead_minutes': '提前提醒',
      'enabled': '启用提醒',
      'mode': '提醒方式',
      'purpose': '提醒用途',
      'start_policy': '最早开始',
      'earliest_start_at': '开始时刻',
      'reminders': '提醒',
      'certainty': '时间是否确定',
      'kind': '事项类型',
      'course_id': '关联课程',
    };
    final fields = labels.keys
        .where(
          (key) =>
              after.containsKey(key) &&
              (create
                  ? key != 'title' &&
                        after[key] != null &&
                        after[key] != '' &&
                        !(after[key] is List && (after[key] as List).isEmpty)
                  : jsonEncode(before[key]) != jsonEncode(after[key])),
        )
        .toList();
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                applied ? Icons.check_circle : Icons.edit_calendar_outlined,
                color: CampusColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  applied
                      ? '已保存'
                      : action == 'cancel'
                      ? '取消日程'
                      : create
                      ? '添加到日程'
                      : '修改预览',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final key in fields.where(
            (k) =>
                !create ||
                {
                  'time',
                  'location',
                  'reminder_minutes',
                  'reminders',
                }.contains(k),
          ))
            difference(labels[key]!, key, before, after, create),
          if (create)
            AppDisclosure(
              tilePadding: EdgeInsets.zero,
              title: const Text('更多设置与来源'),
              children: [
                for (final key in fields.where(
                  (k) => !{
                    'time',
                    'location',
                    'reminder_minutes',
                    'reminders',
                  }.contains(k),
                ))
                  difference(labels[key]!, key, before, after, true),
                if ((after['source_text'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(after['source_text']),
                  ),
              ],
            ),
          if (action == 'cancel') Text(entryTime(before)),
          if (rows(p['affected_blocks']).isNotEmpty)
            const Text('已有个人计划与这次修改有关，请核对后保存。'),
          if (pending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppOutlineButton(
                    onPressed: c.busy ? null : () => c.decide(run, false),
                    child: Text(
                      create
                          ? '暂不添加'
                          : action == 'cancel'
                          ? '保留安排'
                          : '暂不修改',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    onPressed: c.busy ? null : () => c.decide(run, true),
                    child: Text(
                      action == 'cancel'
                          ? '确认取消'
                          : create
                          ? '确认添加'
                          : '确认修改',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '有不对的地方，可以继续输入修改要求。',
              style: TextStyle(color: CampusColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget difference(
    String label,
    String key,
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    bool create,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, size) {
        final value = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!create && before.containsKey(key))
              Text(
                fieldValue(key, before[key]),
                style: const TextStyle(
                  color: CampusColors.muted,
                  decoration: TextDecoration.lineThrough,
                  fontSize: 14,
                ),
              ),
            Text(
              fieldValue(key, after[key]),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.4,
              ),
            ),
          ],
        );
        final name = Text(
          label,
          style: const TextStyle(color: CampusColors.muted, fontSize: 13),
        );
        if (size.maxWidth < 260 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [name, const SizedBox(height: 4), value],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 76, child: name),
            const SizedBox(width: 8),
            Expanded(child: value),
          ],
        );
      },
    ),
  );

  String fieldValue(String key, dynamic value) {
    if (value == null) return '未设置';
    if (key == 'certainty') {
      return {'formal': '已确定', 'tentative': '暂定', 'unknown': '待核实'}[value] ??
          '待核实';
    }
    if (key == 'kind') return kindLabel(value);
    if (key == 'course_id') {
      return widget.controller.courses
              .where((r) => r['id'] == value)
              .firstOrNull?['title'] ??
          '关联课程（名称待加载）';
    }
    if (key == 'time') return entryTime({'time': value});
    if (key == 'category_id') {
      return {
            'study': '学业',
            'research': '科研',
            'affairs': '校园事务',
            'life': '生活',
          }[value] ??
          '未分类';
    }
    if (key == 'priority') {
      return {'high': '高', 'normal': '普通', 'low': '低'}[value] ?? '普通';
    }
    if (key == 'start_policy') {
      return {'now': '现在起', 'at': '指定时刻', 'unconfirmed': '待确认'}[value] ?? '待确认';
    }
    if (key == 'trigger_at' || key == 'earliest_start_at') {
      return displayInstant(value);
    }
    if (key == 'mode') return value == 'absolute' ? '指定时刻' : '提前提醒';
    if (key == 'purpose') {
      return {
            'item': '事项提醒',
            'start_review': '开始复习',
            'check_notice': '核实通知',
          }[value] ??
          '事项提醒';
    }
    if (value is bool) return value ? '是' : '否';
    if (key == 'remaining_minutes' || key == 'lead_minutes') return '$value分钟';
    if (value is List) {
      if (value.isEmpty) return '未设置';
      if (key == 'reminder_minutes') {
        return value.map((v) => v == 0 ? '开始时' : '提前$v分钟').join('、');
      }
      if (key == 'reminders') {
        return value
            .map(
              (v) => v['mode'] == 'absolute'
                  ? displayInstant(v['trigger_at'])
                  : '提前${v['lead_minutes']}分钟',
            )
            .join('、');
      }
      return value.map((v) => v is Map ? v['name'] : v).join('、');
    }
    return '$value';
  }

  Widget planPreview(Map<String, dynamic> run, Map<String, dynamic> preview) {
    final result = Map<String, dynamic>.from(preview['after']);
    final blocks = rows(result['blocks']);
    final tasks = {
      for (final t in rows(preview['before']?['tasks'])) t['id']: t['title'],
    };
    final previous = {
      for (final b in rows(preview['before']?['blocks'])) b['id']: b,
    };
    final replan = preview['action'] == 'replan';
    final changed = replan
        ? blocks
              .where((b) => previous[b['id']]?['start_at'] != b['start_at'])
              .toList()
        : blocks;
    final missing = result['unarranged_minutes'] as num? ?? 0;
    final pending = run['status'] == 'needs_confirmation';
    final partial = missing > 0;
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                run['status'] == 'applied'
                    ? Icons.check_circle
                    : Icons.event_note_rounded,
                color: CampusColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  run['status'] == 'applied'
                      ? '已保存个人计划'
                      : replan
                      ? '调整个人计划'
                      : '个人计划预览',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            replan ? '${changed.length}段计划将调整时间' : '新增${blocks.length}段个人计划',
          ),
          for (final b in changed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b['title'] ?? tasks[b['item_id']] ?? '个人任务'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (replan && previous[b['id']] != null)
                    Text(
                      entryTime(previous[b['id']]!),
                      style: const TextStyle(
                        color: CampusColors.muted,
                        decoration: TextDecoration.lineThrough,
                        fontSize: 12,
                      ),
                    ),
                  Text(entryTime(b), style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          if (partial)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0D6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('还有$missing分钟没有排入日程。已有安排不会因此被自动延长。'),
            ),
          if (pending && partial)
            AppCheckRow(
              contentPadding: EdgeInsets.zero,
              title: const Text('先保存能安排的部分', style: TextStyle(fontSize: 14)),
              value: partialAcknowledged.contains(run['id']),
              onChanged: c.busy
                  ? null
                  : (v) => setState(() {
                      v == true
                          ? partialAcknowledged.add(run['id'])
                          : partialAcknowledged.remove(run['id']);
                    }),
            ),
          if (pending)
            Row(
              children: [
                Expanded(
                  child: AppOutlineButton(
                    onPressed: c.busy ? null : () => c.decide(run, false),
                    child: const Text('暂不安排'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    key: const Key('agent-plan-confirm'),
                    onPressed:
                        c.busy ||
                            (partial &&
                                !partialAcknowledged.contains(run['id']))
                        ? null
                        : () => c.decide(run, true),
                    child: Text(
                      partial
                          ? '确认部分安排'
                          : replan
                          ? '确认调整'
                          : '确认安排',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
