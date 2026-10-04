import 'package:semester_os/ui/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/core/api.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/features/items/items_view.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'api_session_test.dart' show ControlledTransport, account, body;
import 'controller_test.dart' show MemoryStore;
import 'reminder_sync_test.dart' show FakeNotifications;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

const semester = {'id': 'sample', 'name': '示例学期', 'total_weeks': 20};

class Fixture {
  final api = SemesterApi()..session = account('preview_demo');
  final saved = <Map<String, dynamic>>[];
  late final ItemsController c;
  Map<String, dynamic>? submitted;
  Fixture() {
    c = ItemsController(api, MemoryStore(), ReminderSync(FakeNotifications()));
    api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/courses')) return body([]);
      if (r.path.endsWith('/reminders')) {
        return body({
          'owner_id': 'preview_demo',
          'reminders': [],
          'synced_at': '2026-09-20T00:00:00Z',
        });
      }
      if (r.method == 'POST' && r.path.endsWith('/items')) {
        submitted = Map<String, dynamic>.from(r.data);
        final item = {
          ...submitted!,
          'id': 'created',
          'version': 1,
          'lifecycle': 'active',
          'course_title': '',
          'created_at': '2026-09-20T00:00:00Z',
          'anchor_at': submitted!['time']['at'],
          'reminders': submitted!['reminders'] ?? [],
        };
        saved.add(item);
        return body(item, 201);
      }
      if (r.path.endsWith('/items/created')) return body(saved.last);
      return body({'items': saved, 'revision': 1});
    });
  }
}

Future<void> openForm(
  WidgetTester tester,
  Fixture f, {
  Map<String, dynamic>? candidate,
}) async {
  await tester.runAsync(() => f.c.bind('sample'));
  await mount(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ItemFormPage(
                controller: f.c,
                semester: semester,
                candidate: candidate,
              ),
            ),
          ),
          child: const Text('打开录入'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开录入'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('保存'),
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(find.text('保存'));
    // bind() initialises the platform queue in the real async zone, as on device.
    // Let its chained I/O complete before asserting the resulting navigation.
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets(
    'collapsed invalid effort still shows a field error and never submits',
    (tester) async {
      final f = Fixture();
      await openForm(tester, f);
      await tester.enterText(find.byKey(const Key('item-title')), '测试任务');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('安排学习时间'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('安排学习时间'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('item-minutes')), '1.5');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('安排学习时间'));
      await tester.tap(find.text('安排学习时间'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(f.submitted, isNull);
      expect(find.text('预计耗时请填写整数分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'lightweight manual task saves without inventing date effort or reminders',
    (tester) async {
      final f = Fixture();
      await openForm(tester, f);
      await tester.enterText(find.byKey(const Key('item-title')), '整理实验材料');
      await tester.pumpAndSettle();
      await capture(tester, 'item-form');
      await save(tester);
      expect(f.submitted!['remaining_minutes'], isNull);
      expect(f.submitted!['time']['precision'], 'unknown');
      expect(f.submitted!['reminders'], isEmpty);
      expect(
        find.text('打开录入'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'AI deadline and effort are reviewed by the explicit save action',
    (tester) async {
      final f = Fixture();
      await openForm(
        tester,
        f,
        candidate: {
          'id': 'synthetic-candidate',
          'inferred_fields': ['time'],
          'questions': ['请核对通知年份'],
          'item': {
            'kind': 'assignment',
            'title': 'Java实验报告',
            'time': {'precision': 'exact', 'at': '2099-09-25T23:59:00+08:00'},
            'remaining_minutes': 180,
            'source_text': '9月25日23:59前交Java报告，预计3小时',
          },
        },
      );
      expect(find.text('需核对：请核对通知年份'), findsOneWidget);
      expect(f.submitted, isNull);
      await save(tester);
      expect(f.submitted!['remaining_minutes'], 180);
      expect(f.submitted!['time']['at'], '2099-09-25T23:59:00+08:00');
      expect(f.submitted!['candidate_id'], 'synthetic-candidate');
      await mount(
        tester,
        ItemDetailPage(controller: f.c, semester: semester, id: 'created'),
      );
      expect(
        find.byTooltip('编辑事项'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'item-detail');
      await mount(
        tester,
        Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ItemsView(controller: f.c, onCreate: () {}, onOpen: (_) {}),
            ],
          ),
        ),
      );
      expect(find.text('Java实验报告'), findsOneWidget);
      await capture(tester, 'items-list');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
  testWidgets(
    'exam lead time creates one reminder without inventing a purpose and large text remains usable',
    (tester) async {
      Map<String, dynamic>? selected;
      await mount(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await editReminder(context, kind: 'exam');
              },
              child: const Text('设置提醒'),
            ),
          ),
        ),
        width: 360,
        textScale: 2,
      );
      await tester.tap(find.text('设置提醒'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(AppPickerField<int>));
      await tester.tap(find.byType(AppPickerField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提前14天').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('确认这条提醒'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('确认这条提醒'));
      await tester.pumpAndSettle();
      expect(selected!['lead_minutes'], 20160);
      expect(selected!['purpose'], 'item');
      expect(tester.takeException(), isNull);
    },
  );
}
