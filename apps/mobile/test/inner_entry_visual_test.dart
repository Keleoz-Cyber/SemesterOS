import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/accounts/auth_page.dart';
import 'package:semester_os/features/semester/semester_page.dart';
import 'package:semester_os/features/import/manual_page.dart';
import 'package:semester_os/features/import/school_picker.dart';
import 'package:semester_os/features/import/preview.dart';
import 'package:semester_os/features/items/capture_page.dart';
import 'package:semester_os/features/media/media_capture_page.dart';
import 'package:semester_os/features/media/source_view.dart';
import 'package:semester_os/features/media/drafts.dart';
import 'package:semester_os/features/operations/operation_page.dart';
import 'package:semester_os/features/timetable/semester_view.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'media_flow_test.dart' show FakeMedia, setup, source;
import 'operation_flow_test.dart' show operation;
import 'ui_polish_test.dart'
    show sampleController, mount, capture, loadPreviewFonts;

// ImportPage is intentionally absent: its real school WebView requires a native
// platform view/session. We capture the real picker and real import confirmation,
// never a simulated school login page. MediaInput is FakeMedia; no microphone runs.
const _notice =
    '关于课程实验报告提交的通知\n'
    '请于9月25日23:59前提交Java实验报告。报告包含实验目的、实现过程、测试结果和问题分析。\n'
    '请以“学号_姓名_实验三”命名文件，并提交至课程平台。预计需要3小时，提交前请检查附件。\n'
    '本周五下午的答疑地点调整为教学楼B204，其他安排不变。';
const _semester = {'id': 's', 'name': '2026—2027学年第一学期', 'total_weeks': 20};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, Widget page, double scale) async {
  await _launcher(
    tester,
    scale,
    (context) =>
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => page)),
  );
}

Future<void> _launcher(
  WidgetTester tester,
  double scale,
  void Function(BuildContext) launch,
) async {
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => launch(context),
          child: const Text('打开内部页'),
        ),
      ),
    ),
    textScale: scale,
    width: 390,
  );
  await ioTap(tester, find.text('打开内部页'));
  await _settle(tester);
}

Future<void> _to(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      350,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _edge(WidgetTester tester, {bool bottom = true}) async {
  final scroll = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    final position = tester.state<ScrollableState>(scroll).position;
    position.jumpTo(
      bottom ? position.maxScrollExtent : position.minScrollExtent,
    );
    await tester.pumpAndSettle();
    if (!bottom || (position.maxScrollExtent - position.pixels).abs() < 1) {
      break;
    }
  }
}

