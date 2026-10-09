// 宣传片界面素材导出：真实生产页面 + 合成演示数据，4 倍分辨率 PNG。
//
// 在 apps/mobile 目录运行（PowerShell）：
//   $env:UI_PREVIEW_FONT='C:/Windows/Fonts/NotoSansSC-VF.ttf'
//   $env:UI_PREVIEW_ICONS="$env:USERPROFILE/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf"
//   $env:PROMO_OUT='D:/study/Contest/AIC/promo/public/plates'; flutter test tool/export_promo_plates.dart
//
// 演示日 = 运行当天（任务紧急度按真实日期计算，保持一致），钟面时间由 debugSchoolClock 固定。
// 数据全部为匿名合成：通用课程名与教室号，不含学校信息。
// 此文件通过 flutter test 运行；位于 tool/，分析器不会将其识别为测试目录。
// 仅允许此测试驱动访问调试时钟，保留业务代码上的 @visibleForTesting 限制。
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show RequestOptions, ResponseBody;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/timetable/shell_page.dart';

import '../test/api_session_test.dart' show ControlledTransport, body, account;
import '../test/controller_test.dart' show MemoryStore;
import '../test/ui_polish_test.dart'
    as preview
    show captureKey, mount, sampleItems, previewFont;

final _out = Platform.environment['PROMO_OUT'];

