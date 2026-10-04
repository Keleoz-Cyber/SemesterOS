import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/features/centers/semester_centers.dart';

import 'api_session_test.dart' show ControlledTransport, body;
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'hidden semester updates keep new records readable without a layout error',
    (tester) async {
      final f = await fixture(tester);
      final data = hub(f);
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/hub')) return body(data);
        return old.respond(request);
      });
      var visible = true;
      late StateSetter update;
      final key = GlobalKey<SemesterHomeState>();
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return TickerMode(
              enabled: visible,
              child: Scaffold(
                body: SingleChildScrollView(
                  child: SemesterHome(
                    key: key,
                    controller: f.c,
                    onManage: () {},
                  ),
                ),
              ),
            );
          },
        ),
      );
      await settleIo(tester);
      update(() => visible = false);
      await tester.pump();
      data['revision'] = 2;
      (data['weeks'] as List).single['items'].add({
        ...f.item,
        'id': 'new-while-hidden',
        'title': '后台新增的课程报告',
        'time': {'precision': 'week', 'week': 14},
      });
      await tester.runAsync(() => key.currentState!.reload());
      await tester.pump();
      expect(tester.takeException(), isNull);
      update(() => visible = true);
      await settleIo(tester);
      expect(find.text('后台新增的课程报告'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  for (final size in [
    (name: 'normal', width: 390.0, height: 844.0, scale: 1.0),
    (name: 'small', width: 320.0, height: 740.0, scale: 1.0),
    (name: 'large-text', width: 390.0, height: 844.0, scale: 1.8),
    (name: 'landscape', width: 844.0, height: 390.0, scale: 1.0),
  ]) {
    testWidgets('semester week selection stays coherent at ${size.name}', (
      tester,
    ) async {
      final f = await fixture(tester);
      final data = hub(f);
      final now = schoolNow();
      final day = DateTime(now.year, now.month, now.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      final first = monday.subtract(const Duration(days: 21));
      String date(DateTime value) => value.toIso8601String().substring(0, 10);
      data['semester'] = {
        ...data['semester'],
        'name': '2026—2027学年第一学期',
        'first_monday': date(first),
      };
      data['weeks'] = [
        for (var w = 1; w <= 20; w++)
          {
            'week': w,
            'start_date': date(first.add(Duration(days: (w - 1) * 7))),
            'end_date': date(first.add(Duration(days: (w - 1) * 7 + 6))),
            'changes': [],
            'items': [
              {
                ...f.item,
                'id': 'semester-motion-$w',
                'title': '第$w周课程报告',
                'time': {'precision': 'week', 'week': w},
              },
              if (w == 4)
                {
                  ...f.item,
                  'id': 'semester-motion-long',
                  'title': '实验资料核对与小组汇报',
                  'time': {'precision': 'date', 'date': date(monday)},
                },
            ],
          },
      ];
      Completer<void>? gate;
      var reads = 0, writes = 0;
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.method != 'GET') writes++;
        if (request.path.endsWith('/hub')) return body(data);
        if (request.path.contains('/calendar?')) {
          reads++;
          if (gate != null) await gate!.future;
          return body({
            'semester_id': 's',
            'revision': 1,
            'entries': [],
            'undated': [],
          });
        }
        return old.respond(request);
      });
      final key = GlobalKey<SemesterHomeState>();
      final vertical = ScrollController();
      late StateSetter update;
      var reduced = false, offstage = false;
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: TickerMode(
                enabled: !offstage,
                child: Scaffold(
                  body: SingleChildScrollView(
                    controller: vertical,
                    padding: const EdgeInsets.all(20),
                    child: SemesterHome(
                      key: key,
                      controller: f.c,
                      onManage: () {},
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        width: size.width,
        height: size.height,
        textScale: size.scale,
      );
      await settleIo(tester);
      final week4 = find.byKey(const ValueKey('semester-week-4'));
      final week5 = find.byKey(const ValueKey('semester-week-5'));
      final week6 = find.byKey(const ValueKey('semester-week-6'));
      await tester.ensureVisible(week4);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(week4).properties.selected, isTrue);
      expect(tester.getSize(week4).shortestSide, greaterThanOrEqualTo(48));
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      );
      final scroll = tester
          .widget<SingleChildScrollView>(horizontal)
          .controller!;
      final horizontalBefore = scroll.offset;
      await capture(tester, 'semester-${size.name}-idle');

      if (size.name != 'normal') {
        await tester.tap(week5);
        await settleIo(tester);
        expect(tester.widget<Semantics>(week5).properties.selected, isTrue);
        expect(find.text('第5周课程报告'), findsOneWidget);
        await capture(tester, 'semester-${size.name}-selected');
        expect(writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        vertical.dispose();
        f.c.dispose();
        return;
      }

      await tester.tap(week5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('第4周课程报告').hitTestable(), findsNothing);
      expect(find.text('第5周课程报告').hitTestable(), findsOneWidget);
      if (size.name == 'normal') {
        await capture(tester, 'semester-normal-switch-60ms');
      }
      await tester.tap(week6);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Semantics>(week6).properties.selected, isTrue);
      expect(find.text('第5周课程报告').hitTestable(), findsNothing);
      expect(find.text('第6周课程报告').hitTestable(), findsOneWidget);
      expect(scroll.offset, horizontalBefore);
      update(() => reduced = true);
      await tester.pump();
      expect(find.text('第4周课程报告'), findsNothing);
      expect(find.text('第5周课程报告'), findsNothing);
      expect(find.text('第6周课程报告'), findsOneWidget);
      final indicator = tester.getRect(
        find.byKey(const Key('semester-week-indicator')),
      );
      expect(
        indicator.center.dx,
        closeTo(tester.getRect(week6).center.dx, .01),
      );
      await settleIo(tester);
      await capture(tester, 'semester-${size.name}-selected');

      update(() => reduced = false);
      await tester.pump();
      await tester.tap(week5);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      update(() => offstage = true);
      await tester.pump();
      expect(find.text('第6周课程报告'), findsNothing);
      expect(find.text('第5周课程报告'), findsOneWidget);
      update(() => offstage = false);
      await tester.pump();
      await tester.tap(week6);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('第5周课程报告'), findsNothing);
      expect(find.text('第6周课程报告'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleIo(tester);

      final y = tester.getTopLeft(find.text('第6周课程报告')).dy;
      final verticalBefore = vertical.offset;
      final readsBefore = reads;
      await tester.runAsync(() async {
        gate = Completer<void>();
        final refresh = key.currentState!.reload();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await tester.pump();
        expect(find.text('第6周课程报告'), findsOneWidget);
        expect(tester.getTopLeft(find.text('第6周课程报告')).dy, y);
        gate!.complete();
        await refresh;
      });
      await tester.pumpAndSettle();
      expect(reads, readsBefore + 1);
      expect(scroll.offset, horizontalBefore);
      expect(vertical.offset, verticalBefore);
      expect(tester.getTopLeft(find.text('第6周课程报告')).dy, y);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      vertical.dispose();
      f.c.dispose();
    });
  }
}