Future<void> _shot(WidgetTester tester, String page, String scale) async {
  expect(tester.takeException(), isNull);
  await capture(tester, 'inner-entry-$page-$scale');
  expect(tester.takeException(), isNull);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppField && widget.decoration.labelText == label,
);

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);

  for (final scale in [1.0, 1.6]) {
    final size = scale == 1 ? 'normal' : 'large';

    testWidgets('inner authentication login registration recovery $size', (
      tester,
    ) async {
      final c = sampleController();
      await _open(tester, AuthPage(controller: c), scale);
      await _shot(tester, 'auth-login-top', size);
      await _edge(tester);
      await _shot(tester, 'auth-login-submit', size);
      await _to(tester, find.text('注册'));
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      await _edge(tester, bottom: false);
      await _shot(tester, 'auth-register-top', size);
      await _edge(tester);
      await _shot(tester, 'auth-register-submit', size);
      await _to(tester, find.text('使用恢复码找回密码'));
      await tester.tap(find.text('使用恢复码找回密码'));
      await tester.pumpAndSettle();
      await _edge(tester, bottom: false);
      await _shot(tester, 'auth-recovery-top', size);
      await _edge(tester);
      expect(find.text('账户恢复码'), findsOneWidget);
      await _shot(tester, 'auth-recovery-submit', size);
      await _close(tester);
      c.dispose();
    });

    testWidgets('inner semester calendar interactive periods and batch $size', (
      tester,
    ) async {
      final c = sampleController();
      await _open(tester, SemesterPage(controller: c), scale);
      await _shot(tester, 'semester-calendar', size);
      await _to(tester, find.text('08:00'));
      await _shot(tester, 'semester-periods', size);
      await tester.tap(find.text('08:00'));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await _shot(tester, 'semester-time-picker', size);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await _to(tester, find.text('查看全部 10 节'));
      await tester.tap(find.text('查看全部 10 节'));
      await tester.pumpAndSettle();
      await _to(tester, find.text('收起节次'));
      await _shot(tester, 'semester-periods-expanded', size);
      await _to(tester, find.text('批量编辑节次'));
      await tester.tap(find.text('批量编辑节次'));
      await tester.pumpAndSettle();
      await _to(tester, _field('节次与时间（示例，可修改）'));
      await _shot(tester, 'semester-periods-batch', size);
      await _edge(tester);
      expect(
        tester
            .widget<FButton>(find.widgetWithText(FButton, '确认创建学期'))
            .onPress,
        isNull,
      );
      await _shot(tester, 'semester-confirm', size);
      await _close(tester);
      c.dispose();
    });

    testWidgets('inner manual course identity timetable and footer $size', (
      tester,
    ) async {
      final c = sampleController();
      await _open(tester, ManualPage(controller: c), scale);
      await tester.enterText(
        find.byKey(const Key('course-title')),
        '计算机网络课程设计与实验',
      );
      await _to(tester, _field('教师（可留空）'));
      await tester.enterText(_field('教师（可留空）'), '王老师');
      await _to(tester, _field('上课地点（可留空）'));
      await tester.enterText(_field('上课地点（可留空）'), '教学楼B204计算机实验室');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _edge(tester, bottom: false);
      await _shot(tester, 'manual-identity', size);
      await _to(tester, _field('周次'));
      await tester.enterText(_field('周次'), '1-16周(单)');
      await _to(tester, _field('节次'));
      await tester.enterText(_field('节次'), '1-2');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _edge(tester);
      expect(find.text('核对课程信息'), findsOneWidget);
      await _shot(tester, 'manual-timetable-confirm', size);
      await _close(tester);
      c.dispose();
    });

    testWidgets('inner school picker matched and manual fallback $size', (
      tester,
    ) async {
      await _open(
        tester,
        SchoolPickerPage(onSelect: () {}, onManual: () {}),
        scale,
      );
      await _shot(tester, 'schools-list', size);
      await _edge(tester);
      await _shot(tester, 'schools-manual', size);
      await _to(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), '未适配学校');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _edge(tester, bottom: false);
      await _shot(tester, 'schools-no-match', size);
      await _close(tester);
    });

    testWidgets(
      'inner real import sheet course details and confirmation $size',
      (tester) async {
        final c = sampleController();
        final courses = [
          for (var i = 0; i < 4; i++)
            {
              'title': ['高等数学', '数据结构与算法实验', '大学英语读写', '计算机网络课程设计'][i],
              'teacher': '课程教师',
              'location': '教学楼B20${i + 1}',
              'weekday': i + 1,
              'weeks': List.generate(16, (w) => w + 1),
              'sections': [1, 2],
            },
        ];
        final previous = c.api.dio.httpClientAdapter as ControlledTransport;
        var saves = 0;
        c.api.dio.httpClientAdapter = ControlledTransport((request) async {
          if (request.path.endsWith('/imports')) {
            return body({
              'id': 'preview',
              'new_count': 4,
              'unchanged_count': 0,
              'changed_count': 0,
              'base_revision': 1,
            }, 201);
          }
          if (request.path.endsWith('/apply')) saves++;
          return previous.respond(request);
        });
        await _launcher(tester, scale, (context) {
          showImportPreview(
            context,
            c,
            courses,
            'haut_webview',
            sourceTerm: '2026—2027学年第一学期',
          );
        });
        await _shot(tester, 'import-preview-top', size);
        await _edge(tester);
        expect(find.text('确认保存课表'), findsOneWidget);
        expect(saves, 0);
        await _shot(tester, 'import-preview-confirm', size);
        await _close(tester);
        c.dispose();
      },
    );

    testWidgets('inner text capture restored notice and reference $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      await tester.runAsync(
        () => CaptureDrafts(f.c.cache, 'preview', () => true).save('text:s', {
          'text': _notice,
          'reference_at': '2026-09-20T00:00:00Z',
        }),
      );
      await _open(
        tester,
        CapturePage(controller: f.c, semester: _semester),
        scale,
      );
      await _shot(tester, 'capture-notice', size);
      await _edge(tester);
      expect(find.text('让AI整理'), findsOneWidget);
      await _shot(tester, 'capture-reference-actions', size);
      await _close(tester);
      f.c.dispose();
    });

    for (final kind in ['image', 'audio']) {
      for (final compact in [false, true]) {
        final variant = compact ? 'assistant' : 'full';
        testWidgets('inner media $kind $variant transcript and actions $size', (
          tester,
        ) async {
          final f = await setup(tester);
          final s = {
            ...source('a'),
            'kind': kind,
            'text': _notice,
            'original_text': _notice,
          };
          final previous = f.api.dio.httpClientAdapter as ControlledTransport;
          f.api.dio.httpClientAdapter = ControlledTransport((request) async {
            if (request.path.endsWith('/sources/a')) return body(s);
            if (request.path.endsWith('/sources')) return body([s]);
            return previous.respond(request);
          });
          await tester.runAsync(
            () => CaptureDrafts(f.c.cache, 'preview', () => true)
                .save('media:s:$kind', {
                  'kind': kind,
                  'local': null,
                  'source': s,
                  'text': _notice,
                  'key': 'inner-media-preview',
                  'reference_at': s['reference_at'],
                  'dirty': true,
                }),
          );
          await _open(
            tester,
            MediaCapturePage(
              controller: f.c,
              semester: _semester,
              kind: kind,
              input: FakeMedia(),
              returnSource: compact,
            ),
            scale,
          );
          await _shot(tester, 'media-$kind-$variant-top', size);
          await _to(tester, find.byType(TextField));
          await _shot(tester, 'media-$kind-$variant-transcript', size);
          expect(find.text(compact ? '发送' : '整理日程'), findsOneWidget);
          await tester.tap(find.byTooltip('更多操作'));
          await tester.pumpAndSettle();
          await _shot(tester, 'media-$kind-$variant-actions', size);
          await _close(tester);
          f.c.dispose();
        });
      }
    }

    testWidgets('inner source retained document with deleted file $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var contentRequests = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/sources/a')) {
          return body({
            ...source('a'),
            'file_deleted': true,
            'text': _notice,
            'original_text': '原始识别稿：\n$_notice\n请以课程平台最终通知为准。',
          });
        }
        if (request.path.endsWith('/content')) contentRequests++;
        return previous.respond(request);
      });
      await _open(tester, SourceViewPage(controller: f.c, id: 'a'), scale);
      expect(find.text('原文件已删除，以下识别文字与历史仍保留'), findsOneWidget);
      await _shot(tester, 'source-deleted-file-top', size);
      await _edge(tester);
      expect(contentRequests, 0);
      await _shot(tester, 'source-original-transcript', size);
      await _close(tester);
      f.c.dispose();
    });

    testWidgets('inner operation parsed change remains a preview $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      await tester.runAsync(() => f.c.bind('s'));
      final preview = operation(f);
      final previous = f.api.dio.httpClientAdapter as ControlledTransport;
      var saves = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/operations')) return body([]);
        if (request.path.endsWith('/operations/parse')) {
          return body(preview, 201);
        }
        if (request.path.endsWith('/apply')) saves++;
        return previous.respond(request);
      });
      await _open(
        tester,
        OperationPage(controller: f.c, initialText: preview['source_text']),
        scale,
      );
      await _shot(tester, 'operation-top', size);
      await _to(tester, find.text('确认保存修改'));
      await _shot(tester, 'operation-confirm', size);
      await _edge(tester);
      expect(saves, 0);
      await _shot(tester, 'operation-bottom', size);
      await _close(tester);
      f.c.dispose();
    });

    testWidgets('inner semester management choices and import actions $size', (
      tester,
    ) async {
      final c = sampleController();
      final semesters = [
        {...c.semester!, 'name': '2026—2027学年第一学期'},
        {
          ...c.semester!,
          'id': 'previous',
          'name': '2025—2026学年第二学期',
          'first_monday': '2026-02-23',
        },
        {
          ...c.semester!,
          'id': 'older',
          'name': '2025—2026学年第一学期',
          'first_monday': '2025-09-01',
        },
      ];
      await _open(
        tester,
        Scaffold(
          appBar: AppBar(title: const Text('管理学期与课表')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SemesterView(
              semesters: semesters,
              current: semesters.first,
              onSelect: (_) {},
              onCreate: () {},
              onImport: () {},
              onManual: () {},
            ),
          ),
        ),
        scale,
      );
      await _shot(tester, 'semester-management-list', size);
      await _edge(tester);
      expect(find.text('重新导入教务课表'), findsOneWidget);
      await _shot(tester, 'semester-management-actions', size);
      await _close(tester);
      c.dispose();
    });
  }
}
