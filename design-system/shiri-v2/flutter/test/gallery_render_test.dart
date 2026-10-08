// 渲染关键组件并导出预览 PNG（也用于确认运行时无布局异常）。
// 运行：在包含 lib/shiri/** 的 Flutter 工程里执行 `flutter test test/gallery_render_test.dart`
// 预览输出到环境变量 SHIRI_PREVIEW_DIR（未设置则只做渲染检查）。
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiri_v2_check/shiri/motion/completion_check.dart';
import 'package:shiri_v2_check/shiri/motion/spring_segmented.dart';
import 'package:shiri_v2_check/shiri/shiri_theme.dart';
import 'package:shiri_v2_check/shiri/shiri_tokens.dart';
import 'package:shiri_v2_check/shiri/widgets/gap_slot_bar.dart';
import 'package:shiri_v2_check/shiri/widgets/glass_dock.dart';
import 'package:shiri_v2_check/shiri/widgets/schedule_block.dart';
import 'package:shiri_v2_check/shiri/widgets/sky_header.dart';

final _key = GlobalKey();

Future<void> _fonts() async {
  final cjk = FontLoader('NotoSansSC')
    ..addFont(File('C:/Windows/Fonts/NotoSansSC-VF.ttf').readAsBytes().then(ByteData.sublistView));
  await cjk.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('C:/Users/keleoz/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
        .readAsBytes()
        .then(ByteData.sublistView));
  await icons.load();
}

Widget _gallery(DateTime now) => Builder(
  builder: (context) {
    final shiri = context.shiri;
    final onSky = ShiriGradients.onSky(now);
    return Scaffold(
      backgroundColor: shiri.colors.bg,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              SkyHeader(
                now: now,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 96, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('11月4日 周三', style: shiri.text.display.copyWith(color: onSky)),
                      const SizedBox(height: 10),
                      Text('第 10 周 · 共 20 周', style: shiri.text.label.copyWith(color: onSky.withValues(alpha: .7))),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: ShiriGradients.brandSoft, borderRadius: ShiriRadius.lgAll),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('课前空档 · 40 分钟', style: shiri.text.label.copyWith(color: shiri.colors.success)),
                      const SizedBox(height: 12),
                      const GapSlotBar(
                        start: '13:20', end: '14:00', gapMinutes: 40,
                        taskTitle: '整理实验数据', taskMinutes: 20, filled: true, nextLabel: '数据结构',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SizedBox(
                  height: 96,
                  child: Row(
                    children: [
                      for (final (t, k, l) in const [
                        ('数据结构', ScheduleKind.course, 'A305'),
                        ('组会', ScheduleKind.event, '302'),
                        ('复习线代', ScheduleKind.plan, null),
                        ('大学物理', ScheduleKind.exam, 'C102'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: ScheduleBlock(title: t, kind: k, location: l, onTap: () {}),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SpringSegmented<int>(
                  segments: const [(0, '待处理'), (1, '已完成'), (2, '已取消')],
                  selected: 0,
                  onChanged: (_) {},
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
                child: Row(
                  children: [
                    CompletionCheck(status: CompletionStatus.idle, onPressed: () {}),
                    CompletionCheck(status: CompletionStatus.done, onPressed: () {}),
                    const SizedBox(width: 8),
                    const Expanded(child: StrikeThroughText('提交实验报告', struck: true)),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 12, right: 12, bottom: 12,
            child: Column(
              children: [
                AssistantPill(collapsed: false, onOpen: () {}, onImage: () {}),
                const SizedBox(height: ShiriLayout.pillGapAboveDock),
                GlassDock(
                  index: 0,
                  onSelect: (_) {},
                  items: const [
                    GlassDockItem(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny_rounded), label: '今日'),
                    GlassDockItem(icon: Icon(Icons.calendar_view_week_outlined), selectedIcon: Icon(Icons.calendar_view_week_rounded), label: '日程'),
                    GlassDockItem(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist_rounded), label: '任务'),
                    GlassDockItem(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag_rounded), label: '学期'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  },
);

Future<void> _render(WidgetTester tester, DateTime now, String name) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: shiriLightTheme(fontFamily: 'NotoSansSC'),
      home: _gallery(now),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final dir = Platform.environment['SHIRI_PREVIEW_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(dir).create(recursive: true);
    await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(_fonts);
  testWidgets('gallery · day', (t) => _render(t, DateTime(2026, 11, 4, 13, 18), 'gallery-day'));
  testWidgets('gallery · night', (t) => _render(t, DateTime(2026, 11, 4, 21, 10), 'gallery-night'));
}
