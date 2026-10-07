import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/features/centers/exam_pages.dart';
import 'package:semester_os/features/changes/changes_page.dart';
import 'package:semester_os/features/timetable/course_widgets.dart';
import 'package:semester_os/features/calendar/event_overview.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'centers_flow_test.dart' show fixture, hub, exam, semester, settleIo;
import 'changes_flow_test.dart' show change;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

/// Renders production pages with the same synthetic protocol fixtures used by
/// the behavior suites. No server, account or real student data is involved.
class _AcademicFixture {
  final ScheduleFixture data;
  int writes = 0, parses = 0;
  _AcademicFixture(this.data);

  Map<String, dynamic> get occurrence => {
    'id': 'occurrence-c-1',
    'course_id': 'c',
    'title': '合成概率论',
    'location': '教学楼 A305',
    'start_at': data.start.toIso8601String(),
    'end_at': data.start.add(const Duration(minutes: 100)).toIso8601String(),
    'changed': false,
  };

  Map<String, dynamic> get review => {
    ...data.item,
    'title': '概率论复习：随机变量与分布',
    'review_exam_id': 'exam',
  };

  Map<String, dynamic> get courseHub {
    final value = hub(data);
    value['occurrences'] = [occurrence];
    value['changes'] = [
      {
        'kind': 'move',
        'title': '概率论上课地点调整',
        'source_text': '合成通知：本次课程使用 A305 教室。',
        'before': [occurrence],
        'after': [
          {...occurrence, 'location': '教学楼 A305'},
        ],
      },
    ];
    value['exams'][0].addAll({
      'reviews': [review],
      'review_remaining_minutes': 120,
      'review_planned_minutes': 45,
      'review_unplanned_minutes': 75,
      'completed_review_count': 0,
    });
    return value;
  }

  Map<String, dynamic> get examPreview => {
    'base_revision': 1,
    'preview_token': 'synthetic-preview-only',
    'before': exam(data),
    'after': {
      ...exam(data),
      'certainty': 'formal',
      'location': '教学楼 B204',
      'time': {
        'precision': 'exact',
        'at': data.start.toIso8601String(),
        'end_at': data.start.add(const Duration(hours: 2)).toIso8601String(),
      },
    },
    'reviews': [
      {
        'title': review['title'],
        'will_align': true,
        'after_time': {
          'precision': 'exact',
          'at': data.start.toIso8601String(),
        },
      },
    ],
    'reminders_after': [
      {
        'mode': 'relative',
        'lead_minutes': 60,
        'trigger_at': data.start
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'schedule_state': 'scheduled',
      },
    ],
    'review_reminders_after': [],
    'affected_blocks': [
      {
        'title': '概率论错题复盘',
        'start_at': data.start.toIso8601String(),
        'locked': true,
      },
    ],
    'risk_changes': [
      {'title': '概率论复习', 'before_slack': 180, 'after_slack': 60},
    ],
    'fixed_conflicts': [
      {
        'titles': ['合成概率论考试', '实验课程'],
        'start_at': data.start.toIso8601String(),
        'end_at': data.start.add(const Duration(minutes: 30)).toIso8601String(),
      },
    ],
    'fixed_conflict_count': 1,
  };

  Map<String, dynamic> get coursePreview {
    final value = change(data, conflict: true);
    value['impact']['affected_blocks'] = [
      {
        'title': '合成报告资料整理',
        'start_at': data.start.toIso8601String(),
        'locked': true,
      },
    ];
    value['request']['source_text'] = notice;
    value['patch']['before'][0]['location'] = '教学楼 A305';
    value['patch']['after'][0]['location'] = '教学楼 B204';
    return value;
  }

  static const notice =
      '合成教学通知：因教室维护，概率论本次课程调整至新的时间，地点改为教学楼 B204。'
      '请同学核对本次课次；其他课程仍按原课表上课。';
}

Future<_AcademicFixture> _prepare(WidgetTester tester) async {
  final result = _AcademicFixture(await fixture(tester));
  final f = result.data;
  final previous = f.api.dio.httpClientAdapter as ControlledTransport;
  f.api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.method == 'GET' && r.path.endsWith('/hub')) {
      return body(result.courseHub);
    }
    if (r.method == 'GET' && r.path.endsWith('/changes')) {
      return body({
        'semester_id': 's',
        'revision': 1,
        'occurrences': [result.occurrence],
        'changes': [result.coursePreview],
      });
    }
    if (r.method == 'POST' && r.path.endsWith('/changes/parse')) {
      result.parses++;
      return body({
        'suggestion': {
          'kind': 'move',
          'title': '合成概率论',
          'location': '教学楼 B204',
          'start_at': f.start.add(const Duration(hours: 2)).toIso8601String(),
          'end_at': f.start.add(const Duration(hours: 3)).toIso8601String(),
          'questions': [],
          'evidence': {'source': '概率论本次课程调整，其他课程保持'},
        },
        'target_candidates': ['occurrence-c-1'],
      });
    }
    if (r.method != 'GET') {
      result.writes++;
      throw StateError('Visual review must not save a schedule');
    }
    return previous.respond(r);
  });
  return result;
}

