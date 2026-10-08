import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/calendar/timetable_scale.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/ui/app_selection.dart';
import 'package:semester_os/ui/v2/motion/completion_check.dart';
import 'package:semester_os/ui/v2/motion/spring_segmented.dart';
import 'hold_voice_test.dart' show HoldInput;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'centers_flow_test.dart' show settleIo;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  for (final (width, textScale) in [(390.0, 1.0), (360.0, 1.6)]) {
    testWidgets('task status tabs stay in place without resetting at $width', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        Scaffold(
          body: CustomScrollView(
            slivers: [
              ItemsView(
                controller: f.c,
                sliver: true,
                onCreate: () {},
                onCapture: () {},
                onOpen: (_) {},
              ),
            ],
          ),
        ),
        width: width,
        textScale: textScale,
      );
      await settleIo(tester);
      final tabs = find.byType(AppSegmentedControl<String>);
      final spring = find.byType(SpringSegmented<String>);
      final initialRect = tester.getRect(tabs);
      final springState = tester.state(spring);
      expect(find.text('安排任务'), findsOneWidget);
      expect(find.text('整理通知'), findsOneWidget);
      await capture(tester, 'task-tabs-active-${width.toInt()}');
      for (final label in ['已完成', '已取消', '待处理']) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(tester.getRect(tabs), initialRect);
        expect(tester.state(spring), same(springState));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getRect(tabs), initialRect);
        expect(tester.state(spring), same(springState));
      }
      await tester.pumpAndSettle();
      expect(find.text('安排任务'), findsOneWidget);
      expect(find.text('整理通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }

  test('known course outside local bell times keeps real drawing space', () {
    final scale = TimetableScale.build(
      480,
      1190,
      const [
        {'start': '08:00', 'end': '08:50'},
        {'start': '19:00', 'end': '19:50'},
      ],
      1.5,
      1,
      [(start: 610, end: 720)],
    );
    expect(scale.at(720) - scale.at(610), greaterThanOrEqualTo(44));
    expect(scale.at(665), (scale.at(610) + scale.at(720)) / 2);
    expect(scale.at(1140) - scale.at(720), lessThanOrEqualTo(18));
  });
  testWidgets(
    'seven day choices keep 48dp targets and selected day is reachable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 272,
              child: AppSegmentedControl<int>(
                value: 7,
                options: {
                  for (var i = 1; i <= 7; i++) i: '周${'一二三四五六日'[i - 1]}',
                },
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('周日').hitTestable(), findsOneWidget);
      for (var i = 1; i <= 7; i++) {
        final cell = find.ancestor(
          of: find.text('周${'一二三四五六日'[i - 1]}'),
          matching: find.byType(InkWell),
        );
        expect(tester.getSize(cell).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(cell).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'changing recording scope cancels previous recording before handoff',
    (tester) async {
      final oldInput = HoldInput(), newInput = HoldInput();
      var scope = 'a';
      late StateSetter update;
      var captured = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: HoldVoiceButton(
                  key: ValueKey(scope),
                  compact: true,
                  input: scope == 'a' ? oldInput : newInput,
                  onRecorded: (_) async {
                    captured++;
                  },
                  onError: (_) {},
                ),
              );
            },
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldVoiceButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(oldInput.starts, 1);
      update(() => scope = 'b');
      await tester.pump();
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(captured, 0);
      expect(oldInput.stops, 1);
      expect(oldInput.releases, 1);
      expect(newInput.starts, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changing reduced motion finishes an in-flight strike immediately',
    (tester) async {
      var done = false, reduce = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: const MediaQueryData().copyWith(
                  disableAnimations: reduce,
                ),
                child: Scaffold(
                  body: StrikeThroughText('服务端已确认的任务', struck: done),
                ),
              );
            },
          ),
        ),
      );
      update(() => done = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      update(() => reduce = true);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
