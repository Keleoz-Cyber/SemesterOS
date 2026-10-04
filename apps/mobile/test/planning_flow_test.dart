import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'package:semester_os/features/planning/availability_page.dart';
import 'package:semester_os/features/planning/progress_page.dart';
import 'package:semester_os/features/planning/risk_widgets.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'reminder_sync_test.dart' show FakeNotifications;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

class PlanningFixture {
  final api = SemesterApi()..session = account('preview');
  late final ItemsController c;
  int revision = 1,
      settingsVersion = 0,
      previews = 0,
      puts = 0,
      progressSaves = 0;
  Map<String, dynamic>? lastProgress, lastItem;
  Map<String, dynamic> preferences = {
    'configured': false,
    'version': 0,
    'weekly': <Map<String, dynamic>>[],
    'exclusions': <Map<String, dynamic>>[],
  };
  Map<String, dynamic> item = {
    'id': 'a',
    'semester_id': 's',
    'kind': 'task',
    'title': '合成任务A',
    'version': 1,
    'lifecycle': 'active',
    'certainty': 'formal',
    'time': {'precision': 'exact', 'at': '2099-09-21T13:00:00+08:00'},
    'start_policy': 'now',
    'remaining_minutes': 150,
    'course_title': '',
    'reminders': <Map<String, dynamic>>[],
  };
  Map<String, dynamic> get risk {
    final now = DateTime.now().toUtc();
    final window = {
      'start_at': now.toIso8601String(),
      'end_at': now.add(const Duration(hours: 5)).toIso8601String(),
      'demand_minutes': 300,
      'capacity_minutes': 240,
      'gap_minutes': 60,
      'capacity_is_upper_bound': false,
    };
    return {
      'semester_id': 's',
      'revision': revision,
      'computed_at': now.toIso8601String(),
      'valid_until': now.add(const Duration(minutes: 1)).toIso8601String(),
      'summary': {
        'configured': true,
        'level': 'high',
        'window_gap_minutes': 60,
        'active_task_count': 2,
        'incomplete_count': 0,
        'fixed_conflict_count': 0,
        'critical_window': window,
      },
      'fixed_conflicts': [],
      'items': [
        {
          'item_id': 'a',
          'item_version': item['version'],
          'title': item['title'],
          'level': 'high',
          'task_slack_minutes': 90,
          'window_gap_minutes': 60,
          'remaining_minutes': 150,
          'capacity_before_fixed_minutes': 240,
          'fixed_occupied_minutes': 0,
          'capacity_after_fixed_minutes': 240,
          'other_plan_minutes': 0,
          'max_contiguous_minutes': 240,
          'critical_window': window,
          'reason_codes': ['window_overload'],
        },
      ],
    };
  }

  PlanningFixture() {
    c = ItemsController(api, MemoryStore(), ReminderSync(FakeNotifications()));
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/courses')) return body([]);
      if (r.path.endsWith('/reminders')) {
        return body({'owner_id': 'preview', 'reminders': []});
      }
      if (r.path.endsWith('/risk')) return body(risk);
      if (r.path.endsWith('/availability/preview')) {
        previews++;
        return body({
          'before': preferences,
          'after': r.data,
          'base_revision': revision,
        });
      }
      if (r.path.endsWith('/availability')) {
        if (r.method == 'PUT') {
          puts++;
          revision++;
          settingsVersion++;
          preferences = {
            ...Map<String, dynamic>.from(r.data),
            'configured': true,
            'version': settingsVersion,
          };
        }
        return body(preferences);
      }
      if (r.path.endsWith('/progress/preview')) {
        return body({
          'base_revision': revision,
          'before_remaining_minutes': item['remaining_minutes'],
          'after_remaining_minutes': r.data['remaining_minutes'],
          'actual_minutes': r.data['actual_minutes'],
          'will_complete': r.data['remaining_minutes'] == 0,
        });
      }
      if (r.path.endsWith('/progress') && r.method == 'POST') {
        progressSaves++;
        lastProgress = Map<String, dynamic>.from(r.data);
        revision++;
        item = {
          ...item,
          'version': 2,
          'remaining_minutes': r.data['remaining_minutes'],
          'lifecycle': r.data['confirm_complete'] == true
              ? 'completed'
              : 'active',
        };
        return body(item);
      }
      if (r.path.endsWith('/items') && r.method == 'POST') {
        lastItem = Map<String, dynamic>.from(r.data);
        return body({...item, ...lastItem!});
      }
      return body({
        'items': [item],
        'revision': revision,
      });
    });
  }
}

