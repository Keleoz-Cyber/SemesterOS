import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'controller_test.dart' show MemoryStore;

class MediaTestPaths extends PathProviderPlatform {
  MediaTestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Map<String, dynamic> source(String id) => {
  'id': id,
  'semester_id': 's',
  'kind': 'image',
  'version': 1,
  'status': 'recognized',
  'text': id == 'a' ? '周五交Java实验报告' : '周日提交数学作业',
  'original_text': id == 'a' ? '周五交Java实验报告' : '周日提交数学作业',
  'reference_at': '2026-09-20T00:00:00+00:00',
  'created_at': '2026-09-20T00:00:00+00:00',
  'file_deleted': false,
  'recognition': {},
};
void main() {
  test(
    'drafts survive store recreation and late old-account saves are ignored',
    () async {
      final cache = MemoryStore();
      var valid = true;
      final a = CaptureDrafts(cache, 'a', () => valid);
      await a.save('text:s', {'text': '草稿'});
      expect(
        (await CaptureDrafts(cache, 'a', () => true).read('text:s'))!['text'],
        '草稿',
      );
      valid = false;
      await a.save('text:s', {'text': '迟到写入'});
      expect(
        await CaptureDrafts(cache, 'b', () => true).read('text:s'),
        isNull,
      );
      expect(
        (await CaptureDrafts(cache, 'a', () => true).read('text:s'))!['text'],
        '草稿',
      );
    },
  );
}
