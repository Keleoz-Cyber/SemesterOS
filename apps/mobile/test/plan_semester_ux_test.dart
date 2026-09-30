import 'package:semester_os/ui/app_controls.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:semester_os/app/controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/features/centers/hub_data.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'planning_flow_test.dart' show PlanningFixture, bind;
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'api_session_test.dart' show ControlledTransport, body;
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('overdue and explicit high priority tasks lead the task list', (
    tester,
  ) async {
    final f = PlanningFixture();
    await bind(tester, f);
    f.c.items = [
      {...f.item, 'id': 'ordinary', 'title': '普通任务'},
      {...f.item, 'id': 'important', 'title': '重点任务', 'priority': 'high'},
      {
        ...f.item,
        'id': 'late',
        'title': '逾期任务',
        'anchor_at': '2020-01-01T10:00:00Z',
      },
    ];
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: ItemsView(controller: f.c, onCreate: () {}, onOpen: (_) {}),
        ),
      ),
    );
    final lateY = tester
        .getTopLeft(find.byKey(const ValueKey('plan-task-late')))
        .dy;
    final importantY = tester
        .getTopLeft(find.byKey(const ValueKey('plan-task-important')))
        .dy;
    final ordinaryY = tester
        .getTopLeft(find.byKey(const ValueKey('plan-task-ordinary')))
        .dy;
    expect(lateY, lessThan(importantY));
    expect(importantY, lessThan(ordinaryY));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plan-task-important')),
        matching: find.textContaining('优先'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets(
    'current week is selected, week changes load once and refresh awaits activities',
    (tester) async {
      final f = await fixture(tester);
      final now = schoolNow();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      String date(DateTime day) => day.toIso8601String().substring(0, 10);
      final data = hub(f);
      data['semester'] = {
        ...data['semester'],
        'first_monday': date(monday.subtract(const Duration(days: 7))),
      };
      data['weeks'] = [
        for (var i = 1; i <= 3; i++)
          {
            'week': i,
            'start_date': date(monday.add(Duration(days: (i - 2) * 7))),
            'end_date': date(monday.add(Duration(days: (i - 2) * 7 + 6))),
            'items': [
              {
                ...f.item,
                'id': 'task-$i',
                'title': '第$i周报告',
                'time': {'precision': 'week', 'week': i},
              },
            ],
            'changes': [],
          },
      ];
      final calls = <String>[];
      Completer<void>? gate;
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) return body(data);
        if (r.path.contains('/calendar?')) {
          calls.add('${r.uri.queryParameters['from_date']}');
          if (gate != null) await gate!.future;
          return body({
            'semester_id': 's',
            'revision': 1,
            'entries': [
              {
                'id': 'event:meet',
                'resource_id': 'meet',
                'resource_type': 'event',
                'title': '社团见面会',
                'start_at':
                    '${r.uri.queryParameters['from_date']}T10:00:00+08:00',
              },
              {
                'id': 'course:c',
                'resource_type': 'course',
                'title': '不重复显示整张课表',
              },
            ],
            'undated': [
              {
                'id': 'event:later',
                'resource_id': 'later',
                'resource_type': 'event',
                'title': '日期未定的志愿活动',
              },
            ],
          });
        }
        return previous.respond(r);
      });
      final key = GlobalKey<SemesterHomeState>();
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: SemesterHome(key: key, controller: f.c, onManage: () {}),
          ),
        ),
      );
      await settleIo(tester);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('semester-week-2')))
            .properties
            .selected,
        isTrue,
      );
      expect(find.text('第2周报告'), findsOneWidget);
      expect(find.text('第1周报告'), findsNothing);
      expect(find.text('社团见面会'), findsOneWidget);
      expect(find.text('不重复显示整张课表'), findsNothing);
      expect(find.text('日期未定的志愿活动'), findsOneWidget);
      expect(calls, [date(monday)]);
      await capture(tester, 'semester-current-week');
      await tester.tap(find.byKey(const ValueKey('semester-week-3')));
      await settleIo(tester);
      expect(find.text('第3周报告'), findsOneWidget);
      expect(calls.length, 2);
      await tester.tap(find.byKey(const ValueKey('semester-week-3')));
      await settleIo(tester);
      expect(calls.length, 2);
      var done = false;
      await tester.runAsync(() async {
        gate = Completer<void>();
        final refresh = key.currentState!.reload().then((_) => done = true);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(done, isFalse);
        gate!.complete();
        await refresh;
      });
      expect(done, isTrue);
      expect(calls.length, 3);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'hidden hubs wait for activation and refresh expired data on return',
    (tester) async {
      final f = await fixture(tester);
      var calls = 0;
      final data = hub(f);
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) {
          calls++;
          return body(data);
        }
        return previous.respond(r);
      });
      final enabled = ValueNotifier(false);
      final key = GlobalKey<HubDataState>();
      await mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (_, active, _) => TickerMode(
            enabled: active,
            child: Scaffold(
              body: SingleChildScrollView(
                child: HubData(
                  key: key,
                  controller: f.c,
                  path: '/semesters/s/hub',
                  builder: (_, data, fresh, reload) =>
                      Text(data['semester']['name']),
                ),
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(calls, 0);
      enabled.value = true;
      await settleIo(tester);
      expect(calls, 1);
      enabled.value = false;
      await tester.pump();
      enabled.value = true;
      await settleIo(tester);
      expect(calls, 1);
      enabled.value = false;
      await tester.pump();
      key.currentState!.data!['valid_until'] = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      enabled.value = true;
      await settleIo(tester);
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final count = calls;
      await tester.pump(const Duration(minutes: 3));
      await settleIo(tester);
      expect(calls, count);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIo(tester);
      await tester.pumpWidget(const SizedBox());
      enabled.dispose();
      f.c.dispose();
    },
  );
  testWidgets(
    'plan has one learning settings entry and one contextual request',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      String? request;
      bool submitted = false;
      await mount(
        tester,
        Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: Theme.of(context),
            builder: (context, child) => AssistantScope(
              onOpen:
                  (
                    context, {
                    initialText,
                    mediaKind,
                    autoSubmit = false,
                  }) async {
                    request = initialText;
                    submitted = autoSubmit;
                  },
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: ItemsView(
                  controller: f.c,
                  onCreate: () {},
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('重新计算'), findsNothing);
      expect(find.text('生成计划'), findsNothing);
      expect(find.text('学习时间设置'), findsOneWidget);
      await tester.tap(find.text('安排任务'));
      await tester.pumpAndSettle();
      expect(request, contains('任务'));
      expect(submitted, isTrue);
      await capture(tester, 'plan-actionable');
      f.c.analysis!['summary']['configured'] = false;
      f.c.changed();
      await tester.pumpAndSettle();
      expect(find.text('学习时间设置'), findsNothing);
      expect(find.text('设置可学习时间'), findsOneWidget);
      request = null;
      await tester.tap(find.text('安排记录'));
      await settleIo(tester);
      expect(find.text('生成新的计划方案'), findsNothing);
      expect(find.text('尽量少改动，重排已有计划'), findsNothing);
      await tester.tap(find.text('安排任务'));
      await tester.pumpAndSettle();
      expect(request, contains('任务'));
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'semester opens selected week timeline without week expansion stack',
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
      final selectedWeek = find.byKey(const ValueKey('semester-week-14'));
      expect(selectedWeek, findsOneWidget);
      expect(
        tester.widget<Semantics>(selectedWeek).properties.selected,
        isTrue,
      );
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(AppDisclosure), findsNothing);
      expect(find.text('合成概率论考试'), findsOneWidget);
      expect(find.text('刷新本页'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'hub retains facts on failure and stops fetching while inactive',
    (tester) async {
      final f = await fixture(tester);
      var fail = false, calls = 0;
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) {
          calls++;
          if (fail) throw Exception('离线');
          return body(hub(f));
        }
        return previous.respond(r);
      });
      final enabled = ValueNotifier(true);
      await mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, active, _) => TickerMode(
            enabled: active,
            child: Scaffold(
              body: SingleChildScrollView(
                child: HubData(
                  controller: f.c,
                  path: '/semesters/s/hub',
                  builder: (_, data, fresh, reload) =>
                      Text(data['semester']['name']),
                ),
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      expect(calls, 1);
      fail = true;
      await tester.pump(const Duration(seconds: 46));
      await settleIo(tester);
      expect(find.text('示例学期 · 合成数据'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      enabled.value = false;
      await tester.pump();
      final before = calls;
      await tester.pump(const Duration(minutes: 3));
      await settleIo(tester);
      expect(calls, before);
      await tester.pumpWidget(const SizedBox());
      enabled.dispose();
      f.c.dispose();
    },
  );
}
