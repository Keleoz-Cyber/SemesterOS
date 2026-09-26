import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:semester_os/features/insights/insights_page.dart';
import 'package:semester_os/features/insights/insights_controller.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Map<String, dynamic> insightData(String from, String to, {String? category}) =>
    {
      'semester_id': 's',
      'revision': 1,
      'from_date': from,
      'to_date': to,
      'generated_at': '2026-09-27T00:00:00Z',
      'filters': {'category_id': category, 'tag_ids': []},
      'summary': {
        'entry_count': 2,
        'fixed_scheduled_minutes': 180,
        'personal_planned_minutes': 60,
        'occupied_union_minutes': 210,
        'actual_minutes': null,
        'unknown_duration_count': 0,
        'undated_count': 0,
      },
      'daily': [
        for (var i = 0; i < 7; i++)
          {
            'date': DateTime.parse(
              from,
            ).add(Duration(days: i)).toIso8601String().substring(0, 10),
            'fixed_scheduled_minutes': i == 0 ? 180 : 0,
            'personal_planned_minutes': i == 0 ? 60 : 0,
            'occupied_union_minutes': i == 0 ? 210 : 0,
            'actual_minutes': null,
          },
      ],
      'categories': [
        {
          'id': 'study',
          'name': '学业',
          'scheduled_minutes': 180,
          'actual_minutes': null,
          'entry_count': 1,
        },
        {
          'id': 'research',
          'name': '科研',
          'scheduled_minutes': 60,
          'actual_minutes': null,
          'entry_count': 1,
        },
      ],
      'tags': [
        {'id': 'tag', 'name': '组会'},
      ],
      'records': [
        if (category == null || category == 'study')
          {
            'id': 'course:c',
            'resource_id': 'c',
            'resource_type': 'course',
            'title': '概率论',
            'date': from,
            'scheduled_minutes': 180,
            'actual_minutes': null,
            'category_id': 'study',
            'tags': [],
          },
        if (category == null || category == 'research')
          {
            'id': 'event:e',
            'resource_id': 'e',
            'resource_type': 'event',
            'title': '课题组组会',
            'date': from,
            'scheduled_minutes': 60,
            'actual_minutes': null,
            'category_id': 'research',
            'tags': [
              {'id': 'tag', 'name': '组会'},
            ],
          },
      ],
      'undated': [],
      'definitions': {'actual': '按进度记录的创建日期统计，未记录不计为0。'},
      'limitations': [],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  test(
    'late filter results are ignored and failed new scope cannot display old totals',
    () async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final slow = Completer<dynamic>();
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/insights?')) {
          final q = Uri.parse(r.path).queryParameters;
          if (q['category_id'] == 'study') return await slow.future;
          if (q['category_id'] == 'life') {
            return body({'message': '暂时无法读取'}, 503);
          }
          return body(
            insightData(
              q['from_date']!,
              q['to_date']!,
              category: q['category_id'],
            ),
          );
        }
        return old.respond(r);
      });
      await f.c.bind('s');
      final c = InsightsController(
        f.c,
        's',
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 27),
      );
      try {
        await c.load();
        final pending = c.filterCategory('study');
        expect(c.matchesCurrentQuery, isFalse);
        expect(c.busy, isTrue);
        await c.filterCategory('research');
        slow.complete(
          body(insightData('2026-09-21', '2026-09-27', category: 'study')),
        );
        await pending;
        expect(c.data?['filters']['category_id'], 'research');
        await c.filterCategory('life');
        expect(c.data, isNull);
        expect(c.offline, isTrue);
      } finally {
        c.dispose();
        f.c.dispose();
      }
    },
  );
  testWidgets(
    'statistics uses real chart widgets and category filter updates source records',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      final queries = <Uri>[];
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.contains('/insights?')) {
          final uri = Uri.parse(r.path);
          queries.add(uri);
          return body(
            insightData(
              uri.queryParameters['from_date']!,
              uri.queryParameters['to_date']!,
              category: uri.queryParameters['category_id'],
            ),
          );
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        InsightsPage(
          controller: f.c,
          initialQuery: const {'from': '2026-10-05', 'to': '2026-10-11'},
          semester: {
            'id': 's',
            'name': '测试学期',
            'first_monday': '2026-08-31',
            'total_weeks': 20,
          },
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('未记录'), findsWidgets);
      expect(queries.first.queryParameters['from_date'], '2026-10-05');
      expect(queries.first.queryParameters['to_date'], '2026-10-11');
      expect(find.byType(BarChart), findsOneWidget);
      await capture(tester, 'insights-overview');
      await tester.ensureVisible(find.byType(PieChart));
      await tester.pumpAndSettle();
      expect(find.byType(PieChart), findsOneWidget);
      await capture(tester, 'insights-distribution');
      await tester.ensureVisible(
        find.byKey(const ValueKey('category-research')),
      );
      await ioTap(tester, find.byKey(const ValueKey('category-research')));
      expect(queries.last.queryParameters['category_id'], 'research');
      await tester.ensureVisible(find.text('课题组组会'));
      await tester.pumpAndSettle();
      expect(find.text('概率论'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
