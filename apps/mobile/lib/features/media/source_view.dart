import '../../ui/app_controls.dart';
import '../../ui/detail_widgets.dart';
import '../items/item_widgets.dart' show displayInstant;
import '../../core/api.dart' show userError;
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../items/items_controller.dart';
import '../../ui/campus_widgets.dart';

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
  late final generation = widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    load();
  }

  void changed() {
    if (generation != widget.controller.api.generation) {
      player.stop();
      if (mounted) {
        setState(() {
          source = null;
          bytes = null;
        });
      }
    }
  }

  Future<void> load() async {
    try {
      final s = Map<String, dynamic>.from(
        await widget.controller.api.request('GET', '/sources/${widget.id}'),
      );
      if (!mounted || generation != widget.controller.api.generation) return;
      setState(() => source = s);
      if (s['file_deleted'] == true) return;
      final content = await widget.controller.api.request(
        'GET',
        '/sources/${widget.id}/content',
        responseType: ResponseType.bytes,
      );
      if (!mounted || generation != widget.controller.api.generation) return;
      final data = Uint8List.fromList(List<int>.from(content));
      if (s['kind'] == 'audio') {
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/source-play-${DateTime.now().microsecondsSinceEpoch}.wav',
        );
        temp = file.path;
        await file.writeAsBytes(data);
        if (!mounted || generation != widget.controller.api.generation) {
          await file.delete();
          return;
        }
        await player.setFilePath(file.path);
      } else {
        bytes = data;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    releasePlayback().catchError((_) {});
    super.dispose();
  }

  Future<void> releasePlayback() async {
    await player.dispose();
    final path = temp;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('删除原图 / 原录音？'),
        content: const Text('将删除账号中保存的原图或录音。识别文字、修改记录和已保存的事项会保留。'),
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
    if (yes != true || generation != widget.controller.api.generation) return;
    try {
      final r = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'DELETE',
          '/sources/${widget.id}/content',
          data: {'expected_version': source!['version']},
        ),
      );
      await player.stop();
      if (mounted) {
        setState(() {
          source = r;
          bytes = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('原始来源')),
    body: generation != widget.controller.api.generation
        ? const Center(child: Text('账号已切换，请返回'))
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (source != null)
                RecordHeading(
                  title: source!['kind'] == 'image' ? '图片通知' : '语音记录',
                  label: '原始来源',
                  icon: source!['kind'] == 'image'
                      ? Icons.image_outlined
                      : Icons.mic_none_rounded,
                  subtitle: displayInstant(
                    source!['reference_at'] ?? source!['created_at'],
                  ),
                ),
              if (error != null) SoftNotice(error!, warning: true),
              if (source == null && error == null)
                const LinearProgressIndicator(),
              if (source?['file_deleted'] == true)
                const SoftNotice('原文件已删除，以下识别文字与历史仍保留'),
              if (bytes != null)
                InteractiveViewer(
                  child: Image.memory(bytes!, cacheWidth: 1800),
                ),
              if (source?['kind'] == 'audio' &&
                  temp != null &&
                  source?['file_deleted'] != true)
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, s) => AppTextButton.icon(
                    onPressed: () async {
                      if (player.playing) {
                        await player.pause();
                      } else {
                        await player.seek(Duration.zero);
                        player.play();
                      }
                    },
                    icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
                    label: const Text('播放 / 暂停原录音'),
                  ),
                ),
              if (source != null) ...[
                const SizedBox(height: 20),
                DocumentPanel(title: '你确认的文字', text: source!['text'] ?? ''),
                DocumentPanel(
                  title: 'AI识别的原文',
                  text: source!['original_text'] ?? '',
                ),
              ],
              if (source != null && source!['file_deleted'] != true)
                AppTextButton(
                  onPressed: remove,
                  child: const Text('删除原文件，保留文字与历史'),
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
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await player.setFilePath(widget.path);
      if (mounted) setState(() => ready = true);
    } catch (_) {
      if (mounted) setState(() => error = '本机录音暂时无法回放');
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (error != null) Text(error!),
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
                    player.play();
                  }
                },
          icon: Icon(player.playing ? Icons.pause : Icons.play_arrow),
          label: const Text('回放 / 暂停本机录音'),
        ),
      ),
    ],
  );
}
