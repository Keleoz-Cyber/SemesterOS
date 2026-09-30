import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/calendar/event_form.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'package:semester_os/ui/time_input_options.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'inner_items_visual_test.dart'
    show fixture, eventRecord, itemRecord, settle, reveal, shot;
import 'ui_polish_test.dart' show mount, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  testWidgets(
    'an existing reminder still explains its missing time dependency',
    (tester) async {
      final f = await fixture(tester);
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/events/e')) {
          return body({
            ...eventRecord(),
            'time': {'precision': 'unknown'},
            'location': '',
            'reminders': [
              {
                'mode': 'relative',
                'lead_minutes': 30,
                'schedule_state': 'pending_time',
              },
            ],
          });
        }
        return transport.respond(r);
      });
      await mount(
        tester,
        EventDetailPage(controller: f.c, semester: semester(), eventId: 'e'),
      );
      await settle(tester);
      expect(find.text('时间'), findsNothing);
      expect(find.text('待补充具体时间'), findsOneWidget);
      await shot(tester, 'reminder-needs-time');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'custom event reminder accepts minutes without unrelated settings',
    (tester) async {
      Map<String, dynamic>? result;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await editReminder(
                  context,
                  kind: 'event',
                  relativeOnly: true,
                );
              },
              child: const Text('设置提醒'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('设置提醒'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AppPickerField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '45');
      await tester.ensureVisible(find.text('确认这条提醒'));
      await tester.tap(find.text('确认这条提醒'));
      await tester.pumpAndSettle();
      expect(result?['lead_minutes'], 45);
      expect(result?['mode'], 'relative');
      expect(result?['purpose'], 'item');
    },
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets('sparse event only displays existing attributes $scale', (
      tester,
    ) async {
      final f = await fixture(tester);
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/events/e')) {
          return body({
            ...eventRecord(),
            'location': '',
            'source_text': '',
            'category_id': null,
            'tags': [],
            'reminders': [],
            'time': {'precision': 'exact', 'at': '2026-10-03T14:00:00+08:00'},
          });
        }
        return transport.respond(r);
      });
      await mount(
        tester,
        EventDetailPage(controller: f.c, semester: semester(), eventId: 'e'),
        textScale: scale,
      );
      await settle(tester);
      expect(find.text('2026-10-03 14:00'), findsOneWidget);
      for (final text in ['结束', '地点', '提醒', '未设置提醒', '时间待确认', '通知原文']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      await shot(tester, 'sparse-event-$scale');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('sparse task has no invented progress or source $scale', (
      tester,
    ) async {
      final f = await fixture(tester);
      f.item = {
        ...itemRecord(),
        'title': '交材料',
        'kind': 'task',
        'time': {'precision': 'unknown'},
        'anchor_at': null,
        'remaining_minutes': null,
        'course_title': null,
        'location': '',
        'source_text': '',
        'notes': '',
        'reminders': [],
      };
      f.c.items = [f.item];
      await mount(
        tester,
        ItemDetailPage(controller: f.c, semester: semester(), id: 't'),
        textScale: scale,
      );
      await settle(tester);
      for (final text in ['截止时间', '任务进度', '耗时待补充', '没有附加原文', '计划余量待更新']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      await reveal(tester, find.text('添加提醒'));
      await shot(tester, 'sparse-task-$scale');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }

  testWidgets(
    'editing unknown certainty does not silently confirm it or invent an end',
    (tester) async {
      final f = await fixture(tester);
      Map<String, dynamic>? sent;
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/events/e') && r.method == 'PATCH') {
          sent = Map<String, dynamic>.from(r.data);
          return body({'message': '保存失败'}, 422);
        }
        return transport.respond(r);
      });
      await mount(
        tester,
        EventFormPage(
          controller: f.c,
          semester: semester(),
          original: {
            ...eventRecord(),
            'certainty': 'unknown',
            'reminder_minutes': [30, 1440],
            'time': {'precision': 'exact', 'at': '2026-10-03T14:00:00+08:00'},
          },
        ),
      );
      await settle(tester);
      await reveal(tester, find.text('暂定安排'));
      expect(find.byType(TentativeSwitch), findsOneWidget);
      expect(find.text('待确认'), findsNothing);
      expect(find.text('添加结束时间'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('保存修改'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(sent?['certainty'], 'unknown');
      expect(sent?['time'], {
        'precision': 'exact',
        'at': '2026-10-03T06:00:00.000Z',
      });
      expect(sent?['reminder_minutes'], [30, 1440]);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'event reminders edit one rule, deduplicate and remove independently',
    (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        EventFormPage(
          controller: f.c,
          semester: semester(),
          original: eventRecord(),
        ),
      );
      await settle(tester);
      await reveal(tester, find.text('提前30分钟提醒'));
      expect(find.byType(AppFilterChip), findsNothing);
      await tester.tap(find.text('提前30分钟提醒'));
      await tester.pumpAndSettle();
      expect(find.byType(ReminderEditor), findsOneWidget);
      expect(find.text('指定时刻'), findsNothing);
      await tester.tap(find.byType(AppPickerField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提前1天').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认这条提醒'));
      await tester.tap(find.text('确认这条提醒'));
      await tester.pumpAndSettle();
      expect(find.text('提前1天提醒'), findsOneWidget);
      expect(find.text('提前30分钟提醒'), findsNothing);
      await tester.tap(find.byTooltip('删除这条提醒'));
      await tester.pumpAndSettle();
      expect(find.text('提前1天提醒'), findsNothing);
      expect(find.text('添加提醒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'incomplete notice keeps week and range input available on demand',
    (tester) async {
      String precision = 'exact';
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: TimeInputOptions(
              precision: precision,
              onChanged: (v) => setState(() => precision = v),
            ),
          ),
        ),
        textScale: 1.6,
      );
      expect(find.text('按学期周次填写'), findsNothing);
      await tester.tap(find.text('其他时间写法'));
      await tester.pumpAndSettle();
      await shot(tester, 'time-options-1.6');
      await tester.tap(find.text('按学期周次填写'));
      await tester.pumpAndSettle();
      expect(precision, 'week');
      await tester.tap(find.text('添加日期和时间'));
      await tester.pumpAndSettle();
      expect(precision, 'exact');
      await tester.tap(find.text('只记日期'));
      await tester.pumpAndSettle();
      expect(precision, 'date');
      expect(tester.takeException(), isNull);
    },
  );
}
