import 'package:forui/forui.dart';
import 'package:semester_os/ui/forui_theme.dart';
import 'package:semester_os/ui/app_navigation.dart';
import 'package:semester_os/ui/assistant_scope.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/import/preview.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'package:semester_os/features/home/today_dashboard.dart';
import 'package:semester_os/features/calendar/calendar_panel.dart';
import 'package:semester_os/features/centers/semester_centers.dart';
import 'package:semester_os/features/centers/academic_visuals.dart';
import 'package:semester_os/ui/campus_theme.dart';
import 'api_session_test.dart' show ControlledTransport, body, account;
import 'controller_test.dart' show MemoryStore;
import 'reminder_sync_test.dart' show FakeNotifications;

final output = Platform.environment['UI_PREVIEW_DIR'];
var previewFont = false;
const captureKey = Key('ui-capture');

AppController sampleController() {
  final local = schoolNow();
  final today = DateTime(local.year, local.month, local.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final semester = <String, dynamic>{
    'id': 'sample',
    'name': '界面预览 · 示例数据',
    'first_monday': monday
        .subtract(const Duration(days: 21))
        .toIso8601String()
        .substring(0, 10),
    'total_weeks': 20,
    'revision': 1,
    'periods': [
      {'number': 1, 'start': '08:00', 'end': '08:50'},
      {'number': 2, 'start': '09:00', 'end': '09:50'},
      {'number': 9, 'start': '19:00', 'end': '19:50'},
      {'number': 10, 'start': '20:00', 'end': '20:50'},
    ],
  };
  final events = <Map<String, dynamic>>[];
  void add(String title, int day, String start, String end, String location) {
    final date = monday
        .add(Duration(days: day - 1))
        .toIso8601String()
        .substring(0, 10);
    events.add({
      'id': 'sample-${events.length}',
      'title': title,
      'teacher': '示例教师',
      'location': location,
      'weekday': day,
      'weeks': List.generate(16, (i) => i + 1),
      'sections': [1, 2],
      'start_at': '${date}T$start:00+08:00',
      'end_at': '${date}T$end:00+08:00',
      'conflict': false,
    });
  }

  add('高等数学', 1, '08:00', '09:50', 'A305');
  add('程序设计基础', 2, '10:10', '12:00', 'B204');
  add('大学英语', 3, '08:00', '09:50', 'C301');
  add('数据结构', 4, '14:00', '15:50', 'A401');
  add('线性代数', 5, '10:10', '12:00', 'B201');
  if (!events.any((e) => e['weekday'] == today.weekday)) {
    add('高等数学', today.weekday, '08:00', '09:50', 'A305');
  }
  add('程序设计基础', today.weekday, '14:00', '15:50', 'B204');
  events.sort((a, b) => '${a['start_at']}'.compareTo('${b['start_at']}'));
  final api = SemesterApi()..session = account('preview_demo');
  api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.path.endsWith('/imports')) {
      return body({
        'id': 'preview',
        'new_count': 2,
        'unchanged_count': 0,
        'changed_count': 0,
        'base_revision': 1,
      }, 201);
    }
    if (r.path.endsWith('/reminders')) {
      return body({'owner_id': 'preview_demo', 'reminders': []});
    }
    if (r.path.endsWith('/items')) return body({'revision': 1, 'items': []});
    if (r.path.endsWith('/courses')) return body(events);
    if (r.path.endsWith('/plans')) {
      return body({
        'semester_id': 'sample',
        'revision': 1,
        'blocks': [],
        'invalid_blocks': [],
      });
    }
    final query = Uri.parse(r.path).queryParameters;
    final entries = events
        .map((e) => {...e, 'resource_type': 'course', 'resource_id': e['id']})
        .toList();
    if (r.path.contains('/calendar?')) {
      return body({
        'semester_id': 'sample',
        'revision': 1,
        'from_date': query['from_date'],
        'to_date': query['to_date'],
        'entries': entries,
        'undated': [],
      });
    }
    if (r.path.contains('/day-brief?')) {
      return body({
        'semester_id': 'sample',
        'revision': 1,
        'date': query['day'],
        'valid_until': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'entries': entries.where((e) => e['weekday'] == today.weekday).toList(),
        'suggestions': [],
      });
    }
    if (r.path.endsWith('/hub')) {
      return body({
        'semester_id': 'sample',
        'semester': semester,
        'revision': 1,
        'valid_until': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'courses': events,
        'items': [],
        'exams': [],
        'weeks': [],
        'changes': [],
      });
    }
    return body({'revision': 1, 'events': events});
  });
  return AppController(api, MemoryStore(), clearSchoolSession: () async {})
    ..ready = true
    ..semester = semester
    ..semesters = [semester]
    ..week = 4
    ..events = events
    ..savedWeeks = {
      'sample/4': {'revision': 1, 'events': events},
    };
}

