import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/features/centers/exam_pages.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show route, ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> semester() => {
  'id': 's',
  'name': '示例学期 · 合成数据',
  'first_monday': '2026-08-31',
  'total_weeks': 20,
  'revision': 1,
};
Map<String, dynamic> exam(ScheduleFixture f) => {
  'id': 'exam',
  'semester_id': 's',
  'version': 1,
  'kind': 'exam',
  'title': '合成概率论考试',
  'course_title': '概率论',
  'lifecycle': 'active',
  'certainty': 'tentative',
  'location': '待通知',
  'time': {'precision': 'week', 'week': 14},
  'reminders': [],
};
Map<String, dynamic> hub(ScheduleFixture f) => {
  'semester': semester(),
  'revision': 1,
  'valid_until': DateTime.now()
      .add(const Duration(minutes: 1))
      .toIso8601String(),
  'risk': {
    'items': [],
    'valid_until': DateTime.now()
        .add(const Duration(minutes: 1))
        .toIso8601String(),
  },
  'course': {'id': 'c', 'title': '合成概率论', 'teacher': '示例教师'},
  'items': [f.item, exam(f)],
  'occurrences': [],
  'changes': [],
  'courses': [
    {
      'id': 'c',
      'title': '合成概率论',
      'teacher': '示例教师',
      'task_count': 1,
      'exam_count': 1,
    },
  ],
  'exams': [
    {
      'exam': exam(f),
      'reviews': [],
      'review_remaining_minutes': 0,
      'review_planned_minutes': 0,
      'review_unplanned_minutes': 0,
      'issues': [],
    },
  ],
  'weeks': [
    {
      'week': 14,
      'start_date': '2026-11-30',
      'end_date': '2026-12-06',
      'items': [exam(f)],
      'changes': [],
      'available_minutes': null,
      'planned_minutes': 0,
      'known_due_remaining_minutes': 0,
      'load_level': 'unknown',
    },
  ],
  'undated': [],
  'outside': [],
};

