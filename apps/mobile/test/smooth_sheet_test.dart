import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/ui/app_sheet.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

void main() {
  testWidgets('assistant sheet footer accepts taps at its painted position', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppSheet<void>(
                context: context,
                heightFactor: .9,
                builder: (_) => Column(
                  children: [
                    const Expanded(child: Text('Conversation')),
                    SizedBox(
                      height: 72,
                      child: IconButton(
                        tooltip: 'Keyboard',
                        onPressed: () => taps++,
                        icon: const Icon(Icons.keyboard),
                      ),
                    ),
                  ],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Keyboard'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one smooth sheet disposes content after swipe, barrier and back',
    (tester) async {
      var disposed = 0;
      Future<void>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  result = showAppSheet<void>(
                    context: context,
                    heightFactor: .9,
                    builder: (_) =>
                        _DisposableBody(onDispose: () => disposed++),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      for (final dismissal in ['swipe', 'barrier', 'back']) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(Sheet), findsOneWidget);
        expect(find.byKey(const ValueKey('app-sheet-handle')), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        switch (dismissal) {
          case 'swipe':
            await tester.fling(
              find.byKey(const ValueKey('app-sheet-handle')),
              const Offset(0, 600),
              2000,
            );
          case 'barrier':
            await tester.tapAt(const Offset(20, 2));
          case 'back':
            await tester.binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(Sheet), findsNothing);
        await result;
        expect(tester.takeException(), isNull);
      }
      expect(disposed, 3);
    },
  );

  for (final size in [const Size(320, 760), const Size(740, 390)]) {
    testWidgets('sheet consumes keyboard inset once at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      late MediaQueryData bodyMedia;
      late BoxConstraints bodyConstraints;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAppSheet<void>(
                  context: context,
                  heightFactor: .9,
                  builder: (context) {
                    bodyMedia = MediaQuery.of(context);
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        bodyConstraints = constraints;
                        return Column(
                          children: [
                            const Expanded(
                              child: SingleChildScrollView(
                                child: Text('Conversation content'),
                              ),
                            ),
                            SizedBox(
                              key: const ValueKey('composer'),
                              height: 72,
                              child: const TextField(),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final editor = tester.state(find.byType(EditableText));
      final keyboard = size.height > 500 ? 300.0 : 180.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      expect(bodyMedia.viewInsets.bottom, 0);
      expect(bodyMedia.size.height, bodyConstraints.maxHeight);
      expect(
        tester.getBottomLeft(find.byKey(const ValueKey('composer'))).dy,
        closeTo(size.height - keyboard, 1),
      );
      expect(tester.state(find.byType(EditableText)), same(editor));
      expect(tester.takeException(), isNull);
    });
  }
}

class _DisposableBody extends StatefulWidget {
  const _DisposableBody({required this.onDispose});
  final VoidCallback onDispose;

  @override
  State<_DisposableBody> createState() => _DisposableBodyState();
}

class _DisposableBodyState extends State<_DisposableBody> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Center(child: Text('Assistant'));
}