Finder _verticalScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _show(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    360,
    scrollable: _verticalScroll(),
    maxScrolls: 60,
  );
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await capture(tester, 'inner-academic-$name');
  expect(tester.takeException(), isNull);
}

Future<void> _close(WidgetTester tester, _AcademicFixture f) async {
  expect(f.writes, 0, reason: 'Viewing and validation must not save changes.');
  await tester.pumpWidget(const SizedBox());
  f.data.c.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets('small course details retain a long title and compact periods', (
    tester,
  ) async {
    final course = <String, dynamic>{
      'title': '习近平新时代中国特色社会主义思想概论',
      'start_at': '2026-10-03T14:30:00+08:00',
      'end_at': '2026-10-03T16:05:00+08:00',
      'weeks': List.generate(15, (i) => i + 1),
      'sections': [5, 6],
      'attendance_exempt': true,
    };
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppButton(
                onPressed: () => showCourseDetails(context, course),
                child: Text(courseTitle(course)),
              ),
            ],
          ),
        ),
      ),
      width: 320,
      height: 740,
      textScale: 1.6,
    );
    await _shot(tester, 'course-long-small');
    await tester.tap(find.text(courseTitle(course)));
    await tester.pumpAndSettle();
    await _show(tester, find.text('第5–6节'));
    expect(find.text('地点'), findsNothing);
    expect(find.text('教师'), findsNothing);
    expect(find.textContaining('学校的固定安排'), findsNothing);
    await _shot(tester, 'course-detail-small');
    await _show(tester, find.text('返回课表'));
    await tester.tap(find.text('返回课表'));
    await tester.pumpAndSettle();
    expect(find.text(courseTitle(course)), findsOneWidget);
  });

  testWidgets(
    'small event overview keeps a start-only time and no absent facts',
    (tester) async {
      await mount(
        tester,
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: EventOverview(
              category: '校园事务',
              row: {
                'title': '学生代表座谈会与意见收集',
                'time': {
                  'precision': 'exact_start',
                  'at': '2026-10-03T14:00:00+08:00',
                },
                'tags': [
                  {'name': '座谈会'},
                  {'name': '线下'},
                ],
              },
            ),
          ),
        ),
        width: 320,
        height: 740,
        textScale: 1.6,
      );
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('地点'), findsNothing);
      expect(find.text('结束'), findsNothing);
      expect(find.text('校园事务 · 线下'), findsOneWidget);
      await _shot(tester, 'event-overview-small');
    },
  );
  for (final scale in [1.0, 1.6]) {
    final size = scale == 1 ? 'normal' : 'large';

    testWidgets('academic course hub gallery $size', (tester) async {
      final f = await _prepare(tester);
      await mount(
        tester,
        CourseHubPage(controller: f.data.c, courseId: 'c'),
        width: scale == 1 ? 390 : 320,
        height: scale == 1 ? 844 : 740,
        textScale: scale,
      );
      await settleIo(tester);
      expect(find.text('合成概率论'), findsOneWidget);
      await _shot(tester, 'course-hub-$size');
      await _show(tester, find.text('调课或停课'));
      await _shot(tester, 'course-hub-records-$size');
      await _close(tester, f);
    });

    testWidgets('academic exam center gallery $size', (tester) async {
      final f = await _prepare(tester);
      await mount(
        tester,
        ExamCenterPage(controller: f.data.c, semester: semester()),
        width: scale == 1 ? 390 : 320,
        height: scale == 1 ? 844 : 740,
        textScale: scale,
      );
      await settleIo(tester);
      expect(find.text('第14周'), findsOneWidget);
      expect(find.text('暂定'), findsOneWidget);
      await _shot(tester, 'exam-center-$size');
      await _show(tester, find.text('复习任务'));
      await _shot(tester, 'exam-center-review-$size');
      expect(find.textContaining('已安排复习'), findsOneWidget);
      await _close(tester, f);
    });

    testWidgets(
      'academic review setup gallery and explicit effort gate $size',
      (tester) async {
        final f = await _prepare(tester);
        await mount(
          tester,
          ReviewSetupPage(controller: f.data.c, exam: exam(f.data)),
          width: scale == 1 ? 390 : 320,
          height: scale == 1 ? 844 : 740,
          textScale: scale,
        );
        expect(find.text('考试开始前'), findsNothing);
        await _shot(tester, 'review-setup-$size');
        await _show(tester, find.text('复习时间'));
        await _shot(tester, 'review-setup-conditions-$size');
        await tester.tap(find.text('创建复习任务'));
        await tester.pumpAndSettle();
        expect(find.text('请明确填写复习剩余分钟数'), findsOneWidget);
        await _shot(tester, 'review-setup-validation-$size');
        await _close(tester, f);
      },
    );

    testWidgets(
      'academic exam reschedule gallery with optional note and required valid week $size',
      (tester) async {
        final f = await _prepare(tester);
        await mount(
          tester,
          ExamReschedulePage(controller: f.data.c, exam: exam(f.data)),
          width: scale == 1 ? 390 : 320,
          height: scale == 1 ? 844 : 740,
          textScale: scale,
        );
        await _shot(tester, 'exam-reschedule-$size');
        await _show(tester, find.text('确认状态与复习'));
        await _shot(tester, 'exam-reschedule-conditions-$size');
        final weekField = find.byWidgetPredicate(
          (w) => w is AppField && w.decoration.labelText == '第几周',
        );
        await _show(tester, weekField);
        await tester.enterText(weekField, '');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看改期影响'));
        await tester.pumpAndSettle();
        expect(find.text('请输入周次'), findsOneWidget);
        expect(find.text('请填写改期原因'), findsNothing);
        await _close(tester, f);
      },
    );

    testWidgets(
      'academic exam change preview gallery and fixed conflict gate $size',
      (tester) async {
        final f = await _prepare(tester);
        await mount(
          tester,
          ExamChangePreviewPage(
            controller: f.data.c,
            preview: f.examPreview,
            request: {'reason': _AcademicFixture.notice},
          ),
          width: scale == 1 ? 390 : 320,
          height: scale == 1 ? 844 : 740,
          textScale: scale,
        );
        await _shot(tester, 'exam-preview-$size');
        await _show(tester, find.text('学习安排影响'));
        await _shot(tester, 'exam-preview-impact-$size');
        final submit = find.widgetWithText(AppButton, '确认考试新安排');
        await _show(tester, find.text('确认考试新安排'));
        expect(tester.widget<AppButton>(submit).onPressed, isNull);
        await _shot(tester, 'exam-preview-confirm-$size');
        await tester.tap(find.byType(AppCheckRow));
        await tester.pumpAndSettle();
        expect(tester.widget<AppButton>(submit).onPressed, isNotNull);
        f.data.c.observeRevision('s', 2);
        await tester.pumpAndSettle();
        // The inserted warning can push the lazy-list button out of the
        // mounted viewport at large text sizes. Reveal it again.
        await _show(tester, submit);
        expect(tester.widget<AppButton>(submit).onPressed, isNull);
        await _close(tester, f);
      },
    );

    testWidgets(
      'academic changes editor gallery is only a prepared preview $size',
      (tester) async {
        final f = await _prepare(tester);
        await mount(
          tester,
          ChangesPage(
            controller: f.data.c,
            initialText: _AcademicFixture.notice,
          ),
          width: scale == 1 ? 390 : 320,
          height: scale == 1 ? 844 : 740,
          textScale: scale,
        );
        await settleIo(tester);
        await _shot(tester, 'changes-editor-$size');
        await _show(tester, find.text('智能填写'));
        await tester.tap(find.text('智能填写'));
        await settleIo(tester);
        expect(f.parses, 1);
        await _show(tester, find.text('选择受影响课次（已选1次）'));
        await _shot(tester, 'changes-editor-selected-$size');
        await _show(tester, find.text('新地点（可留空）'));
        await _shot(tester, 'changes-editor-time-$size');
        await _close(tester, f);
      },
    );

    testWidgets(
      'academic course change preview gallery and fixed conflict gate $size',
      (tester) async {
        final f = await _prepare(tester);
        await mount(
          tester,
          ChangePreviewPage(controller: f.data.c, preview: f.coursePreview),
          width: scale == 1 ? 390 : 320,
          height: scale == 1 ? 844 : 740,
          textScale: scale,
        );
        await _shot(tester, 'course-preview-$size');
        await _show(tester, find.text('相关学习安排'));
        await _shot(tester, 'course-preview-impact-$size');
        final submit = find.widgetWithText(AppButton, '保存修改');
        await _show(tester, find.text('保存修改'));
        expect(tester.widget<AppButton>(submit).onPressed, isNull);
        await _shot(tester, 'course-preview-confirm-$size');
        await tester.tap(find.byType(AppCheckRow));
        await tester.pumpAndSettle();
        expect(tester.widget<AppButton>(submit).onPressed, isNotNull);
        f.data.c.observeRevision('s', 2);
        await tester.pumpAndSettle();
        // The inserted warning can push the lazy-list button out of the
        // mounted viewport at large text sizes. Reveal it again.
        await _show(tester, submit);
        expect(tester.widget<AppButton>(submit).onPressed, isNull);
        await _close(tester, f);
      },
    );
  }
}
