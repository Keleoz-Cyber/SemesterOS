import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/insights/insights_page.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount, loadPreviewFonts, capture;
import 'insights_flow_test.dart' show insightData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  testWidgets(
    'filter sheet cancels drafts and applies category and tags together',
    (tester) async {
      final fixture = ScheduleFixture();
      final previous = fixture.api.dio.httpClientAdapter as ControlledTransport;
      final queries = <Uri>[];
      fixture.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.contains('/insights?')) {
          final uri = Uri.parse(request.path);
          queries.add(uri);
          return body(
            insightData(
              uri.queryParameters['from_date']!,
              uri.queryParameters['to_date']!,
              category: uri.queryParameters['category_id'],
            ),
          );
        }
        return previous.respond(request);
      });
      await tester.runAsync(() => fixture.c.bind('s'));
      await mount(
        tester,
        InsightsPage(
          controller: fixture.c,
          semester: const {
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
      expect(find.byKey(const ValueKey('category-research')), findsNothing);
      expect(find.text('标签筛选'), findsNothing);
      final reads = queries.length;
      await ioTap(tester, find.byKey(const ValueKey('insights-filters')));
      await ioTap(tester, find.byKey(const ValueKey('category-research')));
      await capture(tester, 'statistics-filter-sheet');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(queries.length, reads);

      await ioTap(tester, find.byKey(const ValueKey('insights-filters')));
      expect(
        tester
            .widget<AppTile>(find.byKey(const ValueKey('category-all')))
            .selected,
        isTrue,
      );
      await ioTap(tester, find.byKey(const ValueKey('category-research')));
      await tester.scrollUntilVisible(
        find.widgetWithText(AppFilterChip, '组会'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await ioTap(tester, find.widgetWithText(AppFilterChip, '组会'));
      await ioTap(tester, find.text('应用筛选'));
      expect(queries.length, reads + 1);
      expect(queries.last.queryParameters['category_id'], 'research');
      expect(queries.last.queryParameters['tag_ids'], 'tag');
      expect(find.widgetWithText(AppInputChip, '科研'), findsOneWidget);
      expect(find.widgetWithText(AppInputChip, '组会'), findsOneWidget);
      expect(find.byType(AppFilterChip), findsNothing);
      await tester.pumpWidget(const SizedBox());
      fixture.c.dispose();
    },
  );
}
