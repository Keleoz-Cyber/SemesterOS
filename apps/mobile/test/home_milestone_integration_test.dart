import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/home/home_preferences.dart';
import 'package:semester_os/features/calendar/calendar_repository.dart';
import 'package:semester_os/features/home/today_view_enhanced.dart';
import 'package:semester_os/features/home/time_stats_card.dart';
import 'package:semester_os/features/home/semester_progress.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/ui/breathing_card.dart';
import 'package:semester_os/ui/empty_scene.dart';
import 'package:semester_os/ui/time_river.dart';
import 'package:semester_os/ui/week_heatmap.dart';
import 'package:semester_os/ui/accessibility.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'controller_test.dart' show MemoryStore;
import 'ui_polish_test.dart' show mount;

void main() {
  test(
    'Today choice and task order persist only in the same account and term',
    () async {
      final store = MemoryStore();
      final prefs = HomePreferences(store, 'a', 's', () => true);
      await prefs.change(todayView: TodayViewMode.tasks, taskOrder: ['2', '1']);
      final same = HomePreferences(store, 'a', 's', () => true);
      final account = HomePreferences(store, 'b', 's', () => true);
      final term = HomePreferences(store, 'a', 't', () => true);
      await Future.wait([same.restore(), account.restore(), term.restore()]);
      expect(same.todayView, TodayViewMode.tasks);
      expect(same.taskOrder, ['2', '1']);
      expect(account.todayView, isNull);
      expect(term.taskOrder, isEmpty);
      expect(same.enabled.contains('breathing_exercise'), isFalse);
      for (final p in [prefs, same, account, term]) {
        p.dispose();
      }
    },
  );

  test('Unknown or non-deadline times have no urgency or guessed progress', () {
    for (final meaning in ['start', 'window', 'candidate', 'course_anchor']) {
      expect(
        itemDeadline({
          'kind': 'task',
          'anchor_at': '2026-10-02T00:00:00Z',
          'time': {'precision': 'exact', 'meaning': meaning},
        }),
        isNull,
      );
    }
    expect(
      itemDeadline({
        'kind': 'task',
        'time': {'precision': 'date', 'date': '2026-10-02'},
      }),
      isNull,
    );
    expect(TimeUrgency.level(null), isNull);
    expect(TimeUrgency.level(119), DeadlineUrgency.critical);
    expect(TimeUrgency.level(120), DeadlineUrgency.soon);
    expect(TimeUrgency.level(720), DeadlineUrgency.approaching);
    expect(TimeUrgency.level(4320), DeadlineUrgency.future);
    expect(
      TimeUrgency.getProgressPercentage(DateTime.utc(2026, 10, 3), null),
      0,
    );
  });

  testWidgets(
    'Time river consumes the school clock once and keeps unknown ends as points',
    (tester) async {
      final now = DateTime.utc(2026, 10, 2, 7, 30);
      Map<String, dynamic>? openedEvent;
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              TimeRiverView(
                now: now,
                day: DateTime.utc(2026, 10, 2),
                onEventTap: (row) => openedEvent = row,
                events: [
                  {
                    'id': 'known',
                    'title': '晨间课程',
                    'resource_type': 'course',
                    'start_at': '2026-10-02T07:00:00+08:00',
                    'end_at': '2026-10-02T08:00:00+08:00',
                  },
                  {
                    'id': 'point',
                    'title': '开始时间已知',
                    'resource_type': 'event',
                    'start_at': '2026-10-02T10:00:00+08:00',
                  },
                ],
              ),
            ],
          ),
        ),
      );
      expect(find.text('现在 07:30'), findsOneWidget);
      expect(find.text('现在 15:30'), findsNothing);
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('开始时间已知'), findsOneWidget);
      expect(find.textContaining('结束时间待定'), findsNothing);
      final progress = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('time-track-event-progress')),
      );
      expect(progress.value, .5);
      await tester.tap(find.text('开始时间已知'));
      await tester.pumpAndSettle();
      expect(openedEvent?['id'], 'point');
      expect(openedEvent?['end_at'], isNull);
      expect(tester.takeException(), isNull);
      await mount(
        tester,
        Scaffold(
          body: SemesterProgressCard(
            semester: const {'first_monday': '2026-09-21', 'total_weeks': 16},
            now: now,
          ),
        ),
      );
      expect(find.text('学期进度'), findsOneWidget);
      expect(find.text('第2周'), findsOneWidget);
      expect(find.text('共16周'), findsOneWidget);
      expect(find.textContaining('期中'), findsNothing);
      final calendarProgress = tester.widget<SemanticProgressBar>(
        find.byType(SemanticProgressBar),
      );
      expect(calendarProgress.label, '学期日历进度');
      expect(
        calendarProgress.value,
        closeTo(
          now.difference(DateTime.utc(2026, 9, 21)).inMinutes /
              const Duration(days: 16 * 7).inMinutes,
          1e-10,
        ),
      );
    },
  );

  test(
    'Heatmap clips partial hours and counts overlaps while statistics merge them',
    () {
      final hour = DateTime.utc(2026, 10, 2, 10);
      final blocks = [
        TimeBlock(
          start: hour.add(const Duration(minutes: 20)),
          end: hour.add(const Duration(minutes: 40)),
          title: 'A',
        ),
        TimeBlock(
          start: hour.add(const Duration(minutes: 30)),
          end: hour.add(const Duration(hours: 1)),
          title: 'B',
        ),
        TimeBlock(
          start: hour.add(const Duration(minutes: 15)),
          end: hour.add(const Duration(minutes: 15)),
          title: 'point',
        ),
      ];
      final cell = heatmapHour(blocks, hour);
      expect(cell.minutes, 50);
      expect(cell.count, 2);
      expect(cell.points, 1);
      final stats = recordedTimeStats(
        [
          {
            'start_at': '2026-10-02T10:20:00+08:00',
            'end_at': '2026-10-02T10:40:00+08:00',
          },
          {
            'start_at': '2026-10-02T10:30:00+08:00',
            'end_at': '2026-10-02T11:00:00+08:00',
          },
          {'start_at': '2026-10-02T10:15:00+08:00'},
          {
            'resource_type': 'course',
            'attendance_exempt': true,
            'start_at': '2026-10-02T10:00:00+08:00',
            'end_at': '2026-10-02T11:00:00+08:00',
          },
        ],
        hour,
        hour.add(const Duration(hours: 1)),
      );
      expect(stats.minutes, 40);
      expect(stats.unknownDuration, 1);
      expect(calendarReservesTime({'attendance_exempt': true}), isFalse);
      expect(
        calendarDisplayEntry({
          'title': '参考课程',
          'attendance_exempt': true,
        })['title'],
        '免听 · 参考课程',
      );
    },
  );

  testWidgets(
    'Today remains available with empty agenda or only undated tasks',
    (tester) async {
      final now = DateTime.utc(2026, 10, 2);
      final completed = <String>[];
      await mount(
        tester,
        Scaffold(
          body: ListView(
            children: [
              TodayViewSwitch(
                timeline: const [],
                tasks: const [
                  {
                    'id': 'undated',
                    'kind': 'task',
                    'title': '待补充日期的事项',
                    'lifecycle': 'active',
                    'time': {'precision': 'none'},
                  },
                ],
                now: now,
                day: now,
                onEventTap: (_) {},
                onTaskTap: (_) {},
                onTaskComplete: (row) async => completed.add('${row['id']}'),
              ),
            ],
          ),
        ),
      );
      expect(find.text('待补充日期的事项'), findsOneWidget);
      expect(find.text('今日日程'), findsOneWidget);
      expect(find.text('待办任务'), findsOneWidget);
      expect(find.text('今天没有安排'), findsOneWidget);
      final completion = find.widgetWithText(AppTextButton, '完成');
      expect(completion, findsOneWidget);
      expect(tester.getSize(completion).height, greaterThanOrEqualTo(48));
      await tester.tap(completion);
      await tester.pumpAndSettle();
      expect(completed, ['undated']);
      expect(tester.takeException(), isNull);
      var openedAll = 0;
      final preferences = HomePreferences(
        MemoryStore(),
        'large',
        's',
        () => true,
      );
      preferences.todayView = TodayViewMode.tasks;
      preferences.taskOrder = [for (var i = 0; i < 1000; i++) '$i', 'hidden'];
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: TodayViewSwitch(
              key: const ValueKey('large-preview'),
              timeline: const [],
              tasks: [
                for (var i = 0; i < 1000; i++)
                  {
                    'id': '$i',
                    'kind': 'task',
                    'title': '事项 $i',
                    'lifecycle': 'active',
                    'time': {'precision': 'unknown'},
                  },
              ],
              now: now,
              day: now,
              preferences: preferences,
              onEventTap: (_) {},
              onTaskTap: (_) {},
              onAllTasks: () {
                openedAll++;
              },
            ),
          ),
        ),
      );
      expect(find.byType(ItemCard), findsNWidgets(8));
      expect(find.text('查看全部 1000 项'), findsOneWidget);
      final preview = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      preview.onReorderItem!(0, 7);
      await tester.pumpAndSettle();
      expect(preferences.taskOrder.length, 1001);
      expect(preferences.taskOrder[7], '0');
      expect(preferences.taskOrder[8], '8');
      expect(preferences.taskOrder.last, 'hidden');
      await tester.ensureVisible(find.text('查看全部 1000 项'));
      await tester.tap(find.text('查看全部 1000 项'));
      await tester.pumpAndSettle();
      expect(openedAll, 1);
      await tester.pumpWidget(const SizedBox());
      preferences.dispose();
    },
  );

  testWidgets('Urgent cue is finite and reduced motion stays static', (
    tester,
  ) async {
    Widget app(bool reduced) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const Column(
          children: [
            AppEmptyScene(kind: EmptySceneKind.agenda),
            AppEmptyScene(kind: EmptySceneKind.tasks),
            AppEmptyScene(kind: EmptySceneKind.search),
            AppEmptyScene(),
            BreathingCard(
              enabled: true,
              remainingMinutes: 30,
              child: Text('紧急事项'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
