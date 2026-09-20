import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class MediaInput {
  Future<String?> image({bool recover = false});
  Future<bool> start();
  Future<String?> stop();
  Future<void> release(String path);
  Future<void> dispose();
}

class DeviceMediaInput implements MediaInput {
  final recorder = AudioRecorder();
  final picker = ImagePicker();
  String? recordingPath;
  final recordings = <String>{};
  bool disposed = false;
  @override
  Future<String?> image({bool recover = false}) async {
    if (recover) {
      if (!Platform.isAndroid) return null;
      final lost = await picker.retrieveLostData();
      return lost.files?.firstOrNull?.path;
    }
    if (Platform.isAndroid) await picker.retrieveLostData();
    return (await picker.pickImage(source: ImageSource.gallery))?.path;
  }

  @override
  Future<bool> start() async {
    if (!await recorder.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    recordingPath =
        '${dir.path}/semester-record-${DateTime.now().microsecondsSinceEpoch}.wav';
    recordings.add(recordingPath!);
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: recordingPath!,
    );
    return true;
  }

  @override
  Future<String?> stop() => recorder.stop();
  @override
  Future<void> release(String path) async {
    if (recordings.remove(path)) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    await recorder.cancel();
    await recorder.dispose();
    for (final path in recordings.toList()) {
      await release(path);
    }
  }
}
