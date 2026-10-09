import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'package:semester_os/ui/v2/shiri_theme.dart';
import 'package:semester_os/ui/v2/shiri_tokens.dart';
import 'package:semester_os/ui/v2/widgets/glass_dock.dart';

import 'hold_voice_test.dart' show HoldInput;

const _microphoneKey = Key('pill-test-microphone');

AnimationController _geometryAnimation(WidgetTester tester, Finder component) {
  final builder = tester.widget<AnimatedBuilder>(
    find.descendant(of: component, matching: find.byType(AnimatedBuilder)),
  );
  return builder.animation as AnimationController;
}

class _PillHarness extends StatefulWidget {
  const _PillHarness({super.key, this.microphone, this.width = 336});

  final Widget? microphone;
  final double width;

  @override
  State<_PillHarness> createState() => _PillHarnessState();
}

class _PillHarnessState extends State<_PillHarness> {
  final theme = shiriLightTheme();
  bool collapsed = false, reduced = false, tickers = true;
  var opens = 0, images = 0;

  void collapse(bool value) => setState(() => collapsed = value);
  void reduce() => setState(() => reduced = true);
  void pauseTickers() => setState(() => tickers = false);
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: theme,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: widget.width,
          child: MediaQuery(
            data: const MediaQueryData().copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(1.6),
            ),
            child: TickerMode(
              enabled: tickers,
              child: AssistantPill(
                collapsed: collapsed,
                lowEnd: true,
                onOpen: () => opens++,
                onImage: () => images++,
                microphone:
                    widget.microphone ??
                    const SizedBox.square(
                      key: _microphoneKey,
                      dimension: 48,
                      child: Icon(Icons.mic_rounded),
                    ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _DockHarness extends StatefulWidget {
  const _DockHarness({super.key});

  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  final theme = shiriLightTheme();
  var index = 0;
  Widget? reference;

  Widget dock(Key key) => GlassDock(
    key: key,
    index: index,
    lowEnd: true,
    onSelect: (_) {},
    items: const [
      GlassDockItem(
        icon: Icon(Icons.today_outlined),
        selectedIcon: Icon(Icons.today),
        label: '今日',
      ),
      GlassDockItem(
        icon: Icon(Icons.calendar_view_week_outlined),
        selectedIcon: Icon(Icons.calendar_view_week),
        label: '日程',
      ),
    ],
  );

  void select(int value) => setState(() {
    index = value;
    reference = dock(const Key('dock-reference'));
  });

  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    reference ??= dock(const Key('dock-reference'));
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: Row(
            children: [
              Expanded(child: dock(const Key('dock-refreshed'))),
              Expanded(child: reference!),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'dock parent refresh does not restart a spring at the same target',
    (tester) async {
      final key = GlobalKey<_DockHarnessState>();
      await tester.pumpWidget(_DockHarness(key: key));
      double position(String name) {
        final dock = find.byKey(Key(name));
        final indicator = find.descendant(
          of: dock,
          matching: find.byType(Positioned),
        );
        return tester.getTopLeft(indicator).dx - tester.getTopLeft(dock).dx;
      }

      key.currentState!.select(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(position('dock-refreshed'), position('dock-reference'));
      key.currentState!.refresh();
      await tester.pump();
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          position('dock-refreshed'),
          closeTo(position('dock-reference'), .01),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [336.0, 366.0]) {
    testWidgets('pill microphone is anchored through every frame at $width', (
      tester,
    ) async {
      final key = GlobalKey<_PillHarnessState>();
      await tester.pumpWidget(_PillHarness(key: key, width: width));
      final mic = find.byKey(_microphoneKey);
      final initial = tester.getRect(mic);
      expect(initial.size, const Size(48, 48));
      key.currentState!.collapse(true);
      await tester.pump();
      for (final elapsed in [30, 40, 60, 80, 150, 400]) {
        await tester.pump(Duration(milliseconds: elapsed));
        expect(tester.getRect(mic), initial);
        expect(tester.takeException(), isNull);
      }
      expect(
        tester.getSize(find.byType(GlassSurface)).width,
        closeTo(ShiriLayout.pillCollapsed, .1),
      );
      key.currentState!.collapse(false);
      await tester.pump();
      for (final elapsed in [30, 40, 60, 80, 150, 400]) {
        await tester.pump(Duration(milliseconds: elapsed));
        expect(tester.getRect(mic), initial);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('pill reverses from its current geometry without a jump', (
    tester,
  ) async {
    final key = GlobalKey<_PillHarnessState>();
    await tester.pumpWidget(_PillHarness(key: key));
    final mic = find.byKey(_microphoneKey);
    final anchored = tester.getRect(mic);
    final glass = find.byType(GlassSurface);
    key.currentState!.collapse(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final beforeReversal = tester.getRect(glass);
    expect(beforeReversal.width, lessThan(336));
    expect(beforeReversal.width, greaterThan(52));
    key.currentState!.collapse(false);
    await tester.pump();
    expect(tester.getRect(glass), beforeReversal);
    for (final elapsed in [16, 40, 80, 200, 500]) {
      await tester.pump(Duration(milliseconds: elapsed));
      expect(tester.getRect(mic), anchored);
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(glass).width, closeTo(336, .1));
  });

  testWidgets(
    'reversing before the first frame cancels the superseded target',
    (tester) async {
      final key = GlobalKey<_PillHarnessState>();
      await tester.pumpWidget(_PillHarness(key: key));
      key.currentState!.collapse(true);
      await tester.pump();
      key.currentState!.collapse(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(find.byType(GlassSurface)).width, 336);
      final pillAnimation = _geometryAnimation(
        tester,
        find.byType(AssistantPill),
      );
      expect(pillAnimation.isAnimating, isFalse);
      expect(pillAnimation.value, 0);

      final dockKey = GlobalKey<_DockHarnessState>();
      await tester.pumpWidget(_DockHarness(key: dockKey));
      final dock = find.byKey(const Key('dock-refreshed'));
      final indicator = find.descendant(
        of: dock,
        matching: find.byType(Positioned),
      );
      final origin = tester.getTopLeft(indicator);
      dockKey.currentState!.select(1);
      await tester.pump();
      dockKey.currentState!.select(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getTopLeft(indicator), origin);
      final dockAnimation = _geometryAnimation(tester, dock);
      expect(dockAnimation.isAnimating, isFalse);
      expect(dockAnimation.value, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('collapsed content stays mounted but cannot receive a tap', (
    tester,
  ) async {
    final key = GlobalKey<_PillHarnessState>();
    await tester.pumpWidget(_PillHarness(key: key));
    final input = find.byKey(const Key('assistant-dock-input'));
    final image = find.byTooltip('图片');
    await tester.tap(input);
    await tester.tap(image);
    expect(key.currentState!.opens, 1);
    expect(key.currentState!.images, 1);
    key.currentState!.collapse(true);
    await tester.pumpAndSettle();
    expect(input, findsOneWidget);
    expect(image, findsOneWidget);
    expect(input.hitTestable(), findsNothing);
    expect(image.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('holding voice survives collapse, reversal and parent refresh', (
    tester,
  ) async {
    final input = HoldInput();
    var captures = 0;
    final key = GlobalKey<_PillHarnessState>();
    await tester.pumpWidget(
      _PillHarness(
        key: key,
        microphone: HoldVoiceButton(
          key: _microphoneKey,
          compact: true,
          input: input,
          onRecorded: (_) async => captures++,
          onError: (_) {},
        ),
      ),
    );
    final mic = find.byType(HoldVoiceButton);
    final state = tester.state(mic);
    final anchored = tester.getRect(mic);
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(input.starts, 1);
    key.currentState!.collapse(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.state(mic), same(state));
    expect(tester.getRect(mic), anchored);
    expect(input.disposals, 0);
    key.currentState!.refresh();
    await tester.pump();
    key.currentState!.collapse(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.state(mic), same(state));
    expect(tester.getRect(mic), anchored);
    await gesture.up();
    await tester.pump();
    expect(captures, 1);
    expect(input.starts, 1);
    expect(input.stops, 1);
    expect(input.releases, 1);
    expect(input.disposals, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'reduced motion settles the current pill without moving its mic',
    (tester) async {
      final key = GlobalKey<_PillHarnessState>();
      await tester.pumpWidget(_PillHarness(key: key));
      final anchored = tester.getRect(find.byKey(_microphoneKey));
      key.currentState!.collapse(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      key.currentState!.reduce();
      await tester.pump();
      expect(tester.getSize(find.byType(GlassSurface)).width, 52);
      expect(tester.getRect(find.byKey(_microphoneKey)), anchored);
      final animation = _geometryAnimation(tester, find.byType(AssistantPill));
      expect(animation.isAnimating, isFalse);
      expect(animation.value, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden pill settles updates while its ticker is paused', (
    tester,
  ) async {
    final key = GlobalKey<_PillHarnessState>();
    await tester.pumpWidget(_PillHarness(key: key));
    key.currentState!.collapse(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    key.currentState!.pauseTickers();
    await tester.pump();
    expect(tester.getSize(find.byType(GlassSurface)).width, 52);
    final animation = _geometryAnimation(tester, find.byType(AssistantPill));
    expect(animation.isAnimating, isFalse);
    expect(animation.value, 1);
    key.currentState!.collapse(false);
    await tester.pump();
    expect(tester.getSize(find.byType(GlassSurface)).width, 336);
    expect(animation.isAnimating, isFalse);
    expect(animation.value, 0);
    expect(tester.takeException(), isNull);
  });
}
