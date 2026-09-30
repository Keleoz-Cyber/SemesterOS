import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'package:semester_os/features/agent/assistant_sheet.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount;
import 'centers_flow_test.dart' show settleIo;
import 'package:semester_os/features/media/drafts.dart';

void main() {
  testWidgets('navigation has one accessible label and a usable tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 0;
    await mount(
      tester,
      Scaffold(
        bottomNavigationBar: AppNavigation(
          selected: 0,
          onSelected: (v) => selected = v,
        ),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('日程'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(selected, 1);
    semantics.dispose();
  });
  testWidgets('an already sent context action can be invoked again', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    var sent = 0;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/agent/threads?')) return body([]);
      if (r.path.endsWith('/agent/threads')) return body({'id': 'thread'});
      if (r.path.endsWith('/turns')) {
        sent++;
        return body({
          'id': 'r',
          'status': 'completed',
          'text': r.data['text'],
          'answer': '已查询',
          'cards': [],
        });
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    const request = '检查今晚安排';
    final key = 'assistant-context:s:${base64Url.encode(utf8.encode(request))}';
    await tester.runAsync(
      () => CaptureDrafts(
        f.c.cache,
        'preview',
        () => true,
      ).save(key, {'text': '', 'thread_id': 'previous'}),
    );
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openAssistantSheet(
              context,
              controller: f.c,
              semester: const {'id': 's'},
              initialText: request,
              autoSubmit: true,
            ),
            child: const Text('安排'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('安排'));
    await settleIo(tester);
    expect(sent, 1);
    expect(find.text('已查询'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'context follow-up draft survives closing without replacing an unrelated draft',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      final drafts = CaptureDrafts(f.c.cache, 'preview', () => true);
      await tester.runAsync(
        () => drafts.save('assistant:s', {'text': '原来的通知草稿'}),
      );
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => openAssistantSheet(
                    context,
                    controller: f.c,
                    semester: const {'id': 's'},
                    initialText: '检查今晚安排',
                  ),
                  child: const Text('上下文'),
                ),
                TextButton(
                  onPressed: () => openAssistantSheet(
                    context,
                    controller: f.c,
                    semester: const {'id': 's'},
                  ),
                  child: const Text('普通入口'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('上下文'));
      await settleIo(tester);
      await tester.enterText(find.byType(TextField).first, '今晚还需要留一小时');
      await ioTap(tester, find.byTooltip('收起输入'));
      await settleIo(tester);
      await tester.tap(find.text('普通入口'));
      await settleIo(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '今晚还需要留一小时',
      );
      final saved = await tester.runAsync(() => drafts.read('assistant:s'));
      expect(saved?['text'], '原来的通知草稿');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('dock opens text or voice directly without an operation menu', (
    tester,
  ) async {
    final modes = <String?>[];
    await mount(
      tester,
      AssistantScope(
        onOpen:
            (
              context, {
              String? initialText,
              String? mediaKind,
              bool autoSubmit = false,
            }) async {
              modes.add(mediaKind);
            },
        child: Scaffold(
          bottomNavigationBar: AppNavigation(selected: 0, onSelected: (_) {}),
        ),
      ),
    );
    await tester.tap(find.text('输入通知或日程问题'));
    await tester.tap(find.byTooltip('语音输入'));
    await tester.pumpAndSettle();
    expect(modes, [null, 'audio']);
    expect(find.text('记录作业'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
  testWidgets(
    'contextual request opens in sheet with text ready and returns to prior page',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('原来的日程'),
                TextButton(
                  onPressed: () => openAssistantSheet(
                    context,
                    controller: f.c,
                    semester: const {'id': 's', 'name': '本学期'},
                    initialText: '检查今晚安排',
                  ),
                  child: const Text('打开输入'),
                ),
              ],
            ),
          ),
        ),
      );
      await ioTap(tester, find.text('打开输入'));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '检查今晚安排',
      );
      await tester.tap(find.byTooltip('收起输入'));
      await tester.pumpAndSettle();
      expect(find.text('原来的日程'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
