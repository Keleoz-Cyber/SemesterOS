import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/tags/tag_management_page.dart';
import 'package:semester_os/features/tags/tag_records_page.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'schedule_flow_test.dart' show ScheduleFixture;

const term = {'id': 's', 'name': '秋季学期', 'revision': 1, 'total_weeks': 20};
const tag = {'id': 'meeting', 'name': '会议'};
Map<String, dynamic> page(
  List<Map<String, dynamic>> records, {
  bool more = false,
}) => {
  'owner_id': 'preview',
  'tag': tag,
  'records': records,
  'semesters': [term],
  'total': 2,
  'has_more': more,
};
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'tap tag opens real tasks and events, and a task opens its detail',
    (tester) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.item['tags'] = [tag];
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/tags/organize')) {
          return body({'owner_id': 'preview', 'merged': 0, 'renamed': 0});
        }
        if (r.path.endsWith('/tags')) {
          return body({
            'owner_id': 'preview',
            'tags': [tag],
          });
        }
        if (r.path.endsWith('/tags/meeting/records')) {
          return body(
            page([
              {...f.item, 'resource_type': 'item'},
              {
                'id': 'event',
                'title': '部门会议',
                'resource_type': 'event',
                'semester_id': 's',
                'time': {'precision': 'unknown'},
                'lifecycle': 'cancelled',
              },
            ]),
          );
        }
        if (r.path.endsWith('/items/t')) return body(f.item);
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: TagManagementPage(controller: f.c),
        ),
      );
      await settleIo(tester);
      await tester.tap(find.byKey(const ValueKey('open-tag-meeting')));
      await settleIo(tester);
      expect(find.byType(TagRecordsPage), findsOneWidget);
      expect(find.text('合成报告'), findsOneWidget);
      expect(find.text('部门会议'), findsOneWidget);
      expect(find.textContaining('已取消'), findsOneWidget);
      await tester.tap(find.text('合成报告'));
      await settleIo(tester);
      expect(find.byType(ItemDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  test(
    'pagination retries do not duplicate records and account changes discard late data',
    () async {
      final f = ScheduleFixture();
      await f.c.bind('s');
      final pending = Completer<void>();
      var calls = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        calls++;
        if (calls == 1) {
          return body(
            page([
              {'id': 'a'},
            ], more: true),
          );
        }
        if (calls == 2) return body({'message': '暂时断网'}, 503);
        if (calls == 3) {
          expect(r.queryParameters['offset'], 1);
          return body(
            page([
              {'id': 'b'},
            ]),
          );
        }
        await pending.future;
        return body(
          page([
            {'id': 'wrong-account'},
          ]),
        );
      });
      final c = TagRecordsController(f.c, 'meeting');
      await c.load();
      await c.load(next: true);
      expect(c.error, isNotNull);
      expect(c.records.length, 1);
      await c.load(next: true);
      expect(c.records.map((r) => r['id']), ['a', 'b']);
      final request = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      f.api.session = account('other');
      f.c.changed();
      pending.complete();
      await request;
      expect(c.active, isFalse);
      expect(c.records, isEmpty);
      c.dispose();
      f.c.dispose();
    },
  );

  testWidgets('a record from another semester opens in its own editing scope', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    final other = {
      ...f.item,
      'id': 'older',
      'semester_id': 'old',
      'title': '上学期会议记录',
    };
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/tags/meeting/records')) {
        return body({
          ...page([
            {...other, 'resource_type': 'item'},
          ]),
          'total': 1,
          'semesters': [
            {...term, 'id': 'old', 'name': '春季学期'},
          ],
        });
      }
      if (r.path.endsWith('/semesters/old/items')) {
        return body({
          'revision': 1,
          'items': [other],
        });
      }
      if (r.path.endsWith('/items/older')) return body(other);
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => ShiriForuiTheme(child: child!),
        home: TagRecordsPage(controller: f.c, tag: tag),
      ),
    );
    await settleIo(tester);
    expect(find.textContaining('春季学期'), findsOneWidget);
    await tester.tap(find.text('上学期会议记录'));
    await settleIo(tester);
    final detail = tester.widget<ItemDetailPage>(find.byType(ItemDetailPage));
    expect(detail.controller.semesterId, 'old');
    expect(detail.semester['id'], 'old');
    expect(f.c.semesterId, 's');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
