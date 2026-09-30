import 'dart:async';
import 'package:flutter/material.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'centers_flow_test.dart' show fixture, hub, settleIo;
import 'ui_polish_test.dart' show mount;

void main() {
  testWidgets('timeline orders actual instants and labels tentative records', (
    tester,
  ) async {
    final f = await fixture(tester);
    final data = hub(f);
    data['weeks'][0]['items'] = [
      {
        ...f.item,
        'title': '十点考试',
        'kind': 'exam',
        'certainty': 'tentative',
        'anchor_at': '2026-11-30T02:00:00Z',
        'time': {'precision': 'exact', 'at': '2026-11-30T02:00:00Z'},
      },
    ];
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/hub')) return body(data);
      if (r.path.contains('/calendar?')) {
        return body({
          'semester_id': 's',
          'revision': 1,
          'undated': [],
          'entries': [
            {
              'id': 'event:e',
              'resource_id': 'e',
              'resource_type': 'event',
              'title': '九点活动',
              'certainty': 'tentative',
              'start_at': '2026-11-30T09:00:00+08:00',
            },
          ],
        });
      }
      return old.respond(r);
    });
    await mount(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: SemesterHome(controller: f.c, onManage: () {}),
        ),
      ),
    );
    await settleIo(tester);
    expect(
      tester.getTopLeft(find.text('九点活动')).dy,
      lessThan(tester.getTopLeft(find.text('十点考试')).dy),
    );
    expect(find.textContaining('暂定'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets(
    'forced refresh refetches after an older in-flight calendar response',
    (tester) async {
      final f = await fixture(tester);
      final data = hub(f);
      final gate = Completer<void>();
      var reads = 0;
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/hub')) return body(data);
        if (r.path.contains('/calendar?')) {
          final revision = ++reads == 1 ? 1 : 2;
          if (reads == 1) await gate.future;
          return body({
            'semester_id': 's',
            'revision': revision,
            'undated': [],
            'entries': [
              {
                'id': 'event:e',
                'resource_id': 'e',
                'resource_type': 'event',
                'title': revision == 1 ? '旧活动' : '新活动',
                'start_at': '2026-11-30T09:00:00+08:00',
              },
            ],
          });
        }
        return old.respond(r);
      });
      final key = GlobalKey<SemesterHomeState>();
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SemesterHome(key: key, controller: f.c, onManage: () {}),
            ),
          ),
        ),
      );
      // A running progress indicator needs bounded pumps until the gate is released.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      Future<void>? refresh;
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        data['revision'] = 2;
        data['semester']['revision'] = 2;
        refresh = key.currentState!.reload();
        await Future<void>.delayed(const Duration(milliseconds: 80));
        gate.complete();
      });
      await settleIo(tester);
      await tester.runAsync(() => refresh!.timeout(const Duration(seconds: 2)));
      expect(reads, 2);
      expect(find.text('新活动'), findsOneWidget);
      expect(find.text('旧活动'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
