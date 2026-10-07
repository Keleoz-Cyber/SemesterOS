import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/features/planning/proposal_page.dart';
import 'package:semester_os/ui/motion_task_list.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'controller_test.dart' show MemoryStore;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets('gap selects known work and remains a preview until confirmed', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final original = f.api.dio.httpClientAdapter as ControlledTransport;
    final now = schoolNow();
    final start = DateTime.now().toUtc().add(const Duration(hours: 1));
    final opportunity = {
      'item_id': 't',
      'title': '整理材料',
      'target_minutes': 20,
      'remaining_minutes': 20,
      'already_planned_minutes': 0,
      'start_at': start.toIso8601String(),
      'end_at': start.add(const Duration(minutes: 40)).toIso8601String(),
      'latest_start_at': start
          .add(const Duration(minutes: 20))
          .toIso8601String(),
      'before_kind': 'course',
    };
    f.item = {...f.item, 'title': '整理材料', 'remaining_minutes': 20};
    final p = {
      ...f.proposal(),
      'title': '整理材料',
      'window_start': opportunity['start_at'],
      'window_end': opportunity['end_at'],
      'blocks': [
        {
          'item_id': 't',
          'title': '整理材料',
          'start_at': opportunity['start_at'],
          'end_at': start.add(const Duration(minutes: 20)).toIso8601String(),
          'minutes': 20,
        },
      ],
      'tasks': [
        {
          'item_id': 't',
          'title': '整理材料',
          'target_minutes': 20,
          'new_minutes': 20,
          'existing_minutes': 0,
          'unarranged_minutes': 0,
          'later_minutes': 0,
        },
      ],
    };
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.contains('/day-brief?')) {
        return body({
          'semester_id': 's',
          'revision': f.revision,
          'date':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          'valid_until': '2099-01-01T00:00:00Z',
          'entries': [],
          'next_day': {'entries': []},
          'suggestions': [],
          'study_opportunity': f.applied == 0 ? opportunity : null,
        });
      }
      if (r.path.endsWith('/plan-proposals') && r.method == 'POST') {
        f.generated++;
        expect(r.data['tasks'][0]['target_minutes'], isNull);
        expect(r.data['window_start_at'], opportunity['start_at']);
        return body(p);
      }
      if (r.path.endsWith('/plan-proposals/p/accept')) {
        f.applied++;
        f.revision++;
        f.accepted = {...p, 'phase': 'applied', 'version': 2};
        f.blocks = [
          {
            ...(p['blocks'] as List).single as Map<String, dynamic>,
            'id': 'b',
            'status': 'active',
            'version': 1,
          },
        ];
        return body({
          'proposal_id': 'p',
          'proposal_version': 2,
          'semester_id': 's',
          'revision': f.revision,
          'block_ids': ['b'],
        });
      }
      return original.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    final app = AppController(
      f.api,
      MemoryStore(),
      clearSchoolSession: () async {},
    )..semester = semester();
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: TodayDashboard(
            app: app,
            items: f.c,
            onCalendar: () {},
            now: () => now,
          ),
        ),
      ),
      width: 320,
      textScale: 1.4,
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('study-opportunity')));
    await tester.pumpAndSettle();
    await capture(tester, 'gap-and-task');
    expect(find.text('课前空档'), findsOneWidget);
    expect(f.applied, 0);
    await tester.tap(find.byKey(const Key('opportunity-arrange')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProposalPage), findsOneWidget);
    expect(f.generated, 1);
    expect(f.applied, 0);
    await capture(tester, 'gap-preview');
    await tester.tap(find.text('保存学习安排'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    expect(f.applied, 1);
    expect(f.blocks.single['minutes'], 20);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    app.dispose();
  });
  testWidgets(
    'completion feedback starts only after actual data and retires without actions',
    (tester) async {
      final rows = ValueNotifier<List<Map<String, dynamic>>>([
        {'id': 'a', 'title': '交材料', 'kind': 'task', 'lifecycle': 'active'},
        {'id': 'b', 'title': '读书笔记', 'kind': 'task', 'lifecycle': 'active'},
      ]);
      var attempts = 0;
      final states = <String, String>{};
      await mount(
        tester,
        Scaffold(
          body: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: rows,
            builder: (c, data, _) => MotionTaskList(
              items: data,
              removedStates: states,
              builder: (c, item, index) => ItemCard(
                item: item,
                onTap: () {},
                onComplete: () async {
                  attempts++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('标记完成：交材料'));
      await tester.pumpAndSettle();
      expect(attempts, 1);
      expect(find.text('交材料'), findsOneWidget);
      states['a'] = 'completed';
      rows.value = [rows.value.last];
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('已完成'), findsOneWidget);
      await capture(tester, 'task-completion-in-flight');
      await tester.pumpAndSettle();
      expect(find.text('交材料'), findsNothing);
      expect(find.text('读书笔记'), findsOneWidget);
      states['b'] = 'completed';
      rows.value = [];
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('读书笔记'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('读书笔记'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      rows.dispose();
    },
  );
}