Future<ScheduleFixture> fixture(WidgetTester tester) async {
  final f = ScheduleFixture();
  await tester.runAsync(() => f.c.bind('s'));
  final old = f.api.dio.httpClientAdapter as ControlledTransport;
  f.api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.path.endsWith('/hub')) return body(hub(f));
    if (r.path.contains('/calendar?')) {
      return body({
        'semester_id': 's',
        'revision': 1,
        'entries': [],
        'undated': [],
      });
    }
    return old.respond(r);
  });
  return f;
}

Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 35)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'semester course access is secondary and returns to visible timeline',
    (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: SemesterHome(controller: f.c, onManage: () {}),
          ),
        ),
      );
      await settleIo(tester);
      expect(find.text('合成概率论考试'), findsOneWidget);
      await tester.ensureVisible(find.text('课程事务（1门）'));
      await tester.tap(find.text('课程事务（1门）'));
      await tester.pumpAndSettle();
      expect(find.text('合成概率论'), findsOneWidget);
      Navigator.pop(tester.element(find.text('合成概率论')));
      await tester.pumpAndSettle();
      expect(find.text('合成概率论考试'), findsOneWidget);
      expect(find.byType(AppDisclosure), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('course hub renders related work and stale risk is labelled', (
    tester,
  ) async {
    final f = await fixture(tester);
    await route(tester, CourseHubPage(controller: f.c, courseId: 'c'));
    await settleIo(tester);
    expect(find.text('合成概率论'), findsOneWidget);
    expect(find.text('合成报告'), findsOneWidget);
    await capture(tester, 'course-hub');
    f.c.observeRevision('s', 2);
    await tester.pumpAndSettle();
    expect(find.textContaining('分析过期'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'course hub offers edit and shows deletion impact before writing',
    (tester) async {
      final f = await fixture(tester);
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/courses/c')) {
          return body({
            'id': 'c',
            'semester_id': 's',
            'revision': 1,
            'course': {
              'title': '合成概率论',
              'teacher': '示例教师',
              'location': 'A305',
              'weekday': 3,
              'weeks': [1, 3, 5],
              'sections': [1, 2],
              'source_id': '',
            },
          });
        }
        if (request.path.endsWith('/courses/c/delete-preview')) {
          return body({
            'course_id': 'c',
            'semester_id': 's',
            'title': '合成概率论',
            'revision': 1,
            'meetings': 1,
            'linked_items': 1,
          });
        }
        return old.respond(request);
      });
      await route(tester, CourseHubPage(controller: f.c, courseId: 'c'));
      await settleIo(tester);
      await tester.ensureVisible(find.text('编辑课程安排'));
      await tester.tap(find.text('编辑课程安排'));
      await settleIo(tester);
      expect(find.text('编辑课程'), findsOneWidget);
      Navigator.pop(tester.element(find.text('编辑课程')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('删除这门课程'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('删除这门课程'));
      await settleIo(tester);
      expect(find.textContaining('1 条关联事项会保留'), findsOneWidget);
      expect(find.text('确认删除'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('timeline shows week-only exam without inventing a date', (
    tester,
  ) async {
    final f = await fixture(tester);
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: SemesterHome(controller: f.c, onManage: () {}),
        ),
      ),
      width: 360,
      textScale: 1.6,
    );
    await settleIo(tester);
    final week = find.byKey(const ValueKey('semester-week-14'));
    await tester.ensureVisible(week);
    expect(tester.widget<Semantics>(week).properties.selected, isTrue);
    final weekOnly = find.textContaining('第14周 · 具体日期待确认');
    await tester.ensureVisible(weekOnly);
    expect(weekOnly, findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'semester-timeline-large');
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'review duration is explicit and tentative exam has no inherited deadline',
    (tester) async {
      final f = await fixture(tester);
      Map<String, dynamic>? sent;
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/reviews')) {
          sent = Map<String, dynamic>.from(r.data);
          return body(f.item, 201);
        }
        return old.respond(r);
      });
      await route(tester, ReviewSetupPage(controller: f.c, exam: exam(f)));
      expect(find.text('确认以考试开始时刻为截止'), findsNothing);
      await ioTap(tester, find.text('创建复习任务'));
      expect(sent, isNull);
      expect(find.text('请明确填写复习剩余分钟数'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('review-minutes')), '180');
      await ioTap(tester, find.text('创建复习任务'));
      expect(sent!['remaining_minutes'], 180);
      expect(sent!['deadline_mode'], 'unknown');
      expect(sent!['start_policy'], 'unconfirmed');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'exam change preview never applies before confirmation and stale revision disables it',
    (tester) async {
      final f = await fixture(tester);
      final p = {
        'base_revision': 1,
        'before': exam(f),
        'after': {
          ...exam(f),
          'time': {'precision': 'week', 'week': 15},
        },
        'reviews': [],
        'reminders_after': [],
        'affected_blocks': [],
        'risk_changes': [],
        'fixed_conflicts': [],
        'fixed_conflict_count': 0,
      };
      await route(
        tester,
        ExamChangePreviewPage(
          controller: f.c,
          preview: p,
          request: {'reason': '教师通知'},
        ),
      );
      await capture(tester, 'exam-change-preview');
      f.c.observeRevision('s', 2);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('确认考试新安排'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '确认考试新安排'))
            .onPressed,
        isNull,
      );
      expect(find.text('账号、学期或安排已变化，请重新预览'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'exam center displays review coverage separately from completion',
    (tester) async {
      final f = await fixture(tester);
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) {
          final data = hub(f);
          data['exams'][0].addAll({
            'reviews': [f.item],
            'review_remaining_minutes': 120,
            'review_planned_minutes': 45,
            'review_unplanned_minutes': 75,
          });
          return body(data);
        }
        return previous.respond(r);
      });
      await route(
        tester,
        ExamCenterPage(controller: f.c, semester: semester()),
      );
      await settleIo(tester);
      expect(find.text('合成概率论考试'), findsOneWidget);
      await capture(tester, 'exam-center');
      expect(find.textContaining('已安排复习'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
