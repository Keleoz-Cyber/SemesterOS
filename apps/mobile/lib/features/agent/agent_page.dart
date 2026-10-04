import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError, ApiFailure;
import '../../ui/performance_widgets.dart';
import '../../ui/empty_states.dart';
import '../../ui/motion.dart' show SkeletonLoader, EmptyState;
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
import 'agent_widgets.dart';
import 'agent_motion.dart';
import '../../ui/app_loading.dart';
import '../../ui/app_sheet.dart';
import 'agent_receipt.dart';
import 'conversation_session.dart';
import '../notices/notice_fields.dart';
import 'change_confirmation.dart';
import '../media/inline_capture_controller.dart';
import '../media/media_input.dart';
import '../planning/date_time_picker.dart';
import '../media/hold_voice_button.dart';
import '../media/source_view.dart';
import '../insights/insights_controller.dart' show insightHours;
import '../media/drafts.dart';
import 'workflow_cards.dart';
import '../media/incoming_notice_draft.dart';
import '../../app/controller.dart' show schoolNow;
import '../items/reminder_editor.dart';

class AgentPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final String? initialMediaKind;
  final String? initialText;
  final String? initialThreadId;
  final List<String> initialImagePaths;
  final String? initialDraftId;
  final List<String> initialRecordIds;
  final VoidCallback? onInitialDraftAccepted;
  final bool embedded, autoSubmit, autofocus;
  final bool initialNotice;
  final MediaInput? voiceInput, imageInput;
  const AgentPage({
    super.key,
    required this.controller,
    required this.semester,
    this.initialMediaKind,
    this.initialText,
    this.initialThreadId,
    this.initialImagePaths = const [],
    this.initialDraftId,
    this.initialRecordIds = const [],
    this.onInitialDraftAccepted,
    this.embedded = false,
    this.autoSubmit = false,
    this.autofocus = false,
    this.initialNotice = false,
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
  bool followingProgrammatically = false, followJumpScheduled = false;
  Timer? draftTimer;
  late final CaptureDrafts drafts;
  late String draftKey;
  late final String baseDraftKey, contextPointerKey;
  late ConversationSession session;
  Map<String, dynamic>? editingRun;
  bool followLatest = true;
  bool showingHistory = false;
  bool readyForDraft = false;
  late bool voiceMode = widget.initialMediaKind == 'audio';
  bool voiceRecording = false;
  Map<String, dynamic>? attachment;
  final List<String> pendingImages = [];
  String? imageRequestId, imageRequestSignature;
  String? importedDraftId;
  late bool noticeDraft = widget.initialNotice || widget.initialDraftId != null;
  bool detachedSource = false;
  Map<String, dynamic>? get currentSource =>
      attachment ?? (detachedSource ? null : c.activeSource);
  final Set<String> partialAcknowledged = {};
  final Set<String> expandedResults = {};
  final Set<String> _seenTurns = {}, _unshownArrivals = {};
  bool _receivingHistory = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = AgentController(widget.controller, widget.semester['id']);
    c.addListener(conversationChanged);
    conversationScroll.addListener(scrollChanged);
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
    draftKey = widget.initialText == null || widget.initialDraftId != null
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
                  (candidate['image_paths'] as List? ?? []).isNotEmpty ||
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
          (saved['image_paths'] as List? ?? []).isEmpty &&
          saved['pending_media'] != true &&
          saved['picking_image'] != true) {
        saved = null;
      }
    } catch (_) {
      /* Local storage failure does not disable online input. */
    }
    if (!mounted || !c.active) return;
    session = ConversationSessions.forContext(
      widget.controller.api,
      owner: widget.controller.owner!,
      generation: widget.controller.api.generation,
      semester: widget.semester['id'],
      context: draftKey,
    );
    editingRun = session.editingRun;
    final target = widget.initialThreadId ?? session.threadId;
    await c.open(id: target, fresh: target == null);
    if (!mounted || !c.active) return;
    _seenTurns.addAll(c.runs.map((run) => '${run['id']}'));
    if (saved != null) {
      input.text = saved['text'] ?? '';
      attachment = saved['source'] is Map
          ? Map<String, dynamic>.from(saved['source'])
          : null;
      detachedSource = saved['detached'] == true;
      mediaReferenceOverride = saved['media_reference_override'];
      transcriptAck = saved['media_transcript_ack'];
      pendingMediaDraft = saved['pending_media'] == true;
      pendingImages.addAll(
        (saved['image_paths'] as List? ?? []).whereType<String>(),
      );
      importedDraftId = saved['incoming_draft_id'];
      imageRequestId = saved['image_request_id'];
      imageRequestSignature = saved['image_request_signature'];
      noticeDraft = saved['notice_input'] == true || noticeDraft;
    }
    readyForDraft = true;
    session.threadId = c.threadId;
    restoringMedia = true;
    try {
      await media.restore(scope: draftKey);
    } finally {
      restoringMedia = false;
    }
    if (!mounted || !c.active) return;
    pendingMediaDraft = media.hasPending;
    if (widget.initialDraftId != null ||
        widget.initialImagePaths.isNotEmpty ||
        widget.initialNotice) {
      await acceptIncoming();
    }
    setState(() {});
    showLatest();
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

  @override
  void didUpdateWidget(covariant AgentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (readyForDraft && oldWidget.initialDraftId != widget.initialDraftId) {
      acceptIncoming();
    }
  }

  Future<void> acceptIncoming() async {
    if (!mounted || !c.active) return;
    if (widget.initialDraftId != null &&
        importedDraftId == widget.initialDraftId) {
      if (await saveDraft()) widget.onInitialDraftAccepted?.call();
      return;
    }
    final incoming = widget.initialText?.trim() ?? '';
    if (incoming.isNotEmpty && input.text.trim() != incoming) {
      input.text = [
        if (input.text.trim().isNotEmpty) input.text.trim(),
        incoming,
      ].join('\n\n');
    }
    for (final path in widget.initialImagePaths) {
      if (!pendingImages.contains(path)) pendingImages.add(path);
    }
    importedDraftId = widget.initialDraftId;
    noticeDraft = true;
    attachment = null;
    detachedSource = true;
    setState(() => voiceMode = false);
    if (await saveDraft()) widget.onInitialDraftAccepted?.call();
  }

  void mediaChanged() {
    if (mounted) setState(() {});
  }

  void scrollChanged() {
    if (conversationScroll.hasClients) {
      if (followingProgrammatically &&
          !conversationScroll.position.isScrollingNotifier.value) {
        return;
      }
      followLatest =
          conversationScroll.position.maxScrollExtent -
              conversationScroll.position.pixels <
          100;
    }
  }

  void conversationChanged() {
    if (!readyForDraft) return;
    if (c.loading || c.earlierLoading) {
      _receivingHistory = true;
      _unshownArrivals.clear();
    } else {
      final ids = c.runs.map((run) => '${run['id']}').toSet();
      if (!_receivingHistory) {
        _unshownArrivals.addAll(ids.difference(_seenTurns));
      }
      _seenTurns.addAll(ids);
      _receivingHistory = false;
    }
    session.threadId = c.threadId;
    session.editingRun = editingRun;
    if (followLatest) showLatest();
  }

  void showLatest() {
    if (followJumpScheduled || !followLatest) return;
    followJumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      followingProgrammatically = true;
      try {
        for (var i = 0; i < 8; i++) {
          if (!mounted || !conversationScroll.hasClients || !followLatest) {
            break;
          }
          final p = conversationScroll.position;
          if (p.extentAfter < 1) break;
          conversationScroll.jumpTo(p.maxScrollExtent);
          WidgetsBinding.instance.scheduleFrame();
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              !conversationScroll.hasClients ||
              conversationScroll.position.extentAfter < 1) {
            break;
          }
        }
      } finally {
        followingProgrammatically = false;
        followJumpScheduled = false;
      }
    });
  }

  void scheduleDraft() {
    if (!readyForDraft) return;
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 350), () => saveDraft());
  }

  Future<bool> saveDraft() async {
    final value = {
      'text': input.text,
      'notice_input': noticeDraft,
      'source': attachment,
      'detached': detachedSource,
      'thread_id': c.threadId,
      'media_reference_override': mediaReferenceOverride,
      'media_transcript_ack': transcriptAck,
      'pending_media': pendingMediaDraft || media.hasPending,
      'picking_image': pickingImage,
      'image_paths': pendingImages.toList(),
      'image_request_id': imageRequestId,
      'image_request_signature': imageRequestSignature,
      'incoming_draft_id': importedDraftId,
      if (editingRun != null) 'editing_run': editingRun,
      if (editingRun != null && session.editBackup != null)
        'edit_backup': session.editBackup,
    };
    final key = draftKey;
    session.threadId = c.threadId;
    session.editingRun = editingRun;
    try {
      await drafts.save(
        key,
        value,
        pointerKey: key == baseDraftKey ? null : contextPointerKey,
        activatePointer:
            (value['text'] as String).isNotEmpty ||
            value['source'] != null ||
            value['pending_media'] == true ||
            pendingImages.isNotEmpty ||
            value['picking_image'] == true,
      );
      if (c.threadId != null) {
        await drafts.save('$baseDraftKey:thread:${c.threadId}', value);
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('草稿未能保存，请保留输入内容')));
      }
      return false;
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
    conversationScroll.removeListener(scrollChanged);
    conversationScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    media.removeListener(mediaChanged);
    media.dispose();
    gallery?.dispose();
    c.removeListener(conversationChanged);
    c.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!readyForDraft ||
        !c.active ||
        c.loading ||
        c.busy ||
        mediaWorking ||
        pickingImage ||
        sendingMedia ||
        voiceRecording) {
      return;
    }
    final value = input.text.trim();
    if (value.isEmpty && pendingImages.isEmpty) return;
    if (c.processing) {
      for (final run
          in c.runs
              .where((r) => {'queued', 'running'}.contains(r['status']))
              .toList()) {
        await c.stop(run);
      }
      if (!mounted || c.processing) return;
    }
    final intendedThread = c.threadId;
    setState(() => sendingMedia = true);
    try {
      if (pendingImages.isNotEmpty) {
        final paths = pendingImages.toList();
        final signature = jsonEncode([paths, value, c.threadId]);
        if (imageRequestSignature != signature || imageRequestId == null) {
          imageRequestSignature = signature;
          imageRequestId =
              'images-${DateTime.now().microsecondsSinceEpoch}-${widget.controller.owner}';
        }
        if (!await saveDraft()) return;
        final accepted = await c.sendImages(
          paths,
          instruction: value,
          clientRequestId: imageRequestId,
        );
        if (accepted && mounted && c.active) {
          pendingImages.removeWhere(paths.contains);
          imageRequestId = imageRequestSignature = null;
          noticeDraft = false;
          if (input.text.trim() == value) input.clear();
          await releaseNoticeImages(paths);
          await saveDraft();
          if (mounted && c.active) setState(() {});
        }
        return;
      }
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
    final source = noticeDraft ? null : currentSource;
    final submittedMediaId = reviewedCapture ? (media.source?['id']) : null;
    final accepted = editingRun == null
        ? await c.send(
            text,
            inputKind: noticeDraft ? 'notice' : 'message',
            source: source,
            detachSource: detachedSource,
            selectedRecordIds: selectedRecordIds,
            contextRecordIds: widget.initialRecordIds,
          )
        : await c.revise(
            editingRun!,
            text,
            inputKind: noticeDraft ? 'notice' : 'message',
            source: source,
            detachSource: detachedSource,
          );
    if (accepted && mounted) {
      noticeDraft = false;
      if (input.text.trim() == text) input.clear();
      if (submittedMediaId != null && media.source?['id'] == submittedMediaId) {
        await media.detach();
      }
      if (!mounted || !c.active) return;
      setState(() {
        editingRun = null;
        session.editBackup = null;
        attachment = null;
        detachedSource = false;
        mediaReferenceOverride = null;
        pendingMediaDraft = media.hasPending;
        if (!pendingMediaDraft) transcriptAck = null;
      });
      if (readyForDraft) await saveDraft();
      followLatest = true;
      showLatest();
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
        final paths = await retainNoticeImages(
          await pickNoticeImages(gallery!, recover: recoverImage),
        );
        if (!mounted || !c.active || epoch != captureEpoch) return;
        for (final image in paths) {
          if (!pendingImages.contains(image)) pendingImages.add(image);
        }
        pickingImage = false;
        setState(() => voiceMode = false);
        await saveDraft();
        return;
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
        : failed ?? (media.kind == 'audio' ? '录音' : '原图');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: failed == null ? CampusColors.surface : CampusColors.errorSoft,
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
                  SizedBox(
                    width: 30,
                    height: 24,
                    child: mediaWorking
                        ? AppLoadingIndicator(label: status, compact: true)
                        : Icon(
                            media.kind == 'image'
                                ? Icons.image_outlined
                                : Icons.mic_none_rounded,
                            size: 20,
                            color: CampusColors.primary,
                          ),
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
                    guardAsync: false,
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
    final value = await showAppSheet<String>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '添加内容',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            AppTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CampusColors.blueSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: CampusColors.primary,
                ),
              ),
              title: const Text('从图片导入'),
              subtitle: const Text('选择通知截图'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            const Divider(height: 24),
            const Text(
              '手动添加',
              style: TextStyle(fontSize: 12, color: CampusColors.muted),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final choice in const [
                  ('event', '添加日程', Icons.event_outlined),
                  ('item', '添加待办', Icons.checklist_rounded),
                  ('exam', '添加考试', Icons.school_outlined),
                ])
                  AppTextButton.icon(
                    icon: Icon(choice.$3, size: 18),
                    label: Text(choice.$2.substring(2)),
                    onPressed: () => Navigator.pop(context, choice.$1),
                  ),
              ],
            ),
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
    await saveDraft();
    if (!mounted) return;
    setState(() => showingHistory = true);
    await c.loadHistory(reset: true);
  }

  Future<void> openHistory(String id) async {
    if (conversationLocked) return;
    await saveDraft();
    final saved = await drafts.read('$baseDraftKey:thread:$id');
    await c.open(id: id);
    if (!mounted || c.threadId != id) return;
    setState(() {
      input.text = saved?['text'] ?? '';
      pendingImages
        ..clear()
        ..addAll((saved?['image_paths'] as List? ?? []).whereType<String>());
      imageRequestId = saved?['image_request_id'];
      imageRequestSignature = saved?['image_request_signature'];
      noticeDraft = saved?['notice_input'] == true;
      attachment = saved?['source'] is Map
          ? Map<String, dynamic>.from(saved!['source'])
          : null;
      detachedSource = saved?['detached'] == true;
      editingRun = saved?['editing_run'] is Map
          ? Map<String, dynamic>.from(saved!['editing_run'])
          : null;
      session.editBackup = saved?['edit_backup'] is Map
          ? Map<String, dynamic>.from(saved!['edit_backup'])
          : null;
      mediaReferenceOverride = saved?['media_reference_override'];
      transcriptAck = saved?['media_transcript_ack'];
      showingHistory = false;
    });
    followLatest = true;
    await saveDraft();
    showLatest();
  }

  Future<void> newConversation() async {
    if (conversationLocked) return;
    await saveDraft();
    await c.open(fresh: true);
    if (!mounted) return;
    setState(() {
      editingRun = null;
      session.editBackup = null;
      showingHistory = false;
      input.clear();
      pendingImages.clear();
      imageRequestId = imageRequestSignature = null;
      noticeDraft = false;
      attachment = null;
      detachedSource = false;
      mediaReferenceOverride = null;
      transcriptAck = null;
    });
    followLatest = true;
    await saveDraft();
    composerFocus.requestFocus();
  }

  Future<void> editMessage(Map<String, dynamic> run) async {
    if (conversationLocked || run['context_only'] == true) return;
    if (c.processing) {
      for (final pending
          in c.runs
              .where((r) => {'queued', 'running'}.contains(r['status']))
              .toList()) {
        await c.stop(pending);
      }
      if (!mounted || c.processing) return;
    }
    session.editBackup ??= {
      'text': input.text,
      'notice_input': noticeDraft,
      'source': attachment,
      'detached': detachedSource,
      'media_reference_override': mediaReferenceOverride,
      'media_transcript_ack': transcriptAck,
    };
    setState(() {
      editingRun = run;
      noticeDraft = run['input_kind'] == 'notice';
      input.text = run['text'] ?? '';
      attachment = run['source'] is Map
          ? Map<String, dynamic>.from(run['source'])
          : null;
      detachedSource = attachment == null;
      voiceMode = false;
    });
    await saveDraft();
    composerFocus.requestFocus();
  }

  void cancelEditing() {
    final old = session.editBackup;
    setState(() {
      editingRun = null;
      input.text = old?['text'] ?? '';
      noticeDraft = old?['notice_input'] == true;
      attachment = old?['source'] is Map
          ? Map<String, dynamic>.from(old!['source'])
          : null;
      detachedSource = old?['detached'] == true;
      mediaReferenceOverride = old?['media_reference_override'];
      transcriptAck = old?['media_transcript_ack'];
      session.editBackup = null;
    });
    scheduleDraft();
  }

  Future<void> earlierMessages() async {
    followLatest = false;
    final oldMax = conversationScroll.hasClients
        ? conversationScroll.position.maxScrollExtent
        : 0.0;
    final oldOffset = conversationScroll.hasClients
        ? conversationScroll.offset
        : 0.0;
    await c.loadEarlier();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && conversationScroll.hasClients) {
        conversationScroll.jumpTo(
          (oldOffset + conversationScroll.position.maxScrollExtent - oldMax)
              .clamp(0.0, conversationScroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        toolbarHeight: MediaQuery.textScalerOf(context).scale(1) > 1.4
            ? 76
            : 60,
        leading: showingHistory
            ? AppIconButton(
                tooltip: '返回对话',
                onPressed: () => setState(() => showingHistory = false),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : widget.embedded
            ? AppIconButton(
                tooltip: '收起输入',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              )
            : AppIconButton(
                tooltip: '返回主页',
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              showingHistory ? '历史对话' : '助手',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if ('${widget.semester['name'] ?? ''}'.isNotEmpty)
              Text(
                widget.semester['name'],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: CampusColors.muted),
              ),
          ],
        ),
        actions: [
          if (!showingHistory)
            AppIconButton(
              tooltip: '最近对话',
              onPressed: conversationLocked ? null : history,
              icon: const Icon(Icons.history_rounded),
            ),
          AppIconButton(
            tooltip: '新对话',
            onPressed: conversationLocked ? null : newConversation,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: showingHistory ? historyList() : conversationList(),
            ),
            if (c.error != null)
              AssistantInlineError(
                text: c.error!,
                onRetry: () => showingHistory
                    ? c.loadHistory(reset: true)
                    : c.processing
                    ? c.poll()
                    : c.open(id: c.threadId, fresh: c.threadId == null),
              ),
            if (!showingHistory && editingRun != null)
              Padding(
                padding: const EdgeInsets.only(left: 18, right: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: CampusColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        editingRun!['status'] == 'applied'
                            ? '编辑消息，已保存的安排保持原样'
                            : '编辑消息',
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.muted,
                        ),
                      ),
                    ),
                    AppIconButton(
                      tooltip: '取消编辑',
                      onPressed: cancelEditing,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            if (!showingHistory && currentSource != null && !media.hasPending)
              Padding(
                padding: const EdgeInsets.only(left: 18, right: 8),
                child: Row(
                  children: [
                    AppTextButton.icon(
                      onPressed: () => sourceView(currentSource!),
                      icon: Icon(
                        currentSource!['kind'] == 'image'
                            ? Icons.image_outlined
                            : Icons.mic_none_rounded,
                        size: 17,
                      ),
                      label: Text(
                        currentSource!['kind'] == 'image' ? '图片通知' : '语音记录',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      tooltip: '移除本次附件',
                      onPressed: c.busy
                          ? null
                          : () => setState(() {
                              attachment = null;
                              detachedSource = true;
                            }),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            if (!showingHistory) composer(),
          ],
        ),
      ),
    ),
  );

  Widget conversationList() {
    if (c.loading || !readyForDraft) {
      return const Center(child: AppLoadingIndicator(label: '正在读取对话'));
    }
    final uploadingImages = sendingMedia && pendingImages.isNotEmpty;
    final batch =
        c.mediaRun != null && (c.mediaProcessing || c.mediaStatus == 'failed');
    final capture =
        uploadingImages ||
        batch ||
        media.hasPending ||
        media.error != null ||
        captureError != null ||
        pickingImage;
    final welcome = c.runs.isEmpty && !capture;
    final leading = c.hasMoreRuns ? 1 : 0;
    return VirtualizedListView<int>(
      key: const Key('agent-messages'),
      controller: conversationScroll,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      items: List<int>.generate(
        leading + (welcome ? 1 : 0) + c.runs.length + (capture ? 1 : 0),
        (i) => i,
      ),
      itemBuilder: (context, entry, _) {
        var index = entry;
        if (leading == 1 && index == 0) {
          return AppTextButton(
            onPressed: c.earlierLoading ? null : earlierMessages,
            child: Text(c.earlierLoading ? '正在读取…' : '查看更早消息'),
          );
        }
        index -= leading;
        if (welcome && index == 0) {
          return ListenableBuilder(
            listenable: Listenable.merge([input, composerFocus]),
            builder: (context, _) {
              // The enclosing sheet already consumes keyboard insets. Focus
              // also covers that resized viewport without hiding any messages.
              if (input.text.trim().isNotEmpty ||
                  composerFocus.hasFocus ||
                  MediaQuery.viewInsetsOf(context).bottom > 0) {
                return const SizedBox.shrink();
              }
              return AssistantWelcome(
                choices: [
                  schoolNow().hour >= 17
                      ? ('明天的安排', '我明天有哪些安排？', Icons.wb_twilight_rounded)
                      : ('接下来做什么', '我接下来有哪些安排？', Icons.today_outlined),
                  if (widget.controller.items.any(
                    (i) => i['lifecycle'] == 'active' && i['kind'] != 'exam',
                  ))
                    ('最近截止', '有哪些任务快截止了？', Icons.flag_outlined)
                  else
                    ('本周空闲', '这周哪天有一小时空闲？', Icons.schedule_rounded),
                ],
                onPrompt: (text) {
                  input.text = text;
                  composerFocus.requestFocus();
                },
              );
            },
          );
        }
        if (welcome) index--;
        if (index < c.runs.length) {
          final run = c.runs[index];
          final id = '${run['id']}';
          return AssistantArrival(
            key: ValueKey('agent-turn-arrival-$id'),
            animateInitial: _unshownArrivals.contains(id),
            onInitialConsumed: () => _unshownArrivals.remove(id),
            child: AgentTurnFeedback(
              key: ValueKey('agent-turn-$id'),
              status: '${run['status']}',
              child: turnView(run),
            ),
          );
        }
        if (uploadingImages) {
          return AssistantActivity(stage: '正在上传${pendingImages.length}张图片');
        }
        if (batch) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.mediaProcessing)
                AssistantActivity(
                  stage: '${c.mediaRun?['stage'] ?? '正在识别图片'}',
                  onStop: c.cancelMedia,
                )
              else
                AssistantInlineError(
                  text: '图片识别未完成，可以重试或输入通知文字',
                  onRetry: () => c.retryMedia(),
                ),
            ],
          );
        }
        return captureStatus();
      },
    );
  }

  Widget historyList() {
    if (c.historyLoading && c.threads.isEmpty) {
      return ListView(
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SkeletonLoader(width: double.infinity, height: 64),
            ),
        ],
      );
    }
    if (c.threads.isEmpty) {
      if (c.error != null) {
        return Center(
          child: DataLoadError(onRetry: () => c.loadHistory(reset: true)),
        );
      }
      return const Center(
        child: EmptyState(
          title: '还没有历史对话',
          icon: Icons.chat_bubble_outline_rounded,
        ),
      );
    }
    return LazyLoadList<Map<String, dynamic>>(
      pagingKey:
          '${widget.controller.owner}:${widget.semester['id']}:${widget.controller.api.generation}',
      items: c.threads,
      hasMore: c.hasMoreThreads,
      itemKey: (row) => ValueKey('history-${row['id']}'),
      onLoadMore: () async {
        await c.loadHistory();
        if (c.error != null) throw ApiFailure(c.error!);
        return c.threads;
      },
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      separatorBuilder: (_) =>
          const Divider(height: 1, color: CampusColors.line),
      endWidget: const SizedBox.shrink(),
      errorBuilder: (context, error, retry) =>
          AppTextButton(onPressed: retry, child: const Text('读取未完成，重试')),
      itemBuilder: (context, thread, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (historyDay(thread).isNotEmpty &&
              (index == 0 ||
                  historyDay(c.threads[index - 1]) != historyDay(thread)))
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
              child: Text(
                historyDay(thread),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CampusColors.muted,
                ),
              ),
            ),
          AppTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 2,
              vertical: 8,
            ),
            leading: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: CampusColors.muted,
              size: 20,
            ),
            title: Text(
              thread['title'] ?? '对话',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: thread['updated_at'] == null
                ? null
                : Text(
                    noticeClock(thread['updated_at'], clockOnly: true),
                    style: const TextStyle(
                      fontSize: 12,
                      color: CampusColors.muted,
                    ),
                  ),
            trailing: const Icon(Icons.chevron_right_rounded, size: 19),
            onTap: () => openHistory(thread['id']),
          ),
        ],
      ),
    );
  }

  String historyDay(Map<String, dynamic> thread) {
    final at = DateTime.tryParse('${thread['updated_at'] ?? ''}');
    if (at == null) return '';
    final day = at.toUtc().add(const Duration(hours: 8));
    final now = schoolNow();
    final delta = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(day.year, day.month, day.day)).inDays;
    return delta == 0
        ? '今天'
        : delta == 1
        ? '昨天'
        : noticeDate(
            '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
          );
  }

  Widget composer() {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final blocked =
        !readyForDraft ||
        !c.active ||
        c.loading ||
        c.busy ||
        voiceRecording ||
        mediaWorking ||
        pickingImage ||
        sendingMedia;
    final field = Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      ),
      child: FTextField(
        key: const Key('agent-input'),
        style: FTextFieldStyleDelta.delta(
          color: FVariants(Colors.transparent, variants: {}),
          border: FVariants(InputBorder.none, variants: {}),
          contentPadding: const EdgeInsetsGeometryDelta.value(
            EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
          contentTextStyle: FVariants(
            TextStyle(
              fontSize: 16,
              height: 1.45,
              color: CampusColors.ink,
              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
            variants: {},
          ),
        ),
        control: FTextFieldControl.managed(controller: input),
        focusNode: composerFocus,
        minLines: 1,
        maxLines: landscape || MediaQuery.sizeOf(context).height < 300
            ? 1
            : MediaQuery.viewInsetsOf(context).bottom > 0 ||
                  MediaQuery.sizeOf(context).height < 500
            ? 2
            : 4,
        enabled:
            readyForDraft &&
            c.active &&
            !c.loading &&
            !media.busy &&
            !sendingMedia,
        maxLength: 10000,
        hint: '输入通知或问题',
        counterBuilder: (_, _, _, _) => null,
      ),
    );
    final toggle = AppIconButton(
      tooltip: voiceMode ? '切换键盘输入' : '切换语音输入',
      onPressed: blocked || c.processing
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
      guardAsync: false,
      onPressed: blocked || c.processing ? null : moreInput,
      icon: const Icon(Icons.add_circle_outline_rounded),
    );
    final submit = ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (_, value, _) => AppIconButton.filled(
        tooltip: '发送',
        onPressed:
            c.loading ||
                blocked ||
                (value.text.trim().isEmpty && pendingImages.isEmpty)
            ? null
            : send,
        icon: const Icon(Icons.arrow_upward_rounded),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: ListenableBuilder(
        listenable: composerFocus,
        builder: (context, child) => AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: CampusColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: composerFocus.hasFocus
                  ? CampusColors.primary
                  : CampusColors.line,
            ),
          ),
          child: child,
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
                  if (pendingImages.isNotEmpty) imageStrip(),
                  field,
                  Row(children: [toggle, const Spacer(), more, submit]),
                ],
              ),
      ),
    );
  }

  Widget imageStrip() => SizedBox(
    height: 88,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final path in pendingImages)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 6, right: 4),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(path),
                    width: 68,
                    height: 76,
                    fit: BoxFit.cover,
                    cacheWidth: 192,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 68,
                      child: Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: AppIconButton(
                    tooltip: '移除第${pendingImages.indexOf(path) + 1}张图片',
                    onPressed: sendingMedia
                        ? null
                        : () async {
                            setState(() => pendingImages.remove(path));
                            await releaseNoticeImages([path]);
                            await saveDraft();
                          },
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget turnView(Map<String, dynamic> run) {
    final working = {'queued', 'running'}.contains(run['status']);
    final p = run['preview'];
    final contextOnly = run['context_only'] == true;
    final applied = run['status'] == 'applied';
    final source = run['source'] is Map
        ? Map<String, dynamic>.from(run['source'])
        : null;
    final shortSource = source != null && run['text'] == '请根据这份通知整理安排，先给我预览';
    final message = shortSource
        ? (source['kind'] == 'image' ? '整理这张通知' : '整理这段录音')
        : '${run['text'] ?? ''}';
    final answer = '${run['answer'] ?? ''}';
    final hasResponse =
        answer.isNotEmpty ||
        p is Map ||
        rows(run['cards']).isNotEmpty ||
        run['error'] != null ||
        {'applied', 'cancelled', 'superseded'}.contains(run['status']);
    final responseRevision = hasResponse
        ? jsonEncode([
            answer,
            p is Map ? p['token'] : null,
            '${run['status']}',
            for (final card in rows(run['cards']))
              [card['card_id'], card['kind']],
            run['error'],
          ])
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AssistantUserMessage(
            text: message,
            attachment: source == null
                ? null
                : source['kind'] == 'image'
                ? '图片通知'
                : '语音记录',
            onSource: source == null ? null : () => sourceView(source),
            onEdit: conversationLocked || contextOnly
                ? null
                : () => editMessage(run),
          ),
          if (working)
            AssistantActivity(
              stage: run['stage'] ?? '正在整理',
              onStop: () => c.stop(run),
            ),
          AssistantArrival(
            key: ValueKey('agent-response-${run['id']}'),
            revision: responseRevision,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!applied &&
                    answer.isNotEmpty &&
                    (p is! Map || answer != '请核对这次修改，确认后保存。'))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AgentAnswer(answer),
                  ),
                if (applied)
                  AssistantSavedAction(
                    text: savedActionMessage(run),
                    onOpen: contextOnly ? null : () => openSaved(run),
                    onUndo:
                        contextOnly ||
                            run['undo_available'] != true ||
                            conversationLocked ||
                            c.processing
                        ? null
                        : () => c.requestUndo(run),
                  ),
                if (!contextOnly &&
                    p is Map &&
                    !{
                      'applied',
                      'cancelled',
                      'superseded',
                    }.contains(run['status']))
                  p['kind'] == 'plan'
                      ? planPreview(run, Map<String, dynamic>.from(p))
                      : {
                              'course_change',
                              'exam_change',
                              'item_state',
                              'batch',
                              'undo',
                            }.contains(p['kind']) ||
                            p['kind'] == 'event' && p['action'] == 'restore'
                      ? ChangeConfirmation(
                          key: ValueKey(p['token']),
                          run: run,
                          controller: c,
                          details: (child) => changeDetails(run, child),
                        )
                      : previewCard(run, Map<String, dynamic>.from(p)),
                if (!applied && p is Map && rows(run['cards']).isNotEmpty)
                  AppDisclosure(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('关联安排'),
                    children: [
                      for (final card in rows(run['cards']))
                        factCard(run, card),
                    ],
                  )
                else if (!applied)
                  for (final card in rows(run['cards'])) factCard(run, card),
                if (run['error'] != null)
                  AssistantInlineError(
                    text: '${run['error']}',
                    onRetry: contextOnly || conversationLocked
                        ? null
                        : () => retryMessage(run),
                  ),
                if (run['undone_by'] != null)
                  const Text(
                    '已撤销',
                    style: TextStyle(color: CampusColors.muted, fontSize: 12),
                  ),
                if (run['status'] == 'cancelled' && answer.isEmpty)
                  const Text(
                    '已停止',
                    style: TextStyle(color: CampusColors.muted, fontSize: 12),
                  ),
                if (run['status'] == 'superseded')
                  const Text(
                    '已重新整理',
                    style: TextStyle(color: CampusColors.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void openSaved(Map<String, dynamic> run) {
    final receipt = noticeMap(run['receipt']);
    for (final key in ['event', 'item']) {
      final record = receipt[key];
      if (record is Map && record['id'] != null) {
        openRecord({
          ...Map<String, dynamic>.from(record),
          'resource_type': key,
        });
        return;
      }
    }
    context.push('/calendar');
  }

  Future<void> retryMessage(Map<String, dynamic> run) async {
    final source = run['source'] is Map
        ? Map<String, dynamic>.from(run['source'])
        : null;
    if (await c.revise(run, '${run['text'] ?? ''}', source: source) &&
        mounted) {
      followLatest = true;
      await saveDraft();
      showLatest();
    }
  }

  Widget panel(Widget child, {Color color = Colors.white}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: CampusColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: CampusColors.line),
      ),
      child: Padding(padding: const EdgeInsets.all(15), child: child),
    ),
  );

  Widget factCard(Map<String, dynamic> run, Map<String, dynamic> card) {
    final d = Map<String, dynamic>.from(card['data'] ?? {});
    final kind = card['kind'];
    if (kind == 'schedule_setup') {
      return ScheduleSetupCard(
        key: ValueKey('setup-${run['id']}'),
        data: d,
        controller: widget.controller,
        onReady: () => submit(
          '按刚确认的预计用时和学习时段，生成安排方案。',
          selectedRecordIds: rows(d['tasks'])
              .where(
                (t) =>
                    t['can_schedule'] != false &&
                    (run['ambiguous_ids'] as List? ?? []).contains(t['id']),
              )
              .map((t) => '${t['id']}')
              .toList(),
        ),
      );
    }
    if (kind == 'forwarding_draft') {
      return ForwardingDraftCard(
        key: ValueKey('forward-${run['id']}'),
        text: '${d['text'] ?? ''}',
      );
    }
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
            if (d['from_date'] != null && d['to_date'] != null)
              Text(
                '${noticeDate(d['from_date'])} — ${noticeDate(d['to_date'])}',
                style: const TextStyle(color: CampusColors.muted, fontSize: 12),
              ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: [
                if (summary['fixed_scheduled_minutes'] is num)
                  metric(
                    '固定安排',
                    insightHours(summary['fixed_scheduled_minutes']),
                  ),
                if (summary['personal_planned_minutes'] is num)
                  metric(
                    '个人计划',
                    insightHours(summary['personal_planned_minutes']),
                  ),
                if (summary['actual_minutes'] is num)
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
      final entries = [
        ...rows(
          d[kind == 'calendar'
              ? 'entries'
              : kind == 'course_occurrences'
              ? 'occurrences'
              : 'records'],
        ),
        if (kind == 'calendar') ...rows(d['undated']),
      ];
      final resultKey = '${run['id']}:${card['card_id'] ?? kind}';
      final shown = expandedResults.contains(resultKey)
          ? entries
          : entries.take(3).toList();
      final total =
          card['total_count'] as int? ??
          d['total_count'] as int? ??
          entries.length;
      final loading = c.loadingCards.contains(resultKey);
      // The answer already states the empty result. Keep diagnostics and any
      // incompletely loaded query, rather than repeating an empty white card.
      bool hasNotice(dynamic value) => switch (value) {
        null => false,
        bool v => v,
        String v => v.trim().isNotEmpty,
        List v => v.isNotEmpty,
        Map v => v.isNotEmpty,
        _ => true,
      };
      const attentionKeys = {
        'warning',
        'warnings',
        'uncertainty_warnings',
        'fixed_conflicts',
        'conflicts',
        'needs_input',
        'stale',
        'is_stale',
        'error',
        'errors',
        'truncated',
        'messages',
      };
      final hasAttention = [
        card,
        d,
      ].any((value) => attentionKeys.any((key) => hasNotice(value[key])));
      const queryMetadata = {
        'entries',
        'undated',
        'records',
        'occurrences',
        'total_count',
        'cached_count',
        'semester_id',
        'revision',
        'queried_revision',
        'from_date',
        'to_date',
        'categories',
        'navigation_query',
        'has_more',
        'next_offset',
      };
      final hasExtraFacts = d.entries.any(
        (entry) =>
            !queryMetadata.contains(entry.key) &&
            !attentionKeys.contains(entry.key) &&
            hasNotice(entry.value),
      );
      if (run['status'] == 'completed' &&
          '${run['answer'] ?? ''}'.trim().isNotEmpty &&
          entries.isEmpty &&
          total == 0 &&
          card['has_more'] != true &&
          d['has_more'] != true &&
          card['next_offset'] == null &&
          !loading &&
          !hasAttention &&
          !hasExtraFacts &&
          run['error'] == null) {
        return const SizedBox.shrink();
      }
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entries.any(
                    (e) => (c.runs.lastOrNull?['ambiguous_ids'] as List? ?? [])
                        .contains(e['id']),
                  )
                  ? '选择要处理的安排'
                  : kind == 'calendar'
                  ? '相关安排'
                  : '相关事项',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            if (kind == 'calendar' &&
                d['from_date'] != null &&
                d['to_date'] != null)
              Text(
                d['from_date'] == d['to_date']
                    ? noticeDate(d['from_date'])
                    : '${noticeDate(d['from_date'])} — ${noticeDate(d['to_date'])}',
                style: const TextStyle(color: CampusColors.muted, fontSize: 12),
              ),
            if (entries.isEmpty && total == 0)
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
            for (final e in shown)
              AppTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  switch (e['resource_type']) {
                    'course' || 'course_occurrence' => Icons.school_outlined,
                    'exam' => Icons.assignment_outlined,
                    'event' => Icons.event_outlined,
                    _ => Icons.checklist_rounded,
                  },
                  size: 20,
                  color: CampusColors.primary,
                ),
                title: Text(e['title'] ?? '日程'),
                subtitle:
                    entryTime(e).isEmpty &&
                        (e['location'] == null || e['location'] == '')
                    ? null
                    : Text(
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
            if (shown.length < entries.length)
              AppTextButton(
                onPressed: () => setState(() => expandedResults.add(resultKey)),
                child: Text('再显示${entries.length - shown.length}项'),
              ),
            if (shown.length == entries.length && card['has_more'] == true)
              AppTextButton(
                onPressed: loading
                    ? null
                    : () async {
                        followLatest = false;
                        setState(() => expandedResults.add(resultKey));
                        await c.loadCard('${run['id']}', card);
                      },
                child: Text(loading ? '正在读取…' : '查看更多 · 共$total项'),
              ),
            if (total > entries.length && card['has_more'] != true)
              Text(
                '显示${entries.length}项，可缩小日期或名称继续查询',
                style: const TextStyle(color: CampusColors.muted, fontSize: 12),
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
                if (d['occupied_union_minutes'] is num)
                  metric('占用时间', insightHours(d['occupied_union_minutes'])),
                if (d['personal_planned_minutes'] is num)
                  metric('个人计划', insightHours(d['personal_planned_minutes'])),
              ],
            ),
          ],
        ),
        color: CampusColors.blueSoft,
      );
    }
    if (kind == 'windows') {
      final windows = rows(d['windows']);
      final key = '${run['id']}:${card['card_id'] ?? kind}';
      final shown = expandedResults.contains(key)
          ? windows
          : windows.take(3).toList();
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '可用时段',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            for (final e in shown)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: CampusColors.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 19,
                      color: CampusColors.teal,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        entryTime(e),
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            if (shown.length < windows.length)
              AppTextButton(
                onPressed: () => setState(() => expandedResults.add(key)),
                child: Text('再显示${windows.length - shown.length}项'),
              ),
            if (shown.length == windows.length && card['has_more'] == true)
              AppTextButton(
                onPressed: c.loadingCards.contains(key)
                    ? null
                    : () {
                        followLatest = false;
                        setState(() => expandedResults.add(key));
                        c.loadCard('${run['id']}', card);
                      },
                child: Text(c.loadingCards.contains(key) ? '正在读取…' : '查看更多'),
              ),
            if (rows(d['windows']).isEmpty)
              Text(
                rows(d['needs_input']).isNotEmpty
                    ? '部分安排没有完整时间，可按已知安排继续查看。'
                    : '当前学习时间设置内没有找到足够长的空闲时段。',
              ),
          ],
        ),
        color: CampusColors.mint,
      );
    }
    if (kind == 'recent_actions') {
      final actions = rows(d['actions']);
      final key = '${run['id']}:${card['card_id'] ?? kind}';
      final shown = expandedResults.contains(key)
          ? actions
          : actions.take(3).toList();
      return panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '最近操作',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            for (final action in shown)
              AppTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${action['text'] ?? '已保存的安排'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${noticeClock(action['created_at'])}${action['undone'] == true ? ' · 已撤销' : ''}',
                ),
                onTap: conversationLocked ? null : () => openAction(action),
                trailing:
                    action['has_undo_record'] == true &&
                        action['undone'] != true
                    ? AppTextButton(
                        onPressed: conversationLocked || c.processing
                            ? null
                            : () => openAction(action, undo: true),
                        child: const Text('撤销'),
                      )
                    : const Icon(Icons.chevron_right_rounded),
              ),
            if (shown.length < actions.length)
              AppTextButton(
                onPressed: () => setState(() => expandedResults.add(key)),
                child: Text('再显示${actions.length - shown.length}项'),
              ),
            if (shown.length == actions.length && card['has_more'] == true)
              AppTextButton(
                onPressed: c.loadingCards.contains(key)
                    ? null
                    : () {
                        followLatest = false;
                        setState(() => expandedResults.add(key));
                        c.loadCard('${run['id']}', card);
                      },
                child: const Text('查看更多'),
              ),
          ],
        ),
      );
    }
    return const SizedBox();
  }

  Future<void> openAction(
    Map<String, dynamic> action, {
    bool undo = false,
  }) async {
    final stamp = c.contextVersion;
    try {
      final value = Map<String, dynamic>.from(
        await c.request('GET', '/agent/runs/${action['id']}'),
      );
      if (!mounted || !c.active || stamp != c.contextVersion) return;
      await openHistory(value['thread_id']);
      if (undo && mounted && c.active && c.threadId == value['thread_id']) {
        await c.requestUndo(value);
      }
    } catch (e) {
      if (mounted && c.active) {
        c.error = userError(e);
        c.emit();
      }
    }
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
    final t = Map<String, dynamic>.from(e['time'] ?? {});
    if (e['start_at'] != null) {
      return noticeTime({...t, 'at': e['start_at'], 'end_at': e['end_at']});
    }
    if (e['due_at'] != null) {
      return noticeTime({...t, 'at': e['due_at'], 'meaning': 'deadline'});
    }
    return noticeTime(
      {
        ...t,
        if (t['date'] == null && e['date'] != null) 'date': e['date'],
        if (t['end_date'] == null && e['end_date'] != null)
          'end_date': e['end_date'],
        if (t['week'] == null && e['week'] != null) 'week': e['week'],
        if (t['expression'] == null && e['expression'] != null)
          'expression': e['expression'],
      },
      task: {
        'item',
        'task',
        'assignment',
        'deadline',
      }.contains(e['resource_type'] ?? e['kind']),
    );
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
    return previewCard(detailRun, {
      ...p,
      if (p['action'] == 'restore') '_compact': true,
    });
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
      'start_policy': '开始条件',
      'earliest_start_at': '开始时刻',
      'reminders': '提醒',
      'certainty': '通知状态',
      'reserve_time': '参加安排',
      'details': '通知信息',
      'kind': '事项类型',
      'lifecycle': '状态',
      'course_id': '关联课程',
    };
    final fields = labels.keys
        .where(
          (key) =>
              after.containsKey(key) &&
              (create
                  ? !{
                          'title',
                          'category_id',
                          'tags',
                          'kind',
                          'certainty',
                          'splittable',
                        }.contains(key) &&
                        key != 'reserve_time' &&
                        key != 'details' &&
                        (p['provided_fields'] == null ||
                            (p['provided_fields'] as List).contains(key) ||
                            {
                              'time',
                              'location',
                              'reminders',
                              'reminder_minutes',
                            }.contains(key)) &&
                        after[key] != null &&
                        after[key] != '' &&
                        !(key == 'notes' &&
                            {'title', 'source_text'}.any(
                              (field) =>
                                  '${after[field] ?? ''}'.trim() ==
                                  '${after[key]}'.trim(),
                            )) &&
                        !(key == 'time' && !noticeTimePresent(after[key])) &&
                        !(key == 'certainty' && after[key] == 'unknown') &&
                        !(key == 'start_policy' &&
                            after[key] == 'unconfirmed') &&
                        !(key == 'priority' && after[key] == 'normal') &&
                        !(after[key] is List && (after[key] as List).isEmpty)
                  : jsonEncode(before[key]) != jsonEncode(after[key])),
        )
        .toList();
    Widget wrap(Widget child) => p['_compact'] == true
        ? Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 10),
            child: child,
          )
        : panel(child);
    return wrap(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p['_compact'] != true)
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
                        ? {'task', 'assignment'}.contains(after['kind'])
                              ? '添加待办'
                              : after['kind'] == 'exam'
                              ? '添加考试'
                              : after['reserve_time'] == false
                              ? '保存为参考'
                              : '添加到日程'
                        : '修改预览',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          if (p['_compact'] != true) const SizedBox(height: 14),
          if (p['_hide_title'] != true)
            Text(
              title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
          if (create &&
              after['certainty'] == 'tentative' &&
              !'$title'.contains('暂定'))
            const Text(
              '暂定',
              style: TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          if (create ||
              jsonEncode(before['details']) == jsonEncode(after['details']))
            NoticeDetails(
              after['details'],
              location: after['location'],
              title: '$title',
            ),
          const SizedBox(height: 12),
          for (final key in fields.where(
            (k) =>
                (!create && !(action == 'restore' && k == 'lifecycle')) ||
                {
                  'time',
                  'location',
                  'reminder_minutes',
                  'reminders',
                }.contains(k),
          ))
            difference(labels[key]!, key, before, after, create),
          if (create &&
              fields.any(
                (k) => !{
                  'time',
                  'location',
                  'reminder_minutes',
                  'reminders',
                  'kind',
                }.contains(k),
              ))
            AppDisclosure(
              tilePadding: EdgeInsets.zero,
              title: const Text('更多信息'),
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
              ],
            ),
          if (action == 'restore') ...[
            Text(entryTime(after)),
            if ('${after['location'] ?? ''}'.isNotEmpty)
              Text('${after['location']}'),
          ],
          if (action == 'cancel') Text(entryTime(before)),
          if (p['kind'] == 'item_state' && p['action'] != 'active')
            const Text('同时关闭这条事项的提醒。'),
          if (rows(p['affected_blocks']).isNotEmpty) ...[
            Text(
              p['kind'] == 'item_state'
                  ? '同时取消 ${rows(p['affected_blocks']).length} 段后续计划'
                  : '涉及 ${rows(p['affected_blocks']).length} 段个人计划',
            ),
            for (final block in rows(p['affected_blocks']).take(3))
              Text(
                '${displayInstant(block['start_at'])} — ${displayInstant(block['end_at'])}${block['locked'] == true ? ' · 已固定' : ''}',
              ),
            if (rows(p['affected_blocks']).length > 3)
              AppDisclosure(
                title: const Text('查看全部关联计划'),
                children: [
                  for (final block in rows(p['affected_blocks']).skip(3))
                    Text(
                      '${displayInstant(block['start_at'])} — ${displayInstant(block['end_at'])}${block['locked'] == true ? ' · 已固定' : ''}',
                    ),
                ],
              ),
          ],
          if (pending) ...[
            if (create && noticeMap(after['time'])['at'] != null)
              Align(
                alignment: Alignment.centerLeft,
                child: AppTextButton.icon(
                  onPressed: c.busy
                      ? null
                      : () async {
                          final r = await editReminder(
                            context,
                            kind: after['kind'] ?? 'event',
                            relativeOnly: true,
                          );
                          if (r == null || !mounted || !c.active) return;
                          await c.revise(
                            run,
                            '保留刚才核对的安排，加上提前${r['lead_minutes']}分钟提醒。',
                          );
                        },
                  icon: const Icon(Icons.notifications_none_rounded, size: 18),
                  label: const Text('设置提醒'),
                  guardAsync: false,
                ),
              ),
            const SizedBox(height: 12),
            confirmationActions(run, create: create, action: action),
          ],
        ],
      ),
    );
  }

  Widget confirmationActions(
    Map<String, dynamic> run, {
    required bool create,
    dynamic action,
  }) => LayoutBuilder(
    builder: (context, size) {
      final cancel = AppOutlineButton(
        onPressed: c.busy ? null : () => c.decide(run, false),
        child: Text(
          create
              ? '暂不添加'
              : action == 'cancel'
              ? '保留安排'
              : '暂不修改',
        ),
      );
      final confirm = AppButton(
        onPressed: c.busy ? null : () => c.decide(run, true),
        child: Text(
          action == 'cancel'
              ? '确认取消'
              : create
              ? '确认添加'
              : '确认修改',
        ),
      );
      if (size.maxWidth < 280 ||
          MediaQuery.textScalerOf(context).scale(16) > 22) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [confirm, const SizedBox(height: 8), cancel],
        );
      }
      return Row(
        children: [
          Expanded(child: cancel),
          const SizedBox(width: 10),
          Expanded(child: confirm),
        ],
      );
    },
  );

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
    if (value == null || value == '') return '已清除';
    if (key == 'lifecycle') {
      return {'active': '待完成', 'completed': '已完成', 'cancelled': '已取消'}[value] ??
          '$value';
    }
    if (key == 'reserve_time') return value == true ? '预留时间' : '仅作参考';
    if (key == 'details') {
      final rows = noticeDetailRows(value);
      return rows.isEmpty
          ? '已清除'
          : rows.map((row) => '${row.label}：${row.value}').join('\n');
    }
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
    if (key == 'time') {
      return entryTime({'time': value}).isEmpty
          ? '不设具体时间'
          : entryTime({'time': value});
    }
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
      if (value.isEmpty) return '已清除';
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
          for (final warning in rows(result['uncertainty_warnings']))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${warning['message']}',
                style: const TextStyle(
                  fontSize: 13,
                  color: CampusColors.warning,
                ),
              ),
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
                color: CampusColors.warningSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('还有 $missing 分钟未安排'),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final cancel = AppOutlineButton(
                  onPressed: c.busy ? null : () => c.decide(run, false),
                  child: const Text('暂不安排'),
                );
                final confirm = AppButton(
                  key: const Key('agent-plan-confirm'),
                  onPressed:
                      c.busy ||
                          (partial && !partialAcknowledged.contains(run['id']))
                      ? null
                      : () => c.decide(run, true),
                  child: Text(
                    partial
                        ? '确认部分安排'
                        : replan
                        ? '确认调整'
                        : '确认安排',
                  ),
                );
                if (constraints.maxWidth < 280 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [confirm, const SizedBox(height: 8), cancel],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: cancel),
                    const SizedBox(width: 10),
                    Expanded(child: confirm),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
