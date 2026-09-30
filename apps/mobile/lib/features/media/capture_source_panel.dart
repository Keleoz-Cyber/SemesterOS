import '../../ui/app_controls.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import '../../ui/motion.dart';

class CaptureSourcePanel extends StatelessWidget {
  final bool image, recording;
  final String? path;
  final int seconds;
  final VoidCallback? onPick, onRecord;
  final String recordLabel;
  const CaptureSourcePanel({
    super.key,
    required this.image,
    required this.recording,
    required this.seconds,
    this.path,
    this.onPick,
    this.onRecord,
    required this.recordLabel,
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppMotion.change(context),
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: BoxDecoration(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border(
        top: BorderSide(
          color: image ? CampusColors.primary : CampusColors.teal,
          width: 3,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (image) ...[
          if (path != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(path!),
                height: 180,
                cacheWidth: 1400,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('本机找不到原图，可重新选择或查看已上传来源'),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                size: 44,
                color: CampusColors.primary,
              ),
            ),
          const SizedBox(height: 12),
          AppOutlineButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.image_outlined),
            label: Text(path == null ? '选择通知图片' : '重新选图'),
          ),
        ] else ...[
          Semantics(
            liveRegion: false,
            label: recording ? '正在录音，已录制$seconds秒' : '尚未录音',
            child: Column(
              children: [
                Icon(
                  recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                  size: 44,
                  color: recording ? CampusColors.error : CampusColors.teal,
                ),
                const SizedBox(height: 10),
                Text(
                  recording
                      ? '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
                      : '说出事项和时间',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: CampusColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton.icon(
            onPressed: onRecord,
            style: FilledButton.styleFrom(backgroundColor: CampusColors.teal),
            icon: Icon(recording ? Icons.stop_circle_outlined : Icons.mic_none),
            label: Text(recordLabel),
          ),
          if (recording)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('录音中，切到后台会停止；最长2分钟。'),
            ),
        ],
      ],
    ),
  );
}
