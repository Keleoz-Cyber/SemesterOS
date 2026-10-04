import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/features/agent/assistant_sheet.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'package:semester_os/ui/brand.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'controller_test.dart' show MemoryStore;
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'planning_flow_test.dart' show ioTap, PlanningFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  for (final layout in [
    (label: '1.0', scale: 1.0, width: 390.0, height: 844.0),
    (label: '1.6', scale: 1.6, width: 360.0, height: 844.0),
    (label: '2.0-small', scale: 2.0, width: 320.0, height: 760.0),
    (label: 'landscape', scale: 1.0, width: 740.0, height: 390.0),
  ]) {
    final scale = layout.scale;
    testWidgets('integrated pages ${layout.label}', (tester) async {
      final f = await fixture(tester), now = schoolNow();
      final day = DateTime.utc(now.year, now.month, now.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      String date(DateTime d) => d.toIso8601String().substring(0, 10);
      final data = hub(f), today = date(day);
      final s = <String, dynamic>{
        ...data['semester'],
        'name': '2026—2027 第一学期',
        'first_monday': date(monday.subtract(const Duration(days: 21))),
        'periods': [
          {'number': 1, 'start': '08:00', 'end': '08:50'},
        ],
      };
      final courses = [
        for (var i = 0; i < 3; i++)
          {
            'id': 'course:$i',
            'resource_id': '$i',
            'resource_type': 'course',
            'title': ['概率论', '软件工程', '大学英语'][i],
            'location': ['A203', '莲7号楼 402', 'B301'][i],
            'start_at': '${today}T${['08', '10', '14'][i]}:00:00+08:00',
            'end_at': '${today}T${['09', '11', '15'][i]}:50:00+08:00',
            'time_precision': 'exact',
          },
      ];
      final activity = {
        'id': 'event:e',
        'resource_id': 'e',
        'resource_type': 'event',
        'title': '课题组组会',
        'location': '6412',
        'start_at': '${today}T17:00:00+08:00',
        'end_at': '${today}T18:00:00+08:00',
        'time_precision': 'exact',
      };
      f.item = {
        ...f.item,
        'title': 'Java实验报告',
        'priority': 'high',
        'category_id': 'study',
        'tags': ['实验报告'],
      };
      data['semester'] = s;
      data['weeks'] = [
        for (var w = 1; w <= 20; w++)
          {
            'week': w,
            'start_date': date(monday.add(Duration(days: (w - 4) * 7))),
            'end_date': date(monday.add(Duration(days: (w - 4) * 7 + 6))),
            'items': w == 4 ? [f.item] : [],
            'changes': [],
          },
      ];
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      final risk = PlanningFixture().risk;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/agent/threads?')) return body([]);
        if (r.path.endsWith('/hub')) return body(data);
        if (r.path.endsWith('/risk')) return body(risk);
        if (r.path.contains('/calendar?')) {
          return body({
            'semester_id': 's',
            'revision': 1,
            'entries': [...courses, activity],
            'undated': [],
          });
        }
        if (r.path.contains('/day-brief?')) {
          return body({
            'semester_id': 's',
            'revision': 1,
            'date': r.uri.queryParameters['day'],
            'valid_until': '2099-01-01T00:00:00Z',
            'entries': [...courses, activity],
            'suggestions': [
              {
                'kind': 'free_window',
                'title': '19:00—20:30 可安排任务',
                'detail': '按你的学习时间设置，连续90分钟',
                'request': '请安排今晚19点到20点半的学习时间，先给我预览',
                'action_label': '安排一下',
              },
            ],
          });
        }
        return previous.respond(r);
      });
      await tester.runAsync(() => f.c.refresh());
      final app =
          AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
            ..semester = s
            ..semesters = [s]
            ..week = 4
            ..ready = true;
      await mount(
        tester,
        AssistantScope(
          onOpen: (context, {initialText, mediaKind, autoSubmit = false}) =>
              openAssistantSheet(
                context,
                controller: f.c,
                semester: s,
                initialText: initialText,
                mediaKind: mediaKind,
                autoSubmit: autoSubmit,
              ),
          child: ShellPage(controller: app, items: f.c),
        ),
        width: layout.width,
        height: layout.height,
        textScale: scale,
      );
      await settleIo(tester);
      expect(find.text(appName), findsOneWidget);
      if (scale == 1 && layout.height > 700) {
        // Active/next-event and clock rows vary by time of day. The isolated
        // dashboard test covers fixed-density layout; this integration check
        // verifies that the timeline stays accessible above the fixed composer.
        final ended = find.textContaining('今天已结束 ·');
        if (ended.evaluate().isNotEmpty) {
          await tester.ensureVisible(ended);
          await ioTap(tester, ended);
        }
        await tester.ensureVisible(find.text('大学英语').last);
        await tester.pumpAndSettle();
        expect(find.text('大学英语').last.hitTestable(), findsOneWidget);
      }
      await capture(tester, 'integrated-today-${layout.label}');
      for (final page in ['日程', '计划', '学期']) {
        await ioTap(tester, find.text(page).last);
        await settleIo(tester);
        expect(
          tester.takeException(),
          isNull,
          reason: '$page at ${layout.label}',
        );
        await capture(tester, 'integrated-$page-${layout.label}');
      }
      if (layout.label == '1.0' || layout.label == '2.0-small') {
        await ioTap(tester, find.byTooltip('账户'));
        await capture(tester, 'integrated-account-${layout.label}');
        await ioTap(tester, find.byTooltip('关闭'));
        await ioTap(tester, find.text('今日').last);
        await settleIo(tester);
        await tester.ensureVisible(find.byTooltip('调整首页内容'));
        await tester.pumpAndSettle();
        await ioTap(tester, find.byTooltip('调整首页内容'));
        await capture(tester, 'integrated-home-settings-${layout.label}');
        await ioTap(tester, find.text('完成'));
      }
      await tester.tap(find.byKey(const Key('assistant-dock-input')));
      await settleIo(tester);
      await tester.enterText(
        find.byType(TextField).first,
        '本周三17点到18点组会，地点6412',
      );
      await capture(tester, 'integrated-input-${layout.label}');
      final keyboard = layout.height > 500 ? 300.0 : 180.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byTooltip('发送')).bottom,
        lessThanOrEqualTo(layout.height - keyboard),
      );
      await capture(tester, 'integrated-keyboard-${layout.label}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    });
  }
}
