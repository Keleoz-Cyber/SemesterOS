import 'package:semester_os/ui/forui_theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/tags/tag_management_page.dart';
import 'package:semester_os/features/tags/tag_picker_field.dart';
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
  testWidgets(
    'old-server labels are grouped locally and can be searched on a phone',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var organized = false;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/tags/organize')) {
          organized = true;
          f.revision = 2;
          return body({
            'owner_id': 'preview',
            'merged': 4,
            'renamed': 0,
            'semesters': [
              {'id': 's', 'revision': 2},
            ],
          });
        }
        if (r.path.endsWith('/tags')) {
          return body({
            'owner_id': 'preview',
            'tags': [
              for (final name in [
                'Python',
                '会议',
                '合唱',
                '实验作业',
                '座谈会',
                '彩排',
                '排练',
                '演出',
                '组会',
                '联排',
                '集合',
              ])
                if (!organized || !{'彩排', '联排', '座谈会', '组会'}.contains(name))
                  {'id': name, 'name': name, 'version': 1},
            ],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: TagManagementPage(controller: f.c),
        ),
      );
      final management =
          (tester.state(find.byType(TagManagementPage)) as dynamic).c
              as TagManagementController;
      for (var i = 0; i < 40 && management.busy; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(management.busy, isFalse);
      await tester.pumpAndSettle();
      expect(find.text('课程与学习 · 2'), findsOneWidget);
      expect(find.text('会议与交流 · 1'), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('已自动整理标签'), findsNothing);
      expect(find.text('重命名'), findsNothing);
      expect(find.text('Python'), findsOneWidget);
      expect(find.text('彩排'), findsNothing);
      expect(find.text('联排'), findsNothing);
      expect(find.text('确认合并'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('tag-management-search')),
        '彩排',
      );
      await tester.pumpAndSettle();
      expect(find.text('联排'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tag-group-arts')),
          matching: find.text('排练'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets('new-item recommendations remain available with no connection', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    await tester.runAsync(() => f.c.bind('s'));
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/tags')) return body({'message': '断网'}, 503);
      return old.respond(r);
    });
    List<String>? chosen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ShiriForuiTheme(child: child!),
        home: Scaffold(
          body: TagPickerField(
            controller: f.c,
            values: const [],
            contextData: () => {'title': '提交Python实验报告', 'kind': 'assignment'},
            onChanged: (v) => chosen = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择标签'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.text('根据内容推荐'), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('实验作业'), findsOneWidget);
    await tester.tap(find.text('Python'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认标签'));
    await tester.pumpAndSettle();
    expect(chosen, ['Python']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  test(
    'legacy server is reorganized automatically without presenting a preview',
    () async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var rows = <Map<String, dynamic>>[
        for (final n in ['彩排', '联排', '排练', '合唱', '组会', '座谈会', '会议', '班会'])
          {'id': n, 'name': n, 'version': 1},
      ];
      Map<String, dynamic>? pending;
      var writes = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/tags/organize')) {
          return body({'message': '旧版'}, 404);
        }
        if (r.path.endsWith('/tags')) {
          return body({'owner_id': 'preview', 'tags': rows});
        }
        if (r.path.endsWith('/tags/preview')) {
          pending = Map<String, dynamic>.from(r.data as Map);
          writes++;
          return body({'owner_id': 'preview', 'token': 'auto'});
        }
        if (r.path.endsWith('/tags/changes/auto/apply')) {
          rows = rows.where((t) => t['id'] != pending!['source_id']).toList();
          writes++;
          f.revision++;
          return body({
            'owner_id': 'preview',
            'semesters': [
              {'id': 's', 'revision': f.revision},
            ],
          });
        }
        return old.respond(r);
      });
      await f.c.bind('s');
      final c = TagManagementController(f.c);
      await c.load();
      expect(writes, 10);
      expect(c.preview, isNull);
      expect(c.error, isNull);
      expect(c.tags.map((t) => t['name']), ['排练', '合唱', '会议']);
      expect(c.notice, isNull);
      c.dispose();
      f.c.dispose();
    },
  );
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
    await tester.ensureVisible(find.byTooltip('管理论文'));
    await tester.tap(find.byTooltip('管理论文'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合并到'));
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