Future<void> _loadPreviewFonts() async {
  if (_out == null) return;
  final font = Platform.environment['UI_PREVIEW_FONT'];
  if (font != null) {
    final file = File(font);
    if (!file.existsSync()) throw StateError('UI_PREVIEW_FONT 文件不存在：$font');
    await (FontLoader('PreviewSans')..addFont(
          file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
    preview.previewFont = true;
  }
  final icons = Platform.environment['UI_PREVIEW_ICONS'];
  if (icons != null) {
    final file = File(icons);
    if (!file.existsSync()) throw StateError('UI_PREVIEW_ICONS 文件不存在：$icons');
    await (FontLoader('MaterialIcons')..addFont(
          file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        ))
        .load();
  }
}

String _d(DateTime day) => day.toIso8601String().substring(0, 10);
String _at(DateTime day, String hm) => '${_d(day)}T$hm:00+08:00';

class PromoWorld {
  PromoWorld(
    this.today, {
    this.meeting = false,
    this.arranged = false,
    this.swapped = false,
  });

  final DateTime today; // 当天 00:00（钟面日期）
  final bool meeting; // 已添加"开会"
  final bool arranged; // 课前空档已安排
  final bool swapped; // 概率论调到明天晚上、复习线代换到今晚
  final unexpectedRequests = <String>[];

  DateTime get monday => today.subtract(Duration(days: today.weekday - 1));
  DateTime get tomorrow => today.add(const Duration(days: 1));

  static const periods = [
    ('08:00', '08:50'),
    ('09:00', '09:50'),
    ('10:10', '11:00'),
    ('11:10', '12:00'),
    ('14:00', '14:50'),
    ('15:00', '15:50'),
    ('16:10', '17:00'),
    ('17:10', '18:00'),
    ('19:00', '19:50'),
    ('20:00', '20:50'),
  ];
  static const patterns = [
    [('高等数学', 1, 2, 'A301'), ('大学英语', 3, 4, 'B204'), ('数据结构', 5, 6, 'A305')],
    [('线性代数', 1, 2, 'A301'), ('程序设计', 3, 4, '机房3'), ('体育', 7, 8, '操场')],
    [('大学物理', 1, 2, 'C102'), ('数据结构', 5, 6, 'A305')],
    [('高等数学', 1, 2, 'A301'), ('操作系统', 3, 4, 'A402')],
  ];

  Map<String, dynamic> get semester => {
    'id': 'promo',
    'name': '2026–2027 学年 · 第一学期',
    'first_monday': _d(monday.subtract(const Duration(days: 63))),
    'total_weeks': 20,
    'revision': 1,
    'periods': [
      for (final (i, p) in periods.indexed)
        {'number': i + 1, 'start': p.$1, 'end': p.$2},
    ],
  };

  late final List<Map<String, dynamic>> courses = _courses();
  List<Map<String, dynamic>> _courses() {
    final out = <Map<String, dynamic>>[];
    void add(String title, DateTime day, int s, int e, String room) => out.add({
      'id': 'c${out.length}',
      'title': title,
      'teacher': '示例教师',
      'location': room,
      'weekday': day.weekday,
      'weeks': List.generate(16, (i) => i + 1),
      'sections': [for (var n = s; n <= e; n++) n],
      'start_at': _at(day, periods[s - 1].$1),
      'end_at': _at(day, periods[e - 1].$2),
      'conflict': false,
    });
    var p = 0;
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day == today) {
        add('大学物理', day, 1, 2, 'C102');
        add('软件工程', day, 5, 6, 'A305');
        if (!swapped) add('概率论', day, 9, 10, 'B102');
      } else if (day == tomorrow) {
        if (swapped) add('概率论', day, 9, 10, 'B102');
      } else if (day.weekday <= 5) {
        for (final c in patterns[p++ % patterns.length]) {
          add(c.$1, day, c.$2, c.$3, c.$4);
        }
      }
    }
    return out;
  }

  Map<String, dynamic> _entry(
    String type,
    String id,
    String title,
    String start,
    String end,
    String room,
  ) => {
    'id': '$type:$id',
    'resource_id': id,
    'resource_type': type,
    'title': title,
    'start_at': start,
    'end_at': end,
    'location': room,
    'time_precision': 'exact',
  };

  List<Map<String, dynamic>> get entries => [
    for (final c in courses)
      {
        ...c,
        'resource_type': 'course',
        'resource_id': c['id'],
        'time_precision': 'exact',
      },
    _entry(
      'event',
      'meet-group',
      '组会',
      _at(today, '17:00'),
      _at(today, '18:00'),
      '实验室302',
    ),
    if (meeting)
      _entry(
        'event',
        'meet-office',
        '开会',
        _at(tomorrow, '15:00'),
        _at(tomorrow, '16:00'),
        '发布者办公室',
      ),
    _entry(
      'exam',
      'exam-physics',
      '大学物理 期中考试',
      _at(tomorrow, '09:00'),
      _at(tomorrow, '11:00'),
      'C102',
    ),
    swapped
        ? _entry(
            'plan',
            'b-review',
            '复习线代',
            _at(today, '19:00'),
            _at(today, '20:30'),
            '',
          )
        : _entry(
            'plan',
            'b-review',
            '复习线代',
            _at(tomorrow, '19:00'),
            _at(tomorrow, '20:30'),
            '',
          ),
    if (arranged)
      _entry(
        'plan',
        'b-data',
        '整理实验数据',
        _at(today, '13:20'),
        _at(today, '13:40'),
        '',
      ),
  ];

  Map<String, dynamic> _task(
    String id,
    String title,
    String course,
    int minutes,
    String? at, {
    String kind = 'assignment',
  }) => {
    'id': id,
    'semester_id': 'promo',
    'kind': kind,
    'version': 1,
    'title': title,
    'lifecycle': 'active',
    'certainty': 'formal',
    'remaining_minutes': minutes,
    'start_policy': 'now',
    'priority': 'normal',
    'splittable': true,
    'category_id': 'study',
    'course_title': course,
    'time': at == null
        ? {'precision': 'unknown'}
        : {'precision': 'exact', 'at': at},
    'anchor_at': ?at,
    'reminders': [],
  };

  List<Map<String, dynamic>> get items => [
    _task('t-report', '提交实验报告', '大学物理', 60, _at(today, '23:59')),
    _task('t-data', '整理实验数据', '大学物理', 20, _at(tomorrow, '22:00')),
    _task('t-aid', '助学金申请', '学工通知', 30, _at(tomorrow, '18:00')),
    _task(
      't-proof',
      '公式推导',
      '线性代数',
      90,
      _at(today.add(const Duration(days: 4)), '23:59'),
    ),
    _task('t-review', '复习线性代数', '线性代数', 90, null, kind: 'study'),
    {
      ..._task(
        'exam-physics',
        '大学物理 期中考试',
        '大学物理',
        0,
        _at(tomorrow, '09:00'),
        kind: 'exam',
      ),
      'location': 'C102',
    },
    {
      ..._task(
        'exam-linear',
        '线性代数 期中考试',
        '线性代数',
        0,
        _at(today.add(const Duration(days: 4)), '09:00'),
        kind: 'exam',
      ),
      'location': 'A301',
    },
  ];

  List<Map<String, dynamic>> get blocks => [
    for (final e in entries.where((e) => e['resource_type'] == 'plan'))
      {
        'id': e['resource_id'],
        'item_id': e['resource_id'] == 'b-data' ? 't-data' : 't-review',
        'title': e['title'],
        'start_at': e['start_at'],
        'end_at': e['end_at'],
        'minutes': e['resource_id'] == 'b-data' ? 20 : 90,
        'status': 'active',
        'version': 1,
      },
  ];

  Map<String, dynamic> get opportunity => {
    'item_id': 't-data',
    'title': '整理实验数据',
    'target_minutes': 20,
    'remaining_minutes': 20,
    'already_planned_minutes': 0,
    'start_at': _at(today, '13:20'),
    'end_at': _at(today, '14:00'),
    'latest_start_at': _at(today, '13:40'),
    'before_kind': 'course',
  };

  List<Map<String, dynamic>> _on(DateTime day) =>
      entries.where((e) => '${e['start_at']}'.startsWith(_d(day))).toList();

  Map<String, dynamic> get hub {
    final valid = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String();
    final first = monday.subtract(const Duration(days: 63));
    return {
      'semester_id': 'promo',
      'semester': semester,
      'revision': 1,
      'valid_until': valid,
      'courses': courses,
      'items': items,
      'exams': items.where((i) => i['kind'] == 'exam').toList(),
      'weeks': [
        for (var w = 1; w <= 20; w++)
          () {
            final start = first.add(Duration(days: (w - 1) * 7));
            final end = start.add(const Duration(days: 6));
            bool inWeek(Map<String, dynamic> i) {
              final at = '${i['anchor_at'] ?? ''}';
              return at.isNotEmpty &&
                  at.compareTo(_d(start)) >= 0 &&
                  at.compareTo('${_d(end)}T99') < 0;
            }

            return {
              'week': w,
              'start_date': _d(start),
              'end_date': _d(end),
              'items': items.where(inWeek).toList(),
              'exams': items
                  .where((i) => i['kind'] == 'exam' && inWeek(i))
                  .toList(),
              'deadlines': [],
              'events': [],
              'changes': [],
            };
          }(),
      ],
      'changes': [],
    };
  }

  Future<ResponseBody> respond(RequestOptions r) async {
    final uri = Uri.parse(r.path);
    final path = uri.path;
    final q = {
      ...uri.queryParameters,
      for (final e in r.queryParameters.entries) e.key: '${e.value}',
    };
    ResponseBody missing() {
      unexpectedRequests.add('${r.method} ${r.path}');
      return body({'message': '宣传渲染未模拟此请求'}, 501);
    }

    if (r.method != 'GET') return missing();
    if (path == '/api/v1/reminders') {
      return body({'owner_id': 'promo_demo', 'reminders': []});
    }
    if (path.startsWith('/api/v1/items/')) {
      final id = path.split('/items/').last.split('?').first;
      final found = items.where((i) => i['id'] == id).firstOrNull;
      return found == null ? missing() : body(found);
    }
    if (path == '/api/v1/semesters/promo/items') {
      return body({'revision': 1, 'items': items});
    }
    if (path == '/api/v1/semesters/promo/courses') return body(courses);
    if (path == '/api/v1/semesters/promo/plans') {
      return body({
        'semester_id': 'promo',
        'revision': 1,
        'blocks': blocks,
        'invalid_blocks': [],
      });
    }
    if (path == '/api/v1/semesters/promo/risk') {
      final computed = DateTime.now().toUtc();
      return body({
        'semester_id': 'promo',
        'revision': 1,
        'computed_at': computed.toIso8601String(),
        'valid_until': computed.add(const Duration(hours: 1)).toIso8601String(),
        'items': [],
      });
    }
    if (path == '/api/v1/semesters/promo/calendar') {
      final from = q['from_date'] ?? '', to = q['to_date'] ?? '9';
      return body({
        'semester_id': 'promo',
        'revision': 1,
        'from_date': from,
        'to_date': to,
        'entries': entries.where((e) {
          final day = '${e['start_at']}'.substring(0, 10);
          return day.compareTo(from) >= 0 && day.compareTo(to) <= 0;
        }).toList(),
        'undated': [],
      });
    }
    if (path == '/api/v1/semesters/promo/day-brief') {
      final day = DateTime.parse(q['day'] ?? _d(today));
      return body({
        'semester_id': 'promo',
        'revision': 1,
        'date': q['day'] ?? _d(today),
        'valid_until': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'entries': _on(day),
        'next_day': {'entries': _on(day.add(const Duration(days: 1)))},
        'suggestions': [],
        'study_opportunity': arranged ? null : opportunity,
      });
    }
    if (path == '/api/v1/semesters/promo/hub') return body(hub);
    if (path == '/api/v1/agent/threads/promo') {
      final meetingAt = DateTime.parse(
        _at(tomorrow, '15:00'),
      ).toUtc().toIso8601String();
      return body({
        'semester_id': 'promo',
        'runs': [
          {
            'id': 'promo-run',
            'status': 'needs_confirmation',
            'text': '大家明天下午三点到我办公室开会 @所有人',
            'answer': '整理出 1 项日程，确认后保存。',
            'cards': [],
            'preview': {
              'kind': 'item',
              'action': 'create',
              'token': 'promo-preview',
              'provided_fields': ['title', 'time', 'location'],
              'after': {
                'title': '开会',
                'kind': 'event',
                'certainty': 'formal',
                'time': {'at': meetingAt, 'meaning': 'start'},
                'location': '发布者办公室',
              },
            },
          },
        ],
      });
    }
    if (path == '/api/v1/semesters/promo/timetable') {
      return body({'revision': 1, 'events': courses});
    }
    return missing();
  }

  AppController controller() {
    final api = SemesterApi(baseUrl: 'https://promo.invalid')
      ..session = account('promo_demo');
    api.dio.httpClientAdapter = ControlledTransport(respond);
    return AppController(api, MemoryStore(), clearSchoolSession: () async {})
      ..ready = true
      ..semester = semester
      ..semesters = [semester]
      ..week = 10
      ..events = courses
      ..savedWeeks = {
        'promo/10': {'revision': 1, 'events': courses},
      };
  }
}

