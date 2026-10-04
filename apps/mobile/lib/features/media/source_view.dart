import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart' show userError;
import '../../ui/accessibility.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/campus_theme.dart';
import '../../ui/empty_states.dart';
import '../../ui/motion.dart';
import '../../ui/performance_widgets.dart';
import '../items/item_widgets.dart' show displayInstant;
import '../items/items_controller.dart';
import 'notice_paper.dart';

class SourceViewPage extends StatefulWidget {
  final ItemsController controller;
  final String id;
  const SourceViewPage({super.key, required this.controller, required this.id});
  @override
  State<SourceViewPage> createState() => _SourceViewPageState();
}

class _SourceViewPageState extends State<SourceViewPage> {
  Map<String, dynamic>? source;
  Uint8List? bytes;
  String? error, temp;
  final player = AudioPlayer();
  late int generation = widget.controller.api.generation;
  int _request = 0;
  bool loading = true, removing = false;
  bool get currentOwner => generation == widget.controller.api.generation;
  Object get imageOwner => (widget.controller.api, generation, widget.id);
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant SourceViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.id != widget.id) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
      _request++;
      generation = widget.controller.api.generation;
      source = null;
      bytes = null;
      error = null;
      unawaited(load());
    }
  }

  void changed() {
    if (!currentOwner) {
      _request++;
      unawaited(_clearPlayback());
      if (mounted) {
        setState(() {
          source = null;
          bytes = null;
          loading = false;
        });
      }
    }
  }

  Future<void> _clearPlayback() async {
    final path = temp;
    temp = null;
    try {
      await player.stop();
    } catch (_) {}
    if (path != null) {
      final file = File(path);
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> load() async {
    if (!currentOwner) return;
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    await _clearPlayback();
    if (!mounted || !currentOwner || request != _request) return;
    try {
      final s = Map<String, dynamic>.from(
        await widget.controller.api.request('GET', '/sources/${widget.id}'),
      );
      if (!mounted || !currentOwner || request != _request) return;
      setState(() {
        source = s;
        bytes = null;
      });
      if (s['file_deleted'] == true || s['is_image_batch'] == true) return;
      final content = await widget.controller.api.request(
        'GET',
        '/sources/${widget.id}/content',
        responseType: ResponseType.bytes,
      );
      if (!mounted || !currentOwner || request != _request) return;
      final data = Uint8List.fromList(List<int>.from(content));
      if (data.isEmpty) throw const FormatException('原文件没有内容');
      if (s['kind'] == 'audio') {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/source-play-${DateTime.now().microsecondsSinceEpoch}.wav',
        );
        await file.writeAsBytes(data);
        if (!mounted || !currentOwner || request != _request) {
          await file.delete();
          return;
        }
        temp = file.path;
        await player.setFilePath(file.path);
        if (!mounted || !currentOwner || request != _request) return;
      } else {
        bytes = data;
      }
    } catch (e) {
      if (mounted && currentOwner && request == _request) {
        setState(() => error = userError(e));
      }
    } finally {
      if (mounted && currentOwner && request == _request) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    _request++;
    widget.controller.removeListener(changed);
    unawaited(releasePlayback().catchError((_) {}));
    super.dispose();
  }

  Future<void> releasePlayback() async {
    await _clearPlayback();
    await player.dispose();
  }

  Future<void> remove() async {
    final identity = (widget.controller, widget.id, generation);
    final expectedVersion = source?['version'];
    if (expectedVersion == null || !currentOwner) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(source?['kind'] == 'audio' ? '删除原录音？' : '删除原图片？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (source?['is_image_batch'] == true)
              Text('删除这份通知的 ${source?['image_count']} 张原图。'),
            const Text(
              '识别文字、修改记录和已保存安排仍会保留。',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: CampusColors.muted,
              ),
            ),
          ],
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除原文件'),
          ),
        ],
      ),
    );
    if (yes != true ||
        !mounted ||
        !currentOwner ||
        identity != (widget.controller, widget.id, generation)) {
      return;
    }
    setState(() => removing = true);
    try {
      final r = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'DELETE',
          '/sources/${widget.id}/content',
          data: {'expected_version': expectedVersion},
        ),
      );
      if (!mounted ||
          !currentOwner ||
          identity != (widget.controller, widget.id, generation)) {
        return;
      }
      _request++;
      await _clearPlayback();
      if (mounted &&
          currentOwner &&
          identity == (widget.controller, widget.id, generation)) {
        setState(() {
          source = r;
          bytes = null;
          loading = false;
          error = null;
        });
        ScreenReaderAnnouncement.announceSuccess(
          '原文件已删除，文字与历史已保留',
          context: context,
        );
      }
    } catch (e) {
      if (mounted &&
          currentOwner &&
          identity == (widget.controller, widget.id, generation)) {
        setState(() => error = userError(e));
        ScreenReaderAnnouncement.announceError(error!, context: context);
      }
    } finally {
      if (mounted) setState(() => removing = false);
    }
  }

  Future<void> sourceActions() async {
    final delete = await showAppSheet<bool>(
      context: context,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '原文件',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: CampusColors.error,
              ),
              title: const Text('删除原文件'),
              subtitle: const Text('保留文字和已保存安排'),
              onTap: () => Navigator.pop(sheet, true),
            ),
          ],
        ),
      ),
    );
    if (delete == true && mounted && currentOwner) await remove();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('原始来源'),
      actions: [
        if (currentOwner && source != null && source?['file_deleted'] != true)
          AppIconButton(
            tooltip: '来源操作',
            guardAsync: false,
            onPressed: loading || removing ? null : sourceActions,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
      ],
    ),
    body: !currentOwner
        ? const EmptyState(
            icon: Icons.person_outline_rounded,
            title: '账号已切换',
            message: '请返回后重新打开来源',
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (source != null)
                SemanticCard(
                  label: '原始来源',
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: CampusColors.blueSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            source!['kind'] == 'image'
                                ? Icons.image_outlined
                                : Icons.mic_none_rounded,
                            size: 22,
                            color: CampusColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                source!['kind'] == 'image' ? '图片通知' : '语音记录',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayInstant(
                                  source!['reference_at'] ??
                                      source!['created_at'],
                                ),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: CampusColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: const BoxDecoration(
                    color: CampusColors.warningSoft,
                    border: Border(
                      left: BorderSide(color: CampusColors.warning, width: 3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: CampusColors.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            error!,
                            style: const TextStyle(fontSize: 14, height: 1.5),
                          ),
                        ),
                      ),
                      AppTextButton(onPressed: load, child: const Text('重试')),
                    ],
                  ),
                ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: SkeletonLoader(width: double.infinity, height: 180),
                ),
              if (source?['file_deleted'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 20,
                        color: CampusColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '原文件已删除，文字已保留',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (bytes != null)
                InteractiveViewer(
                  child: OptimizedImage.memory(
                    bytes: bytes!,
                    ownerGeneration: imageOwner,
                    semanticLabel: '通知原图',
                    fit: BoxFit.contain,
                    errorWidget: ErrorState(message: '原图暂时无法显示', onRetry: load),
                  ),
                ),
              if (source?['is_image_batch'] == true &&
                  source?['file_deleted'] != true)
                for (
                  var index = 0;
                  index < (source!['image_count'] as num? ?? 0).toInt();
                  index++
                )
                  _SourceImage(
                    key: ValueKey('${widget.id}:$index:${source!['version']}'),
                    controller: widget.controller,
                    id: widget.id,
                    index: index,
                    count: (source!['image_count'] as num).toInt(),
                    version: source!['version'] as int,
                  ),
              if (source?['kind'] == 'audio' &&
                  temp != null &&
                  source?['file_deleted'] != true)
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, s) => _SourceAudioPlayback(
                    player: player,
                    onPressed: () async {
                      final identity = imageOwner;
                      try {
                        if (player.playing) {
                          await player.pause();
                        } else {
                          if (player.processingState ==
                              ProcessingState.completed) {
                            await player.seek(Duration.zero);
                          }
                          unawaited(
                            player.play().catchError((Object e) {
                              if (mounted &&
                                  currentOwner &&
                                  identity == imageOwner) {
                                setState(() => error = userError(e));
                              }
                            }),
                          );
                        }
                      } catch (e) {
                        if (mounted && currentOwner && identity == imageOwner) {
                          setState(() => error = userError(e));
                        }
                      }
                    },
                  ),
                ),
              if (!loading &&
                  error == null &&
                  source?['kind'] == 'audio' &&
                  temp == null &&
                  source?['file_deleted'] != true)
                const EmptyState(
                  icon: Icons.mic_off_outlined,
                  title: '暂无可播放录音',
                ),
              if (source != null) ...[
                const SizedBox(height: 20),
                if ((source!['text'] ?? '').toString().trim().isNotEmpty)
                  NoticePaper(title: '通知文字', text: source!['text']),
                if ((source!['original_text'] ?? '')
                        .toString()
                        .trim()
                        .isNotEmpty &&
                    source!['original_text'] != source!['text'])
                  AppDisclosure(
                    title: const Text('最初识别文字'),
                    children: [
                      SelectableText(
                        source!['original_text'] ?? '',
                        style: const TextStyle(fontSize: 16, height: 1.7),
                      ),
                    ],
                  ),
              ],
            ],
          ),
  );
}

