import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'controller_test.dart' show MemoryStore;

void main() {
  test('deleting one semester clears only its saved input drafts', () async {
    final cache = MemoryStore();
    cache.data['capture:a'] = {
      'assistant:s1': {'text': '旧学期通知'},
      'assistant-context:s1:abc': {'text': '旧学期上下文'},
      'assistant-context-latest:s1': {'key': 'assistant-context:s1:abc'},
      'text:s1': {'text': '旧文字'},
      'inline:s1': {'text': '旧语音'},
      'operation:s1:item': {'text': '旧操作'},
      'assistant:s2': {'text': '其他学期通知'},
    };
    await CaptureDrafts.clearSemester(cache, 'a', 's1');
    expect(cache.data['capture:a']!.keys, ['assistant:s2']);
  });
}