Future<void> ioTap(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
  // A press/pop transition can start the actual request on a subsequent frame.
  // Dispatch that frame, then let mock stream I/O complete before expecting
  // the visible waiting indicator to become idle.
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 35)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> bind(WidgetTester tester, PlanningFixture f) async =>
    tester.runAsync(() => f.c.bind('s'));
Future<void> route(WidgetTester tester, Widget page) async {
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: const Text('打开页面'),
        ),
      ),
    ),
  );
  await ioTap(tester, find.text('打开页面'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'exam end is preserved and can explicitly be cleared back to unknown',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      final data = {
        'item': {
          'kind': 'exam',
          'title': '合成考试',
          'certainty': 'formal',
          'time': {
            'precision': 'exact',
            'at': '2099-09-21T09:00:00+08:00',
            'end_at': '2099-09-21T11:00:00+08:00',
          },
        },
      };
      Future<void> open() async => route(
        tester,
        ItemFormPage(
          controller: f.c,
          semester: const {'id': 's', 'total_weeks': 20},
          candidate: data,
        ),
      );
      Future<void> save() async {
        await tester.scrollUntilVisible(
          find.text('保存'),
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await ioTap(tester, find.text('保存'));
      }

      await open();
      await save();
      expect(
        DateTime.parse(f.lastItem!['time']['end_at']),
        DateTime.parse('2099-09-21T11:00:00+08:00'),
      );
      await mount(tester, const SizedBox());
      await open();
      await tester.scrollUntilVisible(
        find.text('移除结束时间'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('移除结束时间'));
      await tester.pumpAndSettle();
      await save();
      expect((f.lastItem!['time'] as Map).containsKey('end_at'), isTrue);
      expect(f.lastItem!['time']['end_at'], isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  test(
    'a newer course revision immediately invalidates previously fresh risk',
    () async {
      final f = PlanningFixture();
      await f.c.bind('s');
      expect(f.c.hasCurrentRisk, isTrue);
      expect(f.c.observeRevision('s', 2), isTrue);
      expect(f.c.hasCurrentRisk, isFalse);
      expect(f.c.analysis, isNull);
      expect(f.c.observeRevision('another-semester', 99), isFalse);
      f.c.dispose();
    },
  );
  testWidgets(
    'positive individual slack cannot hide the shared deficit and expired numbers disappear',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: ItemCard(
              item: f.item,
              onTap: () {},
              riskFooter: RiskBadge(
                risk: f.c.riskFor(f.item),
                onTap: () => showRiskDetails(
                  tester.element(find.byType(ItemCard)),
                  f.c,
                  f.item,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('同期任务至少还缺 1小时'), findsOneWidget);
      expect(find.textContaining('单项余量 1小时30分钟'), findsNothing);
      await tester.tap(find.byType(RiskBadge));
      await tester.pumpAndSettle();
      await tester.tap(find.text('时间计算'));
      await tester.pumpAndSettle();
      expect(find.text('单看每项任务，时间可能够用；放在一起时，它们会争用同一段空闲时间。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'risk-details');
      f.c.analysis!['valid_until'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
      f.c.changed();
      await tester.pumpAndSettle();
      expect(find.text('分析已过期、安排已变化或尚未计算。请刷新后查看本次结果。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'learning time is only written after the before-after confirmation',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      await route(tester, AvailabilityPage(controller: f.c));
      await tester.tap(find.text('快速设置：每天19:00—21:00'));
      await tester.pumpAndSettle();
      await capture(tester, 'learning-time');
      await tester.scrollUntilVisible(
        find.text('核对并保存学习时间'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('核对并保存学习时间'));
      await tester.pumpAndSettle();
      await ioTap(tester, find.text('核对并保存学习时间'));
      expect(f.previews, 1);
      expect(f.puts, 0);
      expect(find.text('原设置'), findsOneWidget);
      await ioTap(tester, find.text('确认保存学习时间'));
      expect(f.puts, 1);
      expect(find.text('打开页面'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'progress history failure can retry in place without leaving a loading state',
    (tester) async {
      final f = PlanningFixture();
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var reads = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/progress') && r.method == 'GET') {
          reads++;
          if (reads == 1) return body({'detail': '进度记录暂时无法读取'}, 503);
          return body([
            {
              'remaining_minutes': 120,
              'before_remaining_minutes': 150,
              'actual_minutes': 30,
              'created_at': '2026-10-03T18:00:00+08:00',
            },
          ]);
        }
        return previous.respond(r);
      });
      await bind(tester, f);
      await route(tester, ProgressPage(controller: f.c, item: f.item));
      await tester.scrollUntilVisible(
        find.text('查看进度记录'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('查看进度记录'));
      expect(
        find.byKey(const ValueKey('progress-history-error')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('progress-history-loading')),
        findsNothing,
      );
      final retry = find.text('重试');
      await Scrollable.ensureVisible(tester.element(retry), alignment: .3);
      await tester.pumpAndSettle();
      expect(retry.hitTestable(), findsOneWidget);
      await capture(tester, 'progress-history-retry');
      await ioTap(tester, retry.hitTestable());
      expect(reads, 2);
      expect(find.text('2小时30分钟 → 2小时'), findsOneWidget);
      expect(find.text('本次用时 30分钟'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('progress-history-error')),
        findsNothing,
      );
      expect(f.progressSaves, 0);
      expect(tester.takeException(), isNull);
      await capture(tester, 'progress-history-recovered');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'remaining zero requires completion preview, actual time is a separate value',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      await route(tester, ProgressPage(controller: f.c, item: f.item));
      await tester.enterText(find.byKey(const Key('progress-remaining')), '0');
      await tester.enterText(find.byKey(const Key('progress-actual')), '60');
      await tester.scrollUntilVisible(
        find.text('确认本次进度'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('确认本次进度'));
      expect(f.progressSaves, 0);
      expect(find.text('确认任务已经完成'), findsOneWidget);
      await capture(tester, 'progress-preview');
      await ioTap(tester, find.text('确认完成并停止提醒'));
      expect(f.lastProgress!['remaining_minutes'], 0);
      expect(f.lastProgress!['actual_minutes'], 60);
      expect(f.lastProgress!['confirm_complete'], true);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'large text risk overview is scrollable and start policy is explicitly selectable',
    (tester) async {
      final f = PlanningFixture();
      await bind(tester, f);
      await mount(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ItemsView(controller: f.c, onCreate: () {}, onOpen: (_) {}),
            ],
          ),
        ),
        width: 360,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'risk-large-text');
      await mount(tester, const SizedBox());
      await route(
        tester,
        ItemFormPage(
          controller: f.c,
          semester: const {'id': 's', 'total_weeks': 20},
          candidate: {
            'item': {'kind': 'task', 'title': '最早开始确认样例'},
          },
        ),
      );
      await tester.scrollUntilVisible(
        find.text('安排学习时间'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('安排学习时间'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('task-start-policy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('task-start-policy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从现在起可开始').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('保存'));
      expect(f.lastItem!['start_policy'], 'now');
      expect(f.lastItem!['earliest_start_at'], isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
