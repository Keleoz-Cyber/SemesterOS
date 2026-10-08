import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'package:semester_os/features/agent/change_confirmation.dart';
import 'package:semester_os/features/calendar/event_conflict_review.dart';
import 'package:semester_os/features/calendar/event_form.dart';
import 'package:semester_os/features/centers/exam_pages.dart';
import 'package:semester_os/features/items/item_actions.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/ui/app_controls.dart';

import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'planning_flow_test.dart' show ioTap, route;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> conflictImpact({bool possible = true}) => {
  'new_fixed_conflicts': <Map<String, dynamic>>[
    {
      'item_ids': ['course-friday'],
      'pending_record': true,
      'titles': ['班主任会议', '软件工程'],
      'start_at': '2026-10-09T09:00:00+08:00',
      'end_at': '2026-10-09T09:50:00+08:00',
      'certainty': possible ? 'possible' : 'confirmed',
      if (possible) ...{
        'uncertainty_reasons': ['end_unknown'],
        'time_incomplete': true,
        'overlap_at_start': true,
        'event_start_at': '2026-10-09T09:00:00+08:00',
      },
    },
  ],
  'course_conflicts': <Map<String, dynamic>>[
    {
      'occurrence_id': 'course-friday',
      'title': '软件工程',
      'start_at': '2026-10-09T08:00:00+08:00',
      'end_at': '2026-10-09T09:50:00+08:00',
    },
  ],
};

Map<String, dynamic> laterCourseWarning(String id, String title, String at) => {
  'item_ids': [id],
  'pending_record': true,
  'titles': ['班主任会议', title],
  'start_at': at,
  'end_at': DateTime.parse(
    at,
  ).add(const Duration(minutes: 100)).toIso8601String(),
  'certainty': 'possible',
  'uncertainty_reasons': ['end_unknown'],
  'time_incomplete': true,
  'overlap_at_start': false,
  'event_start_at': '2026-10-09T09:00:00+08:00',
  'window_is_comparison': true,
};

Map<String, dynamic> mixedConflictImpact() {
  final impact = conflictImpact();
  for (final course in [
    ('course-later', '后续软件工程', '2026-10-09T10:10:00+08:00'),
    ('course-afternoon', '下午课程', '2026-10-09T14:00:00+08:00'),
  ]) {
    (impact['new_fixed_conflicts'] as List).add(
      laterCourseWarning(course.$1, course.$2, course.$3),
    );
    (impact['course_conflicts'] as List).add({
      'occurrence_id': course.$1,
      'title': course.$2,
      'start_at': course.$3,
      'end_at': DateTime.parse(
        course.$3,
      ).add(const Duration(minutes: 100)).toIso8601String(),
    });
  }
  return impact;
}

Map<String, dynamic> warningOnlyImpact() => {
  'new_fixed_conflicts': [
    laterCourseWarning('course-later', '后续软件工程', '2026-10-09T10:10:00+08:00'),
  ],
  'course_conflicts': [
    {
      'occurrence_id': 'course-later',
      'title': '后续软件工程',
      'start_at': '2026-10-09T10:10:00+08:00',
      'end_at': '2026-10-09T11:50:00+08:00',
    },
  ],
};

