import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'package:semester_os/features/agent/assistant_sheet.dart';
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'api_session_test.dart' show ControlledTransport, body;
import 'controller_test.dart' show MemoryStore;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'Shell preserves scroll and selected week across tabs and input, resets semester state',
    (tester) async {
      final f = await fixture(tester);
      final data = hub(f);
      final now = schoolNow();
      final day = DateTime.utc(now.year, now.month, now.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      String date(DateTime d) => d.toIso8601String().substring(0, 10);
      final first = monday.subtract(const Duration(days: 7));
      final semester = <String, dynamic>{
        ...data['semester'],
        'name': '本学期',
        'first_monday': date(first),
        'periods': [
          {'number': 1, 'start': '08:00', 'end': '08:50'},
        ],
      };
      data['semester'] = semester;
      data['weeks'] = [
        for (var w = 1; w <= 3; w++)
          {
            'week': w,
            'start_date': date(first.add(Duration(days: (w - 1) * 7))),
            'end_date': date(first.add(Duration(days: (w - 1) * 7 + 6))),
            'changes': [],
            'items': [
              for (var i = 0; i < 8; i++)
                {
                  ...f.item,
                  'id': '$w-$i',
                  'title': '第$w周事项$i',
                  'time': {'precision': 'week', 'week': w},
                },
            ],
          },
      ];
      var current = semester, reads = 0;
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) {
          reads++;
          return body({...data, 'semester': current});
        }
        if (r.path.endsWith('/me')) return body(f.api.session!['user']);
        if (r.path.endsWith('/semesters')) return body([current]);
        if (r.path.contains('/timetable?')) {
          return body({
            'semester_id': current['id'],
            'revision': 1,
            'events': [],
          });
        }
        if (r.path.contains('/agent/threads?')) return body([]);
        if (r.path.contains('/calendar?')) {
          return body({
            'semester_id': current['id'],
            'revision': 1,
            'entries': [],
            'undated': [],
          });
        }
        if (r.path.contains('/day-brief?')) {
          return body({
            'semester_id': current['id'],
            'revision': 1,
            'date': r.uri.queryParameters['day'],
            'valid_until': '2099-01-01T00:00:00Z',
            'entries': [],
            'suggestions': [],
          });
        }
        return old.respond(r);
      });
      final app =
          AppController(f.api, MemoryStore(), clearSchoolSession: () async {})
            ..semester = semester
            ..semesters = [semester]
            ..week = 2
            ..ready = true;
      await mount(
        tester,
        AssistantScope(
          onOpen: (context, {initialText, mediaKind, autoSubmit = false}) =>
              openAssistantSheet(
                context,
                controller: f.c,
                semester: app.semester!,
                initialText: initialText,
                autoSubmit: autoSubmit,
              ),
          child: ShellPage(controller: app, items: f.c),
        ),
      );
      await settleIo(tester);
      await ioTap(tester, find.text('学期').last);
      await settleIo(tester);
      await tester.tap(find.byKey(const ValueKey('semester-week-3')));
      await settleIo(tester);
      final home = find.byType(SemesterHome);
      final scroll = find
          .ancestor(of: home, matching: find.byType(Scrollable))
          .first;
      await tester.drag(scroll, const Offset(0, -320));
      await tester.pumpAndSettle();
      final before = tester.state<ScrollableState>(scroll).position.pixels;
      expect(before, greaterThan(100));
      await ioTap(tester, find.text('今日').last);
      await ioTap(tester, find.text('学期').last);
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        closeTo(before, 1),
      );
      await ioTap(tester, find.text('输入通知或日程问题'));
      await settleIo(tester);
      await tester.enterText(find.byType(TextField).first, '还没写完的通知');
      await ioTap(tester, find.byTooltip('收起输入'));
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        closeTo(before, 1),
      );
      await ioTap(tester, find.text('输入通知或日程问题'));
      await settleIo(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '还没写完的通知',
      );
      await ioTap(tester, find.byTooltip('收起输入'));
      await tester.drag(scroll, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('semester-week-3')))
            .properties
            .selected,
        isTrue,
      );
      final oldReads = reads;
      await tester.fling(scroll, const Offset(0, 350), 1000);
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pumpAndSettle();
      expect(reads, greaterThan(oldReads));
      await capture(tester, 'shell-semester');
      current = {...semester, 'id': 'new-semester', 'name': '另一个学期'};
      Future<void>? binding, selecting;
      app.semesters = [current];
      await tester.runAsync(() async {
        binding = f.c.bind('new-semester');
        selecting = app.selectSemester(current);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.runAsync(
        () => Future.wait([
          binding!,
          selecting!,
        ]).timeout(const Duration(seconds: 2)),
      );
      await settleIo(tester);
      expect(find.text('另一个学期'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('semester-week-2')))
            .properties
            .selected,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
      app.dispose();
    },
  );
}
