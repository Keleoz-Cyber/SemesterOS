import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/v2/motion/spring_segmented.dart';
import 'package:semester_os/ui/v2/widgets/glass_dock.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/campus_theme.dart';

void main() {
  testWidgets(
    'glass navigation preserves tab selection and Android touch targets',
    (tester) async {
      var selected = 0;
      final changes = <int>[];
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: campusTheme(),
          home: StatefulBuilder(
            builder: (context, update) => RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                bottomNavigationBar: AppNavigation(
                  selected: selected,
                  onSelected: (value) => update(() {
                    selected = value;
                    changes.add(value);
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(GlassDock), findsOneWidget);
      expect(find.byType(InkResponse), findsNWidgets(4));
      await tester.pumpAndSettle();
      final schedule = find.ancestor(
        of: find.text('日程'),
        matching: find.byType(InkResponse),
      );
      await expectNoPressOverlay(tester, boundaryKey, schedule);
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(changes, [1]);
      await expectNoPressOverlay(tester, boundaryKey, schedule);
      await tester.pumpAndSettle();
      expect(changes, [1]);
      for (final element in find.byType(InkResponse).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('segmented selection keeps its surface during a held press', (
    tester,
  ) async {
    var selected = 'active';
    final changes = <String>[];
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: campusTheme(),
        home: StatefulBuilder(
          builder: (context, update) => RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: SpringSegmented<String>(
                    segments: const [
                      ('active', '待处理'),
                      ('completed', '已完成'),
                      ('cancelled', '已取消'),
                    ],
                    selected: selected,
                    onChanged: (value) => update(() {
                      selected = value;
                      changes.add(value);
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cancelled = find.ancestor(
      of: find.text('已取消'),
      matching: find.byType(InkWell),
    );
    await expectNoPressOverlay(tester, boundaryKey, cancelled);
    await tester.pumpAndSettle();
    expect(selected, 'cancelled');
    expect(changes, ['cancelled']);
    await expectNoPressOverlay(tester, boundaryKey, cancelled);
    await tester.pumpAndSettle();
    expect(changes, ['cancelled']);
    expect(tester.takeException(), isNull);
  });
}

/// Check the actual painted, held frame before onTap changes selection.
Future<void> expectNoPressOverlay(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Finder target,
) async {
  final rect = tester.getRect(target);
  final point = rect.topLeft + const Offset(8, 8);
  final before = await readPixel(tester, boundaryKey, point);
  final gesture = await tester.startGesture(rect.center);
  try {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(await readPixel(tester, boundaryKey, point), before);
  } finally {
    await gesture.up();
  }
}

Future<List<int>> readPixel(
  WidgetTester tester,
  GlobalKey boundaryKey,
  Offset point,
) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final local = boundary.globalToLocal(point);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
      return List<int>.generate(4, (i) => bytes.getUint8(offset + i));
    } finally {
      image.dispose();
    }
  }))!;
}