class _SourceAudioPlayback extends StatelessWidget {
  final AudioPlayer player;
  final Future<void> Function() onPressed;
  const _SourceAudioPlayback({required this.player, required this.onPressed});
  String clock(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.positionStream,
    initialData: player.position,
    builder: (context, snapshot) {
      final position = snapshot.data ?? Duration.zero;
      final duration = player.duration;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CampusColors.surface,
          border: Border.all(color: CampusColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            AppIconButton.filled(
              tooltip: player.playing ? '暂停原录音' : '播放原录音',
              guardAsync: false,
              onPressed: onPressed,
              icon: Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '原录音',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${clock(position)}${duration == null ? '' : ' / ${clock(duration)}'}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CampusColors.muted,
                    ),
                  ),
                  if (duration != null && duration.inMilliseconds > 0) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      minHeight: 3,
                      value: (position.inMilliseconds / duration.inMilliseconds)
                          .clamp(0, 1),
                      color: CampusColors.primary,
                      backgroundColor: CampusColors.line,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SourceImage extends StatefulWidget {
  final ItemsController controller;
  final String id;
  final int index, count, version;
  const _SourceImage({
    super.key,
    required this.controller,
    required this.id,
    required this.index,
    required this.count,
    required this.version,
  });
  @override
  State<_SourceImage> createState() => _SourceImageState();
}

class _SourceImageState extends State<_SourceImage> {
  Uint8List? bytes;
  String? error;
  bool loading = true;
  late final generation = widget.controller.api.generation;
  int _request = 0;
  bool get currentOwner => generation == widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (!currentOwner) {
      _request++;
      if (mounted) {
        setState(() {
          bytes = null;
          loading = false;
          error = null;
        });
      }
    }
  }

  Future<void> load() async {
    if (!currentOwner) return;
    final request = ++_request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final content = await widget.controller.api.request(
        'GET',
        '/sources/${widget.id}/images/${widget.index}',
        responseType: ResponseType.bytes,
      );
      if (!mounted || !currentOwner || request != _request) return;
      final data = Uint8List.fromList(List<int>.from(content));
      if (data.isEmpty) throw const FormatException('原图没有内容');
      setState(() => bytes = data);
    } catch (e) {
      if (mounted && currentOwner && request == _request) {
        setState(() => error = userError(e));
      }
    } finally {
      if (mounted && currentOwner && request == _request) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    _request++;
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '第 ${widget.index + 1} / ${widget.count} 张',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        if (!currentOwner)
          const EmptyState(icon: Icons.person_outline_rounded, title: '账号已切换')
        else if (loading)
          const SkeletonLoader(width: double.infinity, height: 180)
        else if (error != null)
          DataLoadError(onRetry: load, errorMessage: error)
        else if (bytes != null)
          InteractiveViewer(
            child: OptimizedImage.memory(
              bytes: bytes!,
              ownerGeneration: (
                widget.controller.api,
                generation,
                widget.id,
                widget.version,
              ),
              semanticLabel: '通知原图第${widget.index + 1}张，共${widget.count}张',
              errorWidget: ErrorState(message: '原图暂时无法显示', onRetry: load),
            ),
          ),
      ],
    ),
  );
}