Future<void> _shot(WidgetTester tester, String name, {double ratio = 4}) async {
  if (_out == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(preview.captureKey),
  );
  final shadows = debugDisableShadows;
  void repaint(RenderObject node) {
    node.markNeedsPaint();
    node.visitChildren(repaint);
  }

  try {
    debugDisableShadows = false;
    repaint(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: ratio);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_out!).create(recursive: true);
        await File('$_out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  } finally {
    debugDisableShadows = shadows;
  }
}

const _probe = [
  '确认添加',
  '暂不添加',
  '大家明天下午三点到我办公室开会',
  '添加到日程',
  '安排这项',
  '课前空档',
  '整理实验数据',
  '20 分钟',
  '20分钟',
  '下一节',
  '软件工程',
  '开会',
  '组会',
  '概率论',
  '复习线代',
  '大学物理',
  '提交实验报告',
  '第10周',
  '今日日程',
];

Future<void> _rects(WidgetTester tester, String name) async {
  if (_out == null) return;
  final out = <String, List<List<double>>>{};
  for (final text in _probe) {
    final rects = <List<double>>[];
    for (final e in find.textContaining(text).evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      rects.add(
        [
          r.left,
          r.top,
          r.width,
          r.height,
        ].map((v) => (v * 10).round() / 10).toList(),
      );
    }
    if (rects.isNotEmpty) out[text] = rects;
  }
  await tester.runAsync(
    () => File(
      '$_out/$name.json',
    ).writeAsString(const JsonEncoder.withIndent(' ').convert(out)),
  );
}

