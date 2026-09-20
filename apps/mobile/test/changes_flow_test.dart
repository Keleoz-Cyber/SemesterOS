import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/changes/changes_page.dart';
import 'package:semester_os/features/planning/proposal_page.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show route, ioTap;
import 'ui_polish_test.dart' show capture, loadPreviewFonts, mount;

Map<String, dynamic> change(ScheduleFixture f, {bool conflict = false}) => {
  'id': 'ch',
  'semester_id': 's',
  'base_revision': 1,
  'phase': 'ready',
  'request': {
    'title': '合成概率论',
    'source_text': '老师通知：本次课程移至周四10点。',
    'kind': 'move',
  },
  'patch': {
    'before': [
      {
        'title': '合成概率论',
        'start_at': f.start.toIso8601String(),
        'end_at': f.start.add(const Duration(hours: 1)).toIso8601String(),
      },
    ],
    'after': [
      {
        'title': '合成概率论',
        'start_at': f.start.add(const Duration(hours: 2)).toIso8601String(),
        'end_at': f.start.add(const Duration(hours: 3)).toIso8601String(),
      },
    ],
  },
  'impact': {
    'after_summary': {'fixed_conflict_count': conflict ? 1 : 0},
    'affected_blocks': [],
    'risk_changes': [
      {'title': '合成报告', 'before_slack': 300, 'after_slack': 180},
    ],
    'fixed_conflicts': conflict
        ? [
            {
              'titles': ['合成概率论', '合成考试'],
              'start_at': f.start.toIso8601String(),
              'end_at': f.start
                  .add(const Duration(minutes: 30))
                  .toIso8601String(),
            },
          ]
        : [],
  },
};

void main() {
  setUpAll(loadPreviewFonts);
  testWidgets(
    'fixed conflicts show the actual arrangements before confirmation',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await route(
        tester,
        ChangePreviewPage(controller: f.c, preview: change(f, conflict: true)),
      );
      await tester.scrollUntilVisible(
        find.text('我已核实通知，确认保存并保留时间冲突提示'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('合成考试'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('确认现实变化，暂不移动个人计划'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '确认现实变化，暂不移动个人计划'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'reality apply and personal replan are two separate confirmations',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var changesApplied = 0, replans = 0, calendarRefresh = 0;
      f.c.onRealityChanged = (_) async {
        calendarRefresh++;
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/changes/ch/apply')) {
          changesApplied++;
          f.revision++;
          return body({'semester_id': 's', 'revision': f.revision});
        }
        if (r.path.endsWith('/replan-proposals')) {
          replans++;
          final p = f.proposal();
          return body({
            ...p,
            'base_revision': f.revision,
            'mode': 'replan',
            'tasks': [],
            'moved_tasks': 1,
            'moved_blocks': 3,
            'shift_minutes': 180,
            'messages': ['重排范围为本学期全部已有的未来个人计划。'],
            'request': {'mode': 'replan', 'lead_minutes': 5},
            'blocks': [
              for (final b in p['blocks'])
                {
                  ...b,
                  'id': 'b',
                  'before_start_at': DateTime.parse(
                    b['start_at'],
                  ).subtract(const Duration(hours: 1)).toIso8601String(),
                  'before_end_at': DateTime.parse(
                    b['end_at'],
                  ).subtract(const Duration(hours: 1)).toIso8601String(),
                },
            ],
          });
        }
        return previous.respond(r);
      });
      await route(
        tester,
        ChangePreviewPage(controller: f.c, preview: change(f)),
      );
      await capture(tester, 'change-preview');
      expect(changesApplied, 0);
      expect(replans, 0);
      expect(f.applied, 0);
      await tester.scrollUntilVisible(
        find.text('确认现实变化，暂不移动个人计划'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('确认现实变化，暂不移动个人计划'));
      expect(changesApplied, 1);
      expect(calendarRefresh, 1);
      expect(replans, 0);
      expect(f.applied, 0);
      await ioTap(tester, find.text('查看个人计划调整方案'));
      expect(replans, 1);
      expect(f.applied, 0);
      expect(find.byType(ProposalPage), findsOneWidget);
      await capture(tester, 'replan-preview');
      await tester.scrollUntilVisible(
        find.text('确认调整计划'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await ioTap(tester, find.text('确认调整计划'));
      expect(f.applied, 1);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets('newer revision disables reality confirmation at large text', (
    tester,
  ) async {
    final f = ScheduleFixture();
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      ChangePreviewPage(controller: f.c, preview: change(f)),
      width: 360,
      textScale: 2,
    );
    f.c.observeRevision('s', 2);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('确认现实变化，暂不移动个人计划'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, '确认现实变化，暂不移动个人计划'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await capture(tester, 'change-large-text');
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