Future<ItemsController> sampleItems(AppController app) async {
  final items = ItemsController(
    app.api,
    app.cache,
    ReminderSync(FakeNotifications()),
  );
  await items.bind('${app.semester!['id']}');
  return items;
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double width = 390,
  double height = 844,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var theme = campusTheme();
  if (previewFont) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'PreviewSans'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'PreviewSans'),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontFamily: 'PreviewSans',
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontFamily: 'PreviewSans',
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: theme.listTileTheme.titleTextStyle?.copyWith(
          fontFamily: 'PreviewSans',
        ),
        subtitleTextStyle: theme.listTileTheme.subtitleTextStyle?.copyWith(
          fontFamily: 'PreviewSans',
        ),
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'PreviewSans',
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.copyWith(
          textStyle: WidgetStatePropertyAll(
            theme.filledButtonTheme.style?.textStyle
                ?.resolve({})
                ?.copyWith(fontFamily: 'PreviewSans'),
          ),
        ),
      ),
    );
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          FLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: ShiriForuiTheme(child: child!),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (output == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  final shadows = debugDisableShadows;
  void repaint(RenderObject node) {
    node.markNeedsPaint();
    node.visitChildren(repaint);
  }

  debugDisableShadows = false;
  repaint(boundary);
  await tester.pump();
  try {
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(output!);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  } finally {
    debugDisableShadows = shadows;
    repaint(boundary);
    await tester.pump();
  }
}

Future<void> loadPreviewFonts() async {
  if (output == null) return;
  final path = Platform.environment['UI_PREVIEW_FONT'];
  if (path != null && File(path).existsSync()) {
    final loader = FontLoader('PreviewSans')
      ..addFont(File(path).readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
    previewFont = true;
  }
  final icons = Platform.environment['UI_PREVIEW_ICONS'];
  if (icons != null && File(icons).existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(
          File(icons).readAsBytes().then((b) => ByteData.sublistView(b)),
        ))
        .load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'live shell renders sample today, calendar, task and semester views',
    (tester) async {
      final controller = sampleController();
      final items = (await tester.runAsync(() => sampleItems(controller)))!;
      await mount(tester, ShellPage(controller: controller, items: items));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TodayDashboard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'today');
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavigation),
          matching: find.text('日程'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('周日'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'timetable');
      expect(find.byType(CalendarPanel), findsOneWidget);
      expect(find.text('高等数学'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavigation),
          matching: find.text('计划'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ItemsView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'tasks');
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavigation),
          matching: find.text('学期'),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SemesterHome), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'semester');
      await tester.pumpWidget(const SizedBox.shrink());
      items.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'small screen with large text keeps navigation and courses usable',
    (tester) async {
      final controller = sampleController();
      final items = (await tester.runAsync(() => sampleItems(controller)))!;
      var opened = false;
      await mount(
        tester,
        AssistantScope(
          onOpen:
              (context, {initialText, mediaKind, autoSubmit = false}) async {
                opened = true;
              },
          child: ShellPage(controller: controller, items: items),
        ),
        width: 360,
        height: 800,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavigation),
          matching: find.text('日程'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPanel), findsOneWidget);
      expect(find.text('高等数学'), findsWidgets);
      expect(tester.takeException(), isNull);
      await capture(tester, 'large-text');
      await tester.tap(find.byKey(const Key('assistant-dock-input')));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.descendant(
          of: find.byType(AppNavigation),
          matching: find.text('今日'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('账户'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('退出登录'));
      expect(find.text('退出登录').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      items.dispose();
      controller.dispose();
    },
  );

  testWidgets('import preview preserves confirmation and source fields', (
    tester,
  ) async {
    final controller = sampleController();
    await mount(
      tester,
      Scaffold(
        body: ImportPreview(
          controller: controller,
          courses: [
            {
              'title': '高等数学',
              'weekday': 1,
              'weeks': [1, 2, 3, 4],
              'sections': [1, 2],
              'location': 'A305',
              'teacher': '示例教师',
            },
            {
              'title': '程序设计基础',
              'weekday': 2,
              'weeks': [1, 3, 5, 7],
              'sections': [3, 4],
              'location': 'B204',
              'teacher': '示例教师',
            },
          ],
          source: 'haut_webview',
          sourceTerm: '示例学年 第一学期',
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.text('新增'), findsOneWidget);
    expect(
      tester
          .widget<AcademicStatStrip>(find.byType(AcademicStatStrip))
          .stats
          .singleWhere((stat) => stat.label == '新增')
          .value,
      2,
    );
    expect(find.text('确认保存课表'), findsOneWidget);
    expect(find.text('第1—7周 · 单周'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, 'import-preview');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
