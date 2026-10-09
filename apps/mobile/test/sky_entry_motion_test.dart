import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/centers/semester_horizon.dart';
import 'package:semester_os/features/home/today_sky_header.dart';
import 'package:semester_os/ui/v2/shiri_theme.dart';
import 'package:semester_os/ui/v2/widgets/sky_header.dart';
import 'package:semester_os/ui/forui_theme.dart';

Widget host(
  Widget child, {
  bool reduced = false,
  bool ticker = true,
  double textScale = 1,
}) => MaterialApp(
  theme: shiriLightTheme(),
  localizationsDelegates: const [
    FLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: const Size(360, 800),
        disableAnimations: reduced,
        textScaler: TextScaler.linear(textScale),
      ),
      child: ShiriForuiTheme(
        child: TickerMode(
          enabled: ticker,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: 360, child: child),
          ),
        ),
      ),
    ),
  ),
);

SunArcPainter skyPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<SunArcPainter>()
    .single;

double horizonProgress(WidgetTester tester) =>
    (tester
                .widget<AnimatedBuilder>(
                  find.descendant(
                    of: find.byType(SemesterHorizon),
                    matching: find.byType(AnimatedBuilder),
                  ),
                )
                .animation
            as Animation<double>)
        .value;

void main() {
  test('celestial entry follows both coordinates of its arc', () {
    const size = Size(176, 104);
    final start = const SunArcPainter(progress: .65, rise: 0).centerFor(size);
    final middle = const SunArcPainter(progress: .65, rise: .5).centerFor(size);
    final end = const SunArcPainter(progress: .65).centerFor(size);
    expect(start.dx, lessThan(0));
    expect(middle.dx, greaterThan(start.dx));
    expect(middle.dx, lessThan(end.dx));
    expect(middle.dy, lessThan(start.dy));
    expect((middle.dx - end.dx).abs(), greaterThan(10));
    // Even the first point has a curved approach from below the horizon.
    expect(
      const SunArcPainter(progress: 0, rise: 0).centerFor(size),
      isNot(const SunArcPainter(progress: 0).centerFor(size)),
    );
    expect(
      const SunArcPainter(progress: .65, night: true).centerFor(size),
      end,
    );
  });

  testWidgets('sky replays only on an entry epoch and pauses underneath', (
    tester,
  ) async {
    Widget sky({int epoch = 0, bool active = true, bool ticker = true}) => host(
      SkyHeader(
        now: DateTime.utc(2026, 10, 9, 12),
        active: active,
        entryEpoch: epoch,
      ),
      ticker: ticker,
    );
    await tester.pumpWidget(sky());
    expect(skyPainter(tester).rise, 0);
    await tester.pump(const Duration(milliseconds: 180));
    final underway = skyPainter(tester).rise;
    expect(underway, greaterThan(0));
    expect(underway, lessThan(1));
    await tester.pumpWidget(sky(active: false));
    await tester.pump(const Duration(seconds: 1));
    expect(skyPainter(tester).rise, underway);
    await tester.pumpWidget(sky());
    expect(skyPainter(tester).rise, underway);
    await tester.pump(const Duration(milliseconds: 520));
    expect(skyPainter(tester).rise, 1);
    await tester.pumpWidget(sky());
    expect(skyPainter(tester).rise, 1);
    await tester.pumpWidget(sky(epoch: 1));
    expect(skyPainter(tester).rise, 0);
    await tester.pump(const Duration(milliseconds: 140));
    final beforeBackground = skyPainter(tester).rise;
    await tester.pumpWidget(sky(epoch: 1, ticker: false));
    await tester.pump(const Duration(seconds: 1));
    expect(skyPainter(tester).rise, beforeBackground);
    await tester.pumpWidget(sky(epoch: 1));
    expect(skyPainter(tester).rise, beforeBackground);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('night arc uses clock position and reduced motion stays final', (
    tester,
  ) async {
    final sky = SkyHeader(now: DateTime.utc(2026, 10, 9, 0));
    await tester.pumpWidget(host(sky, reduced: true));
    expect(skyPainter(tester).night, isTrue);
    expect(skyPainter(tester).progress, .5);
    expect(skyPainter(tester).rise, 1);
    await tester.pumpWidget(host(sky));
    expect(skyPainter(tester).rise, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('semester entry replays without changing saved week semantics', (
    tester,
  ) async {
    Widget horizon({int epoch = 0, bool active = true, bool reduced = false}) =>
        host(
          SemesterHorizon(
            current: 6,
            total: 20,
            examWeeks: const {12, 18},
            active: active,
            entryEpoch: epoch,
          ),
          reduced: reduced,
        );
    await tester.pumpWidget(horizon());
    expect(horizonProgress(tester), 0);
    await tester.pump(const Duration(milliseconds: 180));
    final underway = horizonProgress(tester);
    await tester.pumpWidget(horizon(active: false));
    await tester.pump(const Duration(seconds: 1));
    expect(horizonProgress(tester), underway);
    await tester.pumpWidget(horizon());
    expect(horizonProgress(tester), underway);
    await tester.pumpAndSettle();
    expect(horizonProgress(tester), 1);
    await tester.pumpWidget(horizon(epoch: 1));
    expect(horizonProgress(tester), 0);
    await tester.pumpWidget(horizon(epoch: 1, reduced: true));
    expect(horizonProgress(tester), 1);
    expect(
      tester.widget<SemesterHorizon>(find.byType(SemesterHorizon)).current,
      6,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand to date has no threshold jump and actions stay readable', (
    tester,
  ) async {
    Widget header(double collapse) => host(
      TodaySkyHeader(
        now: DateTime.utc(2026, 10, 9, 12),
        semester: const {'first_monday': '2026-09-07', 'total_weeks': 20},
        collapse: collapse,
        onProfile: () {},
        onSettings: () {},
      ),
      reduced: true,
      textScale: 1.6,
    );
    double alpha(String key) =>
        tester.widget<Opacity>(find.byKey(ValueKey(key))).opacity;
    await tester.pumpWidget(header(.6999));
    final before = alpha('sky-date-title');
    await tester.pumpWidget(header(.7001));
    expect((alpha('sky-date-title') - before).abs(), lessThan(.01));
    await tester.pumpWidget(header(1));
    expect(alpha('sky-brand-title'), 0);
    expect(alpha('sky-date-title'), 1);
    final edge = find.byKey(const ValueKey('sky-scenery-edge'));
    expect(edge, findsOneWidget);
    expect(
      find.descendant(of: edge, matching: find.byTooltip('账户')),
      findsNothing,
    );
    expect(find.byTooltip('账户').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