Future<void> _render(
  WidgetTester tester,
  PromoWorld world,
  Widget Function(AppController app, ItemsController items) page,
  String name, {
  double height = 844,
  int hour = 13,
  int minute = 18,
  bool evening = false,
  bool hiRes = false,
}) async {
  final previousClock = debugSchoolClock;
  final app = world.controller();
  ItemsController? items;
  debugSchoolClock = () => DateTime.utc(
    world.today.year,
    world.today.month,
    world.today.day,
    hour,
    minute,
  );
  try {
    items = (await tester.runAsync(() => preview.sampleItems(app)))!;
    await tester.runAsync(
      () => app.cache.write('home-layout:${app.user['id']}:promo', {
        'enabled': ['deadlines', 'plans', 'windows', 'exams', 'week_heatmap'],
      }),
    );
    await preview.mount(tester, page(app, items), width: 390, height: height);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: name);
    expect(world.unexpectedRequests, isEmpty, reason: '$name 请求必须有明确的合成响应');
    await _shot(tester, name, ratio: hiRes ? 8 : 4);
    await _rects(tester, name);
    if (evening) {
      // 周课表区域最高 660，内部滚动；滚到底拿到晚间节次（调课镜头需要 19:00 一带）。
      for (final e
          in find.byKey(const ValueKey('schedule-grid-scroll')).evaluate()) {
        final scrollable = find
            .descendant(
              of: find.byWidget(e.widget),
              matching: find.byType(Scrollable),
            )
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent);
      }
      await tester.pumpAndSettle();
      await _shot(tester, '$name-evening');
      await _rects(tester, '$name-evening');
    }
    expect(tester.takeException(), isNull, reason: name);
    expect(world.unexpectedRequests, isEmpty, reason: '$name 请求必须有明确的合成响应');
  } finally {
    try {
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugSchoolClock = previousClock;
      items?.dispose();
      app.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadPreviewFonts);

  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  final today = DateTime(now.year, now.month, now.day);

  testWidgets('promo · failed render restores its clock and controllers', (
    t,
  ) async {
    final originalClock = debugSchoolClock;
    DateTime previousClock() => DateTime.utc(2026, 1, 1);
    debugSchoolClock = previousClock;
    AppController? capturedApp;
    ItemsController? capturedItems;
    Object? failure;
    try {
      try {
        await _render(t, PromoWorld(today), (app, items) {
          capturedApp = app;
          capturedItems = items;
          throw StateError('promo cleanup check');
        }, 'cleanup');
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<StateError>());
      expect(debugSchoolClock, same(previousClock));
      expect(() => capturedApp!.addListener(() {}), throwsFlutterError);
      expect(() => capturedItems!.addListener(() {}), throwsFlutterError);
    } finally {
      debugSchoolClock = originalClock;
    }
  });

  testWidgets('promo · today', (t) async {
    final w = PromoWorld(today);
    Widget page(AppController a, ItemsController i) =>
        ShellPage(controller: a, items: i, initialTab: 0);
    await _render(t, w, page, 'today');
    await _render(t, w, page, 'today-long', height: 1900);
    await _render(
      t,
      PromoWorld(today, arranged: true),
      page,
      'today-arranged-long',
      height: 1900,
    );
  });

  testWidgets('promo · sky time-lapse', (t) async {
    final w = PromoWorld(today);
    Widget page(AppController a, ItemsController i) =>
        ShellPage(controller: a, items: i, initialTab: 0);
    for (final (h, m) in [
      (23, 40),
      (4, 40),
      (5, 20),
      (5, 50),
      (6, 20),
      (6, 50),
      (7, 30),
      (8, 30),
      (10, 0),
      (11, 30),
      (13, 18),
    ]) {
      await _render(
        t,
        w,
        page,
        'sky-${h.toString().padLeft(2, '0')}${m.toString().padLeft(2, '0')}',
        hour: h,
        minute: m,
      );
    }
    await _render(t, w, page, 'sky-2340-hi', hour: 23, minute: 40, hiRes: true);
    await _render(t, w, page, 'sky-1318-hi', hour: 13, minute: 18, hiRes: true);
  });

  testWidgets('promo · schedule', (t) async {
    Widget page(AppController a, ItemsController i) =>
        ShellPage(controller: a, items: i, initialTab: 1);
    await _render(
      t,
      PromoWorld(today),
      page,
      'schedule',
      height: 1320,
      evening: true,
    );
    await _render(
      t,
      PromoWorld(today, meeting: true),
      page,
      'schedule-meeting',
      height: 1320,
      evening: true,
    );
    await _render(
      t,
      PromoWorld(today, meeting: true, arranged: true),
      page,
      'schedule-arranged',
      height: 1320,
      evening: true,
    );
    await _render(
      t,
      PromoWorld(today, meeting: true, arranged: true, swapped: true),
      page,
      'schedule-swapped',
      height: 1320,
      evening: true,
    );
  });

  testWidgets('promo · tasks & semester', (t) async {
    final w = PromoWorld(today);
    await _render(
      t,
      w,
      (a, i) => ShellPage(controller: a, items: i, initialTab: 2),
      'tasks',
      height: 1200,
    );
    await _render(
      t,
      w,
      (a, i) => ShellPage(controller: a, items: i, initialTab: 3),
      'semester',
      height: 1200,
    );
  });

  testWidgets('promo · assistant', (t) async {
    final w = PromoWorld(today);
    await _render(
      t,
      w,
      (a, i) => AgentPage(
        controller: i,
        semester: a.semester!,
        initialThreadId: 'promo',
      ),
      'assistant',
    );
  });
}
