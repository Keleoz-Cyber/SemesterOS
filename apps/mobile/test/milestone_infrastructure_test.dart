import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/ui/accessibility.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/ui/campus_theme.dart';
import 'package:semester_os/ui/detail_widgets.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'package:semester_os/ui/motion.dart';
import 'package:semester_os/ui/performance_widgets.dart';

Widget _app(Widget child, {bool reduced = true, bool highContrast = false}) =>
    MaterialApp(
      theme: campusTheme(),
      builder: (context, content) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: reduced, highContrast: highContrast),
        child: ShiriForuiTheme(child: content!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets(
    'custom actions support semantics and Enter/Space without hiding card actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var primary = 0, nested = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              SemanticButton(
                label: '激活',
                onPressed: () => primary++,
                child: const SizedBox(width: 100, height: 48),
              ),
              SemanticCard(
                label: '事项卡片',
                child: TextButton(
                  onPressed: () => nested++,
                  child: const Text('查看详情'),
                ),
              ),
            ],
          ),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('激活'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      expect(primary, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(primary, 3);
      final nestedNode = tester.getSemantics(find.bySemanticsLabel('查看详情'));
      expect(
        nestedNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      nestedNode.owner!.performAction(nestedNode.id, SemanticsAction.tap);
      expect(nested, 1);

      const labels = ['账户', '调整首页内容', '图片通知', '语音输入'];
      var activated = 0;
      await tester.pumpWidget(
        _app(
          Row(
            children: [
              for (final label in labels)
                AppIconButton(
                  tooltip: label,
                  onPressed: () => activated++,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ],
          ),
        ),
      );
      final named = <String, List<SemanticsNode>>{
        for (final label in labels) label: [],
      };
      void collect(SemanticsNode node) {
        // Merged descendants contribute to their parent; the platform exports
        // only that parent as the accessible control.
        if (!node.isMergedIntoParent) {
          final data = node.getSemanticsData();
          for (final label in labels) {
            if (data.label == label || data.tooltip == label) {
              named[label]!.add(node);
            }
          }
        }
        node.visitChildren((child) {
          collect(child);
          return true;
        });
      }

      collect(tester.getSemantics(find.byType(Scaffold)));
      for (final label in labels) {
        expect(named[label], hasLength(1), reason: '$label is announced once');
        final action = named[label]!.single;
        expect(
          action.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        action.owner!.performAction(action.id, SemanticsAction.tap);
      }
      expect(activated, labels.length);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
    },
  );

  testWidgets(
    'shared Forui submit starts immediately and awaits the actual operation',
    (tester) async {
      final first = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        _app(
          ActionFooter(
            label: '保存',
            onPressed: () async {
              calls++;
              if (calls == 1) await first.future;
            },
          ),
        ),
      );
      final initialButtonSize = tester.getSize(find.byType(FButton));
      await tester.tap(find.byType(FButton));
      await tester.pump();
      expect(calls, 1);
      expect(tester.getSize(find.byType(FButton)), initialButtonSize);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
      expect(tester.widget<FButton>(find.byType(FButton)).onPress, isNull);
      await tester.tap(find.byType(FButton));
      expect(calls, 1);
      first.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<FButton>(find.byType(FButton)).onPress, isNotNull);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsNothing);
      await tester.tap(find.byType(FButton));
      await tester.pump();
      expect(calls, 2);
      // Forui keeps a brief press-feedback timer after pointer release.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());

      final navigation = Completer<void>();
      var openings = 0;
      await tester.pumpWidget(
        _app(
          AppIconButton(
            tooltip: '更多操作',
            guardAsync: false,
            onPressed: () async {
              openings++;
              await navigation.future;
            },
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ),
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      expect(openings, 1);
      expect(tester.widget<FButton>(find.byType(FButton)).onPress, isNotNull);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      expect(openings, 2);
      navigation.complete();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disclosure reveals without scaling and handles rapid or reduced changes',
    (tester) async {
      var open = false, reduced = false;
      Widget view() => _app(
        AppExpandRegion(
          visible: open,
          child: const SizedBox(
            key: Key('expanded-body'),
            height: 160,
            child: Text('展开内容'),
          ),
        ),
        reduced: reduced,
      );
      await tester.pumpWidget(view());
      expect(find.text('展开内容'), findsNothing);
      open = true;
      await tester.pumpWidget(view());
      await tester.pump(const Duration(milliseconds: 65));
      final midway = tester.getSize(find.byType(AppExpandRegion)).height;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(160));
      expect(
        tester.getSize(find.byKey(const Key('expanded-body'))).height,
        160,
      );
      open = false;
      await tester.pumpWidget(view());
      await tester.pump(const Duration(milliseconds: 30));
      open = true;
      await tester.pumpWidget(view());
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppExpandRegion)).height, 160);
      open = false;
      await tester.pumpWidget(view());
      await tester.pump(const Duration(milliseconds: 40));
      reduced = true;
      await tester.pumpWidget(view());
      expect(tester.getSize(find.byType(AppExpandRegion)).height, 0);
      await tester.pump();
      expect(find.text('展开内容'), findsNothing);
      // Allow the surrounding Material/Forui configuration change to settle.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion renders completed entrances and stops repeated tickers',
    (tester) async {
      final content = Column(
        children: const [
          TabEntrance(active: true, child: Text('可见内容')),
          LoadingDots(),
          SkeletonLoader(width: 200, height: 60),
          SuccessCheckmark(),
        ],
      );
      await tester.pumpWidget(_app(content));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(
        tester
            .widget<FadeTransition>(find.byType(FadeTransition).first)
            .opacity
            .value,
        1,
      );
      await tester.pumpWidget(
        _app(TickerMode(enabled: false, child: content), reduced: false),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cache expires, changes owner and never reuses captured parent data',
    (tester) async {
      var now = DateTime(2026, 10, 2);
      final cache = MemoryCache<String, int>(
        maxSize: 2,
        expiration: const Duration(seconds: 2),
        clock: () => now,
      );
      cache.setOwner('a');
      cache.set('first', 1);
      cache.set('second', 2);
      expect(cache.get('first'), 1);
      cache.set('third', 3);
      expect(cache.get('second'), isNull);
      cache.set('first', 4);
      expect(cache.size, 2);
      now = now.add(const Duration(seconds: 2));
      expect(cache.get('first'), isNull);
      cache.set('private', 5);
      cache.setOwner('b');
      expect(cache.get('private'), isNull);

      var caption = '旧数据';
      Widget render() => BuildCache(
        cacheKey: 'header',
        ownerGeneration: 'a',
        cacheDuration: const Duration(milliseconds: 50),
        builder: (_) => Text(caption),
      );
      await tester.pumpWidget(_app(render()));
      expect(find.text('旧数据'), findsOneWidget);
      caption = '父级新数据';
      await tester.pumpWidget(_app(render()));
      expect(find.text('父级新数据'), findsOneWidget);
      caption = '到期新数据';
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('到期新数据'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      var revision = 1, builds = 0;
      Widget explicit() => BuildCache(
        cacheKey: 'header',
        ownerGeneration: 'a',
        invalidationKey: revision,
        builder: (_) {
          builds++;
          return Text('修订$revision');
        },
      );
      await tester.pumpWidget(_app(explicit()));
      expect(builds, 1);
      await tester.pumpWidget(_app(explicit()));
      expect(builds, 1);
      revision = 2;
      await tester.pumpWidget(_app(explicit()));
      expect(builds, 2);
      expect(find.text('修订2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'paging failure stays retryable and external controller survives replacement',
    (tester) async {
      final firstController = ScrollController();
      final secondController = ScrollController();
      var calls = 0;
      Future<List<int>> request() async {
        calls++;
        if (calls == 1) throw StateError('offline');
        return [1];
      }

      Widget render(ScrollController? controller) => LazyLoadList<int>(
        pagingKey: 'owner-a',
        controller: controller,
        items: const [1],
        hasMore: true,
        onLoadMore: request,
        itemBuilder: (_, item, _) => Text('记录$item'),
      );
      await tester.pumpWidget(_app(render(firstController)));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('加载失败，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
      await tester.pumpWidget(_app(render(secondController)));
      firstController.addListener(() {});
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(calls, 2);
      expect(find.text('加载失败，请重试'), findsNothing);
      await tester.pumpWidget(_app(render(null)));
      secondController.addListener(() {});
      await tester.pumpWidget(const SizedBox.shrink());
      firstController.dispose();
      secondController.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private image keys isolate owners, bound decoding and evict on owner replacement',
    (tester) async {
      final bytes = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==',
        ),
      );
      Widget render(String owner) => SizedBox(
        width: 120,
        child: OptimizedImage.memory(
          bytes: bytes,
          ownerGeneration: owner,
          maxDecodeWidth: 160,
          semanticLabel: '私有通知',
        ),
      );
      await tester.pumpWidget(_app(render('owner-a'), highContrast: true));
      final first =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(first.width, lessThanOrEqualTo(160));
      final firstProvider = first.imageProvider as OwnerScopedMemoryImage;
      expect(firstProvider.ownerGeneration, 'owner-a');
      await tester.pumpWidget(_app(render('owner-b')));
      final second =
          tester.widget<Image>(find.byType(Image)).image as ResizeImage;
      expect(second.imageProvider, isNot(firstProvider));
      expect(
        (second.imageProvider as OwnerScopedMemoryImage).ownerGeneration,
        'owner-b',
      );
      final cacheKey = await first.obtainKey(const ImageConfiguration());
      expect(
        PaintingBinding.instance.imageCache.containsKey(cacheKey),
        isFalse,
      );
      final high = campusForuiTheme(highContrast: true);
      expect(high.colors.foreground, HighContrastTheme.text);
      expect(high.colors.primary, HighContrastTheme.primary);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
