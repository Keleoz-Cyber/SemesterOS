import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/centers/hub_data.dart';
import 'package:semester_os/features/centers/semester_horizon.dart';
import 'package:semester_os/features/centers/semester_timeline.dart';

import 'api_session_test.dart' show ControlledTransport, body;
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'ui_polish_test.dart' show mount;

const staleMessage = '安排已更新或分析过期，时间余量待更新。';

void main() {
  testWidgets('semester horizon stays anchored when stale data becomes fresh', (
    tester,
  ) async {
    final f = await fixture(tester);
    final data = hub(f);
    var fresh = false, fail = false;
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/hub')) {
        if (fail) throw StateError('synthetic refresh failure');
        return body({
          ...data,
          'valid_until': DateTime.now()
              .add(Duration(minutes: fresh ? 2 : -2))
              .toIso8601String(),
        });
      }
      return previous.respond(request);
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
    expect(find.text(staleMessage), findsOneWidget);
    final before = tester.getRect(find.byType(SemesterHorizon));
    fresh = true;
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pump();
    final refreshing = tester.getRect(find.byType(SemesterHorizon));
    expect(refreshing.top, closeTo(before.top, .01));
    expect(refreshing.height, closeTo(before.height, .01));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.getRect(find.byType(SemesterHorizon)).top,
      closeTo(before.top, .01),
    );
    await tester.pumpAndSettle();
    expect(find.text(staleMessage), findsNothing);
    expect(
      tester.getRect(find.byType(SemesterHorizon)).top,
      closeTo(before.top, .01),
    );
    fail = true;
    await tester.runAsync(() => key.currentState!.reload());
    await tester.pumpAndSettle();
    expect(find.textContaining('更新失败，保留上次记录。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      tester.getRect(find.byType(SemesterHorizon)).top,
      closeTo(before.top, .01),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets('fresh hub data retains the outgoing status while it collapses', (
    tester,
  ) async {
    final f = await fixture(tester);
    final data = hub(f);
    var fresh = false;
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/hub')) {
        return body({
          ...data,
          'valid_until': DateTime.now()
              .add(Duration(minutes: fresh ? 2 : -2))
              .toIso8601String(),
        });
      }
      return previous.respond(request);
    });
    final key = GlobalKey<HubDataState>();
    final freshness = <bool>[];
    const contentKey = Key('hub-status-test-content');
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: HubData(
            key: key,
            controller: f.c,
            path: '/semesters/s/hub',
            builder: (_, value, currentFresh, reload) {
              freshness.add(currentFresh);
              return const SizedBox(
                key: contentKey,
                height: 80,
                child: Text('当前内容'),
              );
            },
          ),
        ),
      ),
    );
    await settleIo(tester);
    final initial = tester.getRect(find.byKey(contentKey)).top;
    expect(initial, greaterThan(0));
    fresh = true;
    await tester.runAsync(() => key.currentState!.load());
    await tester.pump();
    expect(freshness.last, isTrue);
    expect(find.text(staleMessage), findsOneWidget);
    final start = tester.getRect(find.byKey(contentKey)).top;
    expect(start, closeTo(initial, .01));
    await tester.pump(const Duration(milliseconds: 100));
    final during = tester.getRect(find.byKey(contentKey)).top;
    expect(find.text(staleMessage), findsOneWidget);
    expect(during, greaterThan(0));
    expect(during, lessThan(start));
    await tester.pumpAndSettle();
    expect(find.text(staleMessage), findsNothing);
    expect(tester.getRect(find.byKey(contentKey)).top, closeTo(0, .01));
    expect(freshness.last, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets('failed hub refresh keeps the records and actionable error', (
    tester,
  ) async {
    final f = await fixture(tester);
    final data = hub(f);
    var fail = false;
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((request) async {
      if (request.path.endsWith('/hub')) {
        if (fail) throw StateError('synthetic refresh failure');
        return body(data);
      }
      return previous.respond(request);
    });
    final key = GlobalKey<HubDataState>();
    var fresh = false;
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: HubData(
            key: key,
            controller: f.c,
            path: '/semesters/s/hub',
            builder: (_, value, currentFresh, reload) {
              fresh = currentFresh;
              return const Text('已有记录');
            },
          ),
        ),
      ),
    );
    await settleIo(tester);
    expect(fresh, isTrue);
    fail = true;
    await tester.runAsync(() => key.currentState!.load());
    await tester.pumpAndSettle();
    expect(fresh, isFalse);
    expect(find.text('已有记录'), findsOneWidget);
    expect(find.textContaining('更新失败，保留上次记录。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(key.currentState!.data, isNotNull);
    expect(key.currentState!.error, isNotNull);
    expect(key.currentState!.busy, isFalse);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('更新失败，保留上次记录。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
}