class LocalAudioPreview extends StatefulWidget {
  final String path;
  const LocalAudioPreview({super.key, required this.path});
  @override
  State<LocalAudioPreview> createState() => _LocalAudioPreviewState();
}

class _LocalAudioPreviewState extends State<LocalAudioPreview> {
  final player = AudioPlayer();
  bool ready = false;
  String? error;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant LocalAudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) unawaited(load());
  }

  Future<void> load() async {
    final request = ++_request;
    setState(() {
      ready = false;
      error = null;
    });
    try {
      await player.stop();
      await player.setFilePath(widget.path);
      if (mounted && request == _request) setState(() => ready = true);
    } catch (_) {
      if (mounted && request == _request) setState(() => error = '本机录音暂时无法回放');
    }
  }

  @override
  void dispose() {
    _request++;
    unawaited(player.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null) DataLoadError(onRetry: load, errorMessage: error),
      if (!ready && error == null) const LoadingDots(),
      StreamBuilder<PlayerState>(
        stream: player.playerStateStream,
        builder: (context, s) => AppTextButton.icon(
          onPressed: !ready
              ? null
              : () async {
                  if (player.playing) {
                    await player.pause();
                  } else {
                    await player.seek(Duration.zero);
                    final request = _request;
                    unawaited(
                      player.play().catchError((Object _) {
                        if (mounted && request == _request) {
                          setState(() => error = '本机录音暂时无法回放');
                        }
                      }),
                    );
                  }
                },
          icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          label: Text(player.playing ? '暂停本机录音' : '回放本机录音'),
        ),
      ),
    ],
  );
}