Map<String, dynamic> conflictRun({Map<String, dynamic>? impact}) => {
  'id': 'meeting-preview',
  'status': 'needs_confirmation',
  'preview': {
    'kind': 'event',
    'action': 'create',
    'token': 'meeting-token',
    'after': {
      'title': '班主任会议',
      'time': {'precision': 'exact', 'at': '2026-10-09T09:00:00+08:00'},
    },
    'impact': impact ?? conflictImpact(),
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  test('an unsaved event still needs consent with just one real course ID', () {
    expect(unresolvedEventConflicts(conflictImpact(), {}), hasLength(1));
    expect(
      unresolvedEventConflicts(conflictImpact(), {'course-friday'}),
      isEmpty,
    );
    expect(
      unresolvedEventConflicts(conflictImpact(), {'another-course'}),
      hasLength(1),
    );
  });

  test('later courses with an unknown end are warnings, not leave targets', () {
    final impact = mixedConflictImpact();
    expect(eventConflicts(impact), hasLength(1));
    expect(eventTimeWarnings(impact), hasLength(2));
    expect(eventConflictCourses(impact).map((r) => r['occurrence_id']), [
      'course-friday',
    ]);
    expect(unresolvedEventConflicts(impact, {'course-friday'}), isEmpty);
    expect(unresolvedEventConflicts(warningOnlyImpact(), {}), isEmpty);
  });

  test('explicit blocking rows are authoritative, including an empty list', () {
    final impact = {
      ...mixedConflictImpact(),
      'blocking_conflicts': [],
      'time_warnings': [
        {
          ...laterCourseWarning(
            'course-later',
            '后续软件工程',
            '2026-10-09T10:10:00+08:00',
          ),
          'blocking': false,
          'message': '结束时间未知，可稍后核对后续课程。',
        },
      ],
    };
    expect(eventConflicts(impact), isEmpty);
    expect(eventConflictCourses(impact), isEmpty);
    expect(eventTimeWarnings(impact), hasLength(1));
    expect(
      eventConflicts({
        ...impact,
        'new_blocking_conflicts': [
          {
            ...conflictImpact()['new_fixed_conflicts'][0],
            'blocking': true,
            'overlap_at_start': false,
            'overlap_at_arrival': true,
            'evidence_kind': 'arrival_interval',
          },
        ],
      }),
      hasLength(1),
    );
  });

  testWidgets('start-only preview requires a visible choice before saving', (
    tester,
  ) async {
    final f = ScheduleFixture();
    await tester.runAsync(() => f.c.bind('s'));
    final agent = AgentController(f.c, 's');
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    Map<String, dynamic>? decision;
    var adjustments = 0;
    final run = conflictRun(impact: mixedConflictImpact());
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/decision')) {
        decision = Map<String, dynamic>.from(r.data);
        return body({
          ...run,
          'status': 'applied',
          'receipt': {'semester_id': 's', 'revision': 1},
        });
      }
      return old.respond(r);
    });
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: ChangeConfirmation(
            run: run,
            controller: agent,
            details: (_) => const Text('班主任会议 · 09:00开始，结束未说明'),
            onAdjustTime: () => adjustments++,
          ),
        ),
      ),
    );
    expect(find.textContaining('开始时已有课程'), findsOneWidget);
    expect(find.textContaining('08:00–09:50'), findsWidgets);
    expect(find.text('后续软件工程 · 我已请假'), findsNothing);
    expect(find.text('下午课程 · 我已请假'), findsNothing);
    expect(find.text('时间待核对'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, '保存日程'))
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('补充或调整时间'));
    await tester.tap(find.text('补充或调整时间'));
    await tester.pumpAndSettle();
    expect(adjustments, 1);
    expect(decision, isNull);
    await tester.ensureVisible(find.text('软件工程 · 我已请假'));
    await tester.tap(find.text('软件工程 · 我已请假'));
    await tester.pumpAndSettle();
    expect(find.text('已选请假处理'), findsOneWidget);
    await tester.ensureVisible(find.text('保存日程'));
    await ioTap(tester, find.text('保存日程'));
    expect(decision?['course_leave_targets'], ['course-friday']);
    expect(decision?.containsKey('confirm_fixed_conflicts'), false);
    expect(run['preview']['after']['time'].containsKey('end_at'), false);
    await tester.pumpWidget(const SizedBox());
    agent.dispose();
    f.c.dispose();
  });

  testWidgets(
    'incomplete time with only warnings keeps assistant save enabled',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final agent = AgentController(f.c, 's');
      for (final time in <Map<String, dynamic>>[
        {'precision': 'exact', 'at': '2026-10-09T09:00:00+08:00'},
        {'precision': 'date', 'date': '2026-10-09'},
        {'precision': 'week', 'week': 6},
        {'precision': 'unknown'},
      ]) {
        final run = conflictRun(impact: warningOnlyImpact());
        run['preview']['after']['time'] = time;
        await mount(
          tester,
          Scaffold(
            body: ChangeConfirmation(
              run: run,
              controller: agent,
              details: (_) => const Text('班主任会议'),
            ),
          ),
        );
        expect(find.text('时间待核对'), findsOneWidget);
        expect(find.text('保留这些重叠安排'), findsNothing);
        expect(find.textContaining('我已请假'), findsNothing);
        expect(
          tester
              .widget<AppButton>(find.widgetWithText(AppButton, '保存日程'))
              .onPressed,
          isNotNull,
          reason: '${time['precision']} without a proven overlap can save',
        );
        await tester.pumpWidget(const SizedBox());
      }
      agent.dispose();
      f.c.dispose();
    },
  );

  testWidgets(
    'manual meeting checks conflict before POST and keeps unknown end',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var previews = 0;
      Map<String, dynamic>? saved;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/semesters')) return body([semester()]);
        if (r.path.endsWith('/events/conflict-preview')) {
          previews++;
          expect(r.data['time'].containsKey('end_at'), false);
          return body({'impact': conflictImpact(), 'expected_revision': 1});
        }
        if (r.path.endsWith('/events') && r.method == 'POST') {
          saved = Map<String, dynamic>.from(r.data);
          return body({
            'semester_id': 's',
            'revision': 2,
            'event': {'id': 'e'},
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: AppButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EventFormPage(
                    controller: f.c,
                    semester: semester(),
                    candidate: {
                      'event': {
                        'title': '班主任会议',
                        'time': {
                          'precision': 'exact',
                          'at': '2026-10-09T09:00:00+08:00',
                        },
                      },
                    },
                  ),
                ),
              ),
              child: const Text('打开日程录入'),
            ),
          ),
        ),
      );
      await ioTap(tester, find.text('打开日程录入'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('添加日程').last);
      expect(previews, 1);
      expect(saved, isNull);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '确认处理并保存'))
            .onPressed,
        isNull,
      );
      await capture(tester, 'event-conflict-before-save');
      await tester.ensureVisible(find.text('软件工程 · 我已请假'));
      await tester.tap(find.text('软件工程 · 我已请假'));
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('确认处理并保存'));
      expect(saved?['course_leave_targets'], ['course-friday']);
      expect(saved?['time'].containsKey('end_at'), false);
      expect(saved?.containsKey('confirm_fixed_conflicts'), false);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  for (final time in <Map<String, dynamic>>[
    {'precision': 'exact', 'at': '2026-10-09T09:00:00+08:00'},
    {'precision': 'date', 'date': '2026-10-09'},
    {'precision': 'week', 'week': 6},
    {'precision': 'unknown'},
  ]) {
    testWidgets(
      'manual ${time['precision']} event saves without a warning-only dialog',
      (tester) async {
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        Map<String, dynamic>? saved;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/semesters')) return body([semester()]);
          if (r.path.endsWith('/events/conflict-preview')) {
            return body({
              'impact': warningOnlyImpact(),
              'expected_revision': 1,
            });
          }
          if (r.path.endsWith('/events') && r.method == 'POST') {
            saved = Map<String, dynamic>.from(r.data);
            return body({
              'semester_id': 's',
              'revision': 2,
              'event': {'id': 'e'},
            });
          }
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await route(
          tester,
          EventFormPage(
            controller: f.c,
            semester: semester(),
            candidate: {
              'event': {'title': '待核对会议', 'time': time},
            },
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        await ioTap(tester, find.text('添加日程').last);
        expect(saved?['time']['precision'], time['precision']);
        expect(saved?['time']['end_at'], isNull);
        expect(saved?.containsKey('confirm_fixed_conflicts'), false);
        expect(saved?.containsKey('course_leave_targets'), false);
        expect(find.text('保存前核对冲突'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );
  }

  testWidgets('exam reschedule warnings do not require retain consent', (
    tester,
  ) async {
    final f = ScheduleFixture();
    await tester.runAsync(() => f.c.bind('s'));
    final exam = {
      ...f.item,
      'kind': 'exam',
      'reserve_time': true,
      'time': {'precision': 'date', 'date': '2026-10-09'},
    };
    await mount(
      tester,
      ExamChangePreviewPage(
        controller: f.c,
        preview: {
          ...warningOnlyImpact(),
          'base_revision': 1,
          'before': exam,
          'after': {
            ...exam,
            'time': {'precision': 'week', 'week': 6},
          },
          'reviews': [],
          'reminders_after': [],
          'affected_blocks': [],
          'risk_changes': [],
        },
        request: const {'reason': '教师通知'},
      ),
    );
    expect(find.text('时间待核对'), findsOneWidget);
    expect(find.text('保留这些重叠安排'), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, '确认考试新安排'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  for (final hasConflict in [true, false]) {
    testWidgets(
      hasConflict
          ? 'creating an exam needs explicit consent for a proven overlap'
          : 'creating an exam with only a time warning saves directly',
      (tester) async {
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        Map<String, dynamic>? saved;
        var previews = 0;
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/items/conflict-preview')) {
            previews++;
            return body({
              'impact': hasConflict ? conflictImpact() : warningOnlyImpact(),
              'base_revision': 1,
            });
          }
          if (r.path.endsWith('/items') && r.method == 'POST') {
            saved = Map<String, dynamic>.from(r.data);
            return body({
              ...saved!,
              'id': 'exam-new',
              'version': 1,
              'lifecycle': 'active',
              'course_title': '',
              'reminders': [],
            });
          }
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: AppButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemFormPage(
                      controller: f.c,
                      semester: semester(),
                      kind: 'exam',
                      candidate: {
                        'item': {
                          'kind': 'exam',
                          'title': '考试',
                          'time': {
                            'precision': 'exact',
                            'at': '2026-10-09T09:00:00+08:00',
                          },
                        },
                      },
                    ),
                  ),
                ),
                child: const Text('打开考试录入'),
              ),
            ),
          ),
        );
        await ioTap(tester, find.text('打开考试录入'));
        await ioTap(tester, find.text('保存'));
        expect(previews, 1);
        if (hasConflict) {
          expect(saved, isNull);
          await tester.ensureVisible(find.text('保留这些重叠安排'));
          await tester.tap(find.text('保留这些重叠安排'));
          await tester.pumpAndSettle();
          await ioTap(tester, find.text('确认处理并保存'));
        } else {
          expect(find.text('保存前核对冲突'), findsNothing);
        }
        expect(saved?['confirm_fixed_conflicts'], hasConflict ? true : isNull);
        expect(saved?['expected_revision'], 1);
        expect(saved?['time']['end_at'], isNull);
        expect(saved?.containsKey('course_leave_targets'), false);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );

    testWidgets(
      hasConflict
          ? 'restoring an exam requires a decision for a proven overlap'
          : 'restoring an exam with only a time warning saves directly',
      (tester) async {
        final f = ScheduleFixture();
        final old = f.api.dio.httpClientAdapter as ControlledTransport;
        Map<String, dynamic>? saved;
        final exam = {...f.item, 'kind': 'exam', 'lifecycle': 'cancelled'};
        f.api.dio.httpClientAdapter = ControlledTransport((r) async {
          if (r.path.endsWith('/lifecycle/preview')) {
            return body({
              'base_revision': 1,
              'affected_blocks': [],
              'impact': hasConflict ? conflictImpact() : warningOnlyImpact(),
            });
          }
          if (r.path.endsWith('/lifecycle')) {
            saved = Map<String, dynamic>.from(r.data);
            return body({...exam, 'version': 2, 'lifecycle': 'active'});
          }
          return old.respond(r);
        });
        await tester.runAsync(() => f.c.bind('s'));
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: AppButton(
                onPressed: () =>
                    changeItemLifecycle(context, f.c, exam, 'active'),
                child: const Text('恢复考试'),
              ),
            ),
          ),
        );
        await ioTap(tester, find.text('恢复考试'));
        if (hasConflict) {
          expect(saved, isNull);
          await tester.ensureVisible(find.text('保留这些重叠安排'));
          await tester.tap(find.text('保留这些重叠安排'));
          await tester.pumpAndSettle();
          await ioTap(tester, find.text('确认处理并保存'));
        } else {
          expect(find.text('保存前核对冲突'), findsNothing);
        }
        expect(saved?['confirm_fixed_conflicts'], hasConflict ? true : isNull);
        expect(saved?.containsKey('course_leave_targets'), false);
        expect(saved?['expected_revision'], 1);
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      },
    );
  }

  testWidgets('conflict choices fit narrow screens with enlarged text', (
    tester,
  ) async {
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: AppButton(
            onPressed: () => confirmEventConflicts(context, conflictImpact()),
            child: const Text('核对'),
          ),
        ),
      ),
      width: 360,
      textScale: 1.6,
    );
    await tester.tap(find.text('核对'));
    await tester.pumpAndSettle();
    await capture(tester, 'event-conflict-large-text');
    await tester.ensureVisible(find.text('保留这些重叠安排'));
    await tester.tap(find.text('保留这些重叠安排'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, '确认处理并保存'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
