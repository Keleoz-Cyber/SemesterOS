import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'assistant_redesign_test.dart' show settled;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> occurrence(int i) => {
  'id': 'c$i',
  'title': '课程${i + 1}',
  'start_at': '2026-10-0${i + 1}T08:30:00+08:00',
  'end_at': '2026-10-0${i + 1}T10:05:00+08:00',
  'location': 'A301',
};

Future<ScheduleFixture> assistant(
  WidgetTester tester,
  Map<String, dynamic> preview,
) async {
  final f = ScheduleFixture();
  final old = f.api.dio.httpClientAdapter as ControlledTransport;
  f.api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.path.endsWith('/agent/threads/t')) {
      return body({
        'runs': [
          {
            'id': 'r',
            'text': '国庆节一号到7号都没课。',
            'status': 'needs_confirmation',
            'answer': '请核对这次修改，确认后保存。',
            'cards': [],
            'preview': preview,
          },
        ],
      });
    }
    return old.respond(r);
  });
  await tester.runAsync(() => f.c.bind('s'));
  await mount(
    tester,
    AgentPage(
      controller: f.c,
      semester: {'id': 's', 'name': '当前学期'},
      initialThreadId: 't',
    ),
  );
  await settled(tester);
  return f;
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'range suspension is concise and unrelated conflicts do not lock its save',
    (tester) async {
      final f = await assistant(tester, {
        'kind': 'course_change',
        'action': 'suspend',
        'token': 'scope',
        'title': '国庆停课',
        'before': [for (var i = 0; i < 6; i++) occurrence(i)],
        'after': [],
        'impact': {
          'fixed_conflicts': [
            {
              'titles': ['已有会议', '另一会议'],
            },
          ],
          'new_fixed_conflicts': [],
        },
      });
      expect(find.text('停课 6 次'), findsOneWidget);
      expect(find.text('课程4'), findsNothing);
      expect(find.text('有时间冲突'), findsNothing);
      expect(find.text('请核对这次修改，确认后保存。'), findsNothing);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '确认停课'))
            .onPressed,
        isNotNull,
      );
      await capture(tester, 'assistant-range-suspension');
      await tester.ensureVisible(find.text('查看 6 次课'));
      await ioTap(tester, find.text('查看 6 次课'));
      expect(find.text('课程6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'completing a task shows its state and related cancellation once',
    (tester) async {
      final f = await assistant(tester, {
        'kind': 'item_state',
        'action': 'completed',
        'token': 'complete',
        'title': '交材料',
        'before': {'title': '交材料', 'lifecycle': 'active'},
        'after': {'title': '交材料', 'lifecycle': 'completed'},
        'affected_blocks': [
          {
            'start_at': '2026-10-09T19:00:00+08:00',
            'end_at': '2026-10-09T20:00:00+08:00',
            'locked': true,
          },
        ],
      });
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('同时关闭这条事项的提醒。'), findsOneWidget);
      expect(find.text('同时取消 1 段后续计划'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '标记完成'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '确认修改'), findsNothing);
      await capture(tester, 'assistant-task-completion');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'formal exam offers reservation choice without downgrading certainty',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        ItemFormPage(
          controller: f.c,
          semester: {'id': 's', 'total_weeks': 20},
          initial: {
            'id': 'exam',
            'version': 1,
            'kind': 'exam',
            'title': '参考考试',
            'certainty': 'formal',
            'reserve_time': false,
            'time': {'precision': 'unknown'},
          },
        ),
      );
      await tester.scrollUntilVisible(
        find.text('更多设置'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('更多设置'));
      await tester.scrollUntilVisible(
        find.text('为这场考试预留时间'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      final row = tester.widget<AppSwitchRow>(
        find.widgetWithText(AppSwitchRow, '为这场考试预留时间'),
      );
      expect(row.value, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
