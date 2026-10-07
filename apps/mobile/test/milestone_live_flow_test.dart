import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/features/items/item_widgets.dart';
import 'package:semester_os/features/items/item_actions.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'centers_flow_test.dart' show settleIo;
import 'planning_flow_test.dart' show ioTap;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets(
    'live task viewport stays lazy and double tap edits instead of opening',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      f.c.items = [
        for (var i = 0; i < 1000; i++)
          {...f.item, 'id': 't$i', 'title': '任务$i'},
      ];
      var opens = 0, edits = 0;
      await mount(
        tester,
        Scaffold(
          body: CustomScrollView(
            slivers: [
              ItemsView(
                controller: f.c,
                sliver: true,
                onCreate: () {},
                onOpen: (_) => opens++,
                onEdit: (_) => edits++,
              ),
            ],
          ),
        ),
        width: 360,
      );
      await settleIo(tester);
      expect(find.byType(ItemCard).evaluate().length, lessThan(25));
      final firstCard = tester.widget<ItemCard>(find.byType(ItemCard).first);
      final target = find.text(firstCard.item['title']);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(opens, 0);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byType(ItemCard).evaluate().length, lessThan(25));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      for (final filter in ['已完成', '已取消']) {
        await ioTap(tester, find.text(filter));
        expect(
          find.text(filter == '已完成' ? '暂无完成记录' : '没有已取消的任务'),
          findsOneWidget,
        );
        expect(find.widgetWithText(AppButton, '新建任务'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'list shortcut keeps locked plan consent and revision in the real lifecycle path',
    (tester) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? submitted;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/lifecycle/preview')) {
          return body({
            'base_revision': 7,
            'affected_blocks': [
              {
                'id': 'b',
                'title': f.item['title'],
                'minutes': 45,
                'locked': true,
                'start_at': f.start.toIso8601String(),
              },
            ],
          });
        }
        if (r.path.endsWith('/lifecycle')) {
          submitted = Map<String, dynamic>.from(r.data);
          f.item = {...f.item, 'version': 2, 'lifecycle': 'completed'};
          return body(f.item);
        }
        return old.respond(r);
      });
      await mount(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => AppButton(
              onPressed: () =>
                  changeItemLifecycle(context, f.c, f.item, 'completed'),
              child: const Text('快捷完成'),
            ),
          ),
        ),
      );
      await ioTap(tester, find.text('快捷完成'));
      await settleIo(tester);
      expect(submitted, isNull);
      final confirm = find.widgetWithText(FButton, '确认');
      expect(tester.widget<FButton>(confirm).onPress, isNull);
      await ioTap(tester, find.text('取消所选固定安排'));
      await ioTap(tester, find.text('确认'));
      await settleIo(tester);
      expect(submitted?['expected_revision'], 7);
      expect(submitted?['expected_version'], 1);
      expect(submitted?['cancel_plan_ids'], ['b']);
      expect(submitted?['confirm_locked_cancellation'], true);
      expect(f.c.items.single['lifecycle'], 'completed');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
