import 'package:semester_os/ui/forui_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/tags/tag_management_page.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show ioTap;

const tagRows = [
  {'id': 'a', 'name': '论文', 'version': 1},
  {'id': 'b', 'name': '科研', 'version': 1},
];

Map<String, dynamic> tagPreview() => {
  'owner_id': 'preview',
  'token': 'change',
  'operation': 'merge',
  'source': tagRows[0],
  'target': tagRows[1],
  'affected': {'items': 2, 'events': 1, 'plans': 3, 'progress': 4},
  'semesters': [
    {'id': 's', 'name': '秋季学期', 'revision': 1},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'confirmation refreshes revision and network retry keeps bound token',
    () async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var attempts = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/tags')) {
          return body({'owner_id': 'preview', 'tags': tagRows});
        }
        if (r.path.endsWith('/tags/preview')) return body(tagPreview());
        if (r.path.endsWith('/tags/changes/change/apply')) {
          attempts++;
          if (attempts == 1) return body({'message': '网络中断，请重试'}, 503);
          f.revision = 2;
          return body({
            'owner_id': 'preview',
            'token': 'change',
            'tag': tagRows[1],
            'semesters': [
              {'id': 's', 'revision': 2},
            ],
          });
        }
        return old.respond(r);
      });
      await f.c.bind('s');
      final c = TagManagementController(f.c);
      await c.load();
      await c.prepare('a', targetId: 'b');
      expect(attempts, 0);
      await c.apply();
      expect(c.preview?['token'], 'change');
      await c.apply();
      expect(attempts, 2);
      expect(c.preview, isNull);
      expect(f.c.itemsRevision, 2);
      c.dispose();
      f.c.dispose();
    },
  );

  test(
    'late preview from old account cannot apply or remain visible',
    () async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final slow = Completer<dynamic>();
      var applied = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/tags/preview')) return await slow.future;
        if (r.path.endsWith('/apply')) applied++;
        return old.respond(r);
      });
      await f.c.bind('s');
      final c = TagManagementController(f.c);
      final pending = c.prepare('a', targetId: 'b');
      f.api.session = account('other');
      f.c.changed();
      f.api.session = account('preview');
      f.c.changed();
      slow.complete(body(tagPreview()));
      await pending;
      expect(c.active, isFalse);
      expect(c.preview, isNull);
      await c.apply();
      expect(applied, 0);
      c.dispose();
      f.c.dispose();
    },
  );

  testWidgets('merge shows affected history before a single confirmation', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    var applied = 0;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/tags')) {
        return body({'owner_id': 'preview', 'tags': tagRows});
      }
      if (r.path.endsWith('/tags/preview')) return body(tagPreview());
      if (r.path.endsWith('/apply')) applied++;
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ShiriForuiTheme(child: child!),
        home: TagManagementPage(controller: f.c),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并到').first);
    await tester.pumpAndSettle();
    await ioTap(tester, find.text('科研').last);
    expect(find.text('确认合并'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tag-impact-progress')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );
    expect(find.text('历史进度'), findsOneWidget);
    expect(find.textContaining('秋季学期'), findsOneWidget);
    expect(applied, 0);
    await tester.tap(find.text('取消预览'));
    await tester.pumpAndSettle();
    expect(applied, 0);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
