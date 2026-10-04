import 'package:semester_os/ui/app_controls.dart';
import 'package:semester_os/features/tags/tag_picker_field.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/ui/app_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/features/items/reminder_editor.dart';
import 'package:semester_os/features/items/reminder_settings.dart';
import 'package:semester_os/features/calendar/event_form.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'calendar_flow_test.dart' show semester;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

// Actual app widgets and controlled API responses. These are visual fixtures,
// not alternate implementations of any screen.
Map<String, dynamic> itemRecord() => {
  'id': 't',
  'semester_id': 's',
  'kind': 'assignment',
  'title': '完成实验报告与误差分析',
  'version': 1,
  'lifecycle': 'active',
  'course_title': '大学物理实验',
  'course_id': null,
  'time': {'precision': 'exact', 'at': '2026-10-02T18:00:00+08:00'},
  'anchor_at': '2026-10-02T18:00:00+08:00',
  'certainty': 'formal',
  'priority': 'normal',
  'remaining_minutes': 90,
  'splittable': true,
  'start_policy': 'now',
  'category_id': 'study',
  'tags': [
    {'name': '实验报告'},
    {'name': '误差分析'},
  ],
  'location': '实验楼 B302',
  'notes': '补充测量数据表，说明误差来源，并检查参考文献格式。',
  'source_text': '请在10月2日18:00前提交电子版实验报告。报告应包括原始测量记录、计算过程和误差分析。课堂展示材料与报告一并提交。',
  'created_at': '2026-09-26T10:30:00+08:00',
  'reminders': [
    {
      'id': 'r1',
      'version': 1,
      'mode': 'relative',
      'lead_minutes': 1440,
      'purpose': 'item',
      'enabled': true,
      'schedule_state': 'scheduled',
      'trigger_at': '2026-10-01T18:00:00+08:00',
    },
    {
      'id': 'r2',
      'version': 1,
      'mode': 'absolute',
      'lead_minutes': null,
      'purpose': 'check_notice',
      'enabled': true,
      'schedule_state': 'needs_review',
      'trigger_at': '2026-09-30T09:00:00+08:00',
    },
  ],
};

Map<String, dynamic> eventRecord() => {
  'id': 'e',
  'semester_id': 's',
  'version': 1,
  'title': '课题组阶段汇报',
  'lifecycle': 'active',
  'certainty': 'formal',
  'time': {
    'precision': 'exact',
    'at': '2026-10-03T14:00:00+08:00',
    'end_at': '2026-10-03T15:30:00+08:00',
  },
  'location': '科研楼 6412 会议室',
  'category_id': 'research',
  'tags': [
    {'name': '课题组'},
    {'name': '阶段汇报'},
  ],
  'source_text': '本周课题组汇报安排在10月3日14:00—15:30，地点为科研楼6412。请准备实验结果、当前问题和下一阶段计划。',
  'reminder_minutes': [30, 1440],
  'reminders': [
    {'mode': 'relative', 'lead_minutes': 30, 'schedule_state': 'scheduled'},
    {'mode': 'relative', 'lead_minutes': 1440, 'schedule_state': 'scheduled'},
  ],
};

Future<ScheduleFixture> fixture(WidgetTester tester) async {
  final f = ScheduleFixture()..item = itemRecord();
  final original = f.api.dio.httpClientAdapter as ControlledTransport;
  f.api.dio.httpClientAdapter = ControlledTransport((r) async {
    if (r.path.endsWith('/semesters')) return body([semester()]);
    if (r.path.endsWith('/items/t')) return body(f.item);
    if (r.path.endsWith('/events/e')) return body(eventRecord());
    if (r.path.endsWith('/items/t/history')) {
      return body([
        {
          'reason': '根据实验课通知补充地点',
          'created_at': '2026-09-27T09:00:00+08:00',
          'snapshot': f.item,
        },
      ]);
    }
    return original.respond(r);
  });
  await tester.runAsync(() => f.c.bind('s'));
  return f;
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

Finder verticalScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .last;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    240,
    scrollable: verticalScroll(),
    maxScrolls: 40,
  );
  await tester.pumpAndSettle();
}

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  await capture(tester, name);
  expect(tester.takeException(), isNull, reason: '$name after capture');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadPreviewFonts);
  testWidgets('tag picker cancels drafts and preserves one name per value', (
    tester,
  ) async {
    final f = await fixture(tester);
    final original = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/tags')) {
        return body({
          'owner_id': 'preview',
          'tags': [
            {'name': '组会'},
          ],
        });
      }
      return original.respond(r);
    });
    var values = <String>['实验报告'];
    var changes = 0;
    await mount(
      tester,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, rebuild) => Padding(
            padding: const EdgeInsets.all(20),
            child: TagPickerField(
              controller: f.c,
              values: values,
              onChanged: (next) => rebuild(() {
                values = next;
                changes++;
              }),
            ),
          ),
        ),
      ),
      width: 375,
      textScale: 1.6,
    );
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组会'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(values, ['实验报告']);
    expect(changes, 0);
    await tester.tap(find.text('实验报告'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-name-input')), '设计，报告');
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加“设计，报告”'));
    await tester.pumpAndSettle();
    await shot(tester, 'tag-picker-375-large');
    await tester.tap(find.text('确认标签'));
    await tester.pumpAndSettle();
    expect(values, ['实验报告', '设计，报告']);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });
  testWidgets('fixed item save shows missing time even from the form bottom', (
    tester,
  ) async {
    final f = await fixture(tester);
    var writes = 0;
    final transport = f.api.dio.httpClientAdapter as ControlledTransport;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.method == 'POST' && r.path.endsWith('/items')) writes++;
      return transport.respond(r);
    });
    final incomplete = {
      ...itemRecord(),
      'time': {'precision': 'exact'},
    };
    await mount(
      tester,
      ItemFormPage(
        controller: f.c,
        semester: semester(),
        candidate: {'item': incomplete},
      ),
      textScale: 1.6,
    );
    await reveal(tester, find.text('更多设置'));
    await tester.tap(find.text('更多设置'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('来源原文（可留空）'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请先选择日期').hitTestable(), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets(
    'fixed event save shows missing name from below the title field',
    (tester) async {
      final f = await fixture(tester);
      var writes = 0;
      final transport = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.method == 'POST' && r.path.endsWith('/events')) writes++;
        return transport.respond(r);
      });
      await mount(
        tester,
        EventFormPage(controller: f.c, semester: semester()),
        textScale: 1.6,
      );
      await settle(tester);
      await reveal(tester, find.text('分类与更多设置'));
      await tester.tap(find.text('分类与更多设置'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('通知原文（选填）'));
      await tester.tap(find.widgetWithText(FButton, '添加日程'));
      await tester.pumpAndSettle();
      expect(find.text('请填写日程名称').hitTestable(), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  for (final scale in [1.0, 1.6]) {
    final suffix = scale.toStringAsFixed(1);
    testWidgets('inner item detail visual $suffix', (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        ItemDetailPage(controller: f.c, semester: semester(), id: 't'),
        width: scale > 1 ? 320 : 390,
        textScale: scale,
      );
      await settle(tester);
      expect(find.text('完成实验报告与误差分析'), findsOneWidget);
      expect(find.text('还需 1小时30分钟'), findsOneWidget);
      await shot(tester, 'inner-item-detail-$suffix');
      await reveal(tester, find.text('提醒 · 2条'));
      await tester.tap(find.text('提醒 · 2条'));
      await tester.pumpAndSettle();
      await shot(tester, 'inner-item-detail-reminders-$suffix');
      await tester.tap(find.byTooltip('系统通知设置'));
      await settle(tester);
      expect(find.byType(ReminderSettingsPage), findsOneWidget);
      await shot(tester, 'inner-item-reminder-settings-$suffix');
      Navigator.of(tester.element(find.byType(ReminderSettingsPage))).pop();
      await settle(tester);
      await reveal(tester, find.text('通知原文'));
      await tester.tap(find.text('通知原文'));
      await tester.pumpAndSettle();
      await shot(tester, 'inner-item-detail-source-$suffix');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('修改历史'));
      await settle(tester);
      await reveal(tester, find.text('根据实验课通知补充地点'));
      expect(find.text('根据实验课通知补充地点'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    for (final editing in [false, true]) {
      final mode = editing ? 'edit' : 'new';
      testWidgets('inner item form $mode visual $suffix', (tester) async {
        final f = await fixture(tester);
        await mount(
          tester,
          ItemFormPage(
            controller: f.c,
            semester: semester(),
            initial: editing ? itemRecord() : null,
            candidate: editing ? null : {'item': itemRecord()},
          ),
          textScale: scale,
        );
        expect(
          tester
              .widget<AppFormField>(find.byKey(const Key('item-title')))
              .controller!
              .text,
          '完成实验报告与误差分析',
        );
        expect(
          find.text(editing ? '保存修改' : '保存').hitTestable(),
          findsOneWidget,
        );
        await shot(tester, 'inner-item-form-$mode-$suffix');
        await reveal(tester, find.byKey(const Key('item-minutes')));
        expect(
          tester
              .widget<AppFormField>(find.byKey(const Key('item-minutes')))
              .controller!
              .text,
          '90',
        );
        await shot(tester, 'inner-item-form-$mode-work-$suffix');
        await reveal(tester, find.text('更多设置'));
        await tester.tap(find.text('更多设置'));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(const Key('item-tags')));
        expect(
          tester
              .widget<TagPickerField>(find.byKey(const Key('item-tags')))
              .values,
          ['实验报告', '误差分析'],
        );
        await shot(tester, 'inner-item-form-$mode-more-$suffix');
        if (editing) {
          await reveal(tester, find.byKey(const Key('item-change-reason')));
          final field = tester.widget<AppFormField>(
            find.byKey(const Key('item-change-reason')),
          );
          expect(
            field.validator?.call(''),
            isNull,
            reason: 'Changing a task does not require an explanation',
          );
        }
        await tester.pumpWidget(const SizedBox());
        f.c.dispose();
      });
    }

    for (final absolute in [false, true]) {
      final mode = absolute ? 'absolute' : 'relative';
      testWidgets('inner reminder $mode visual $suffix', (tester) async {
        Map<String, dynamic>? result;
        final initial = absolute
            ? <String, dynamic>{
                'mode': 'absolute',
                'trigger_at': '2099-10-02T09:00:00+08:00',
                'purpose': 'check_notice',
                'enabled': true,
                'version': 3,
              }
            : null;
        await mount(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await editReminder(
                      context,
                      kind: 'exam',
                      initial: initial,
                    );
                  },
                  child: const Text('设置提醒'),
                ),
              ),
            ),
          ),
          textScale: scale,
        );
        await tester.tap(find.text('设置提醒'));
        await tester.pumpAndSettle();
        expect(find.byType(ReminderEditor), findsOneWidget);
        await shot(tester, 'inner-reminder-$mode-$suffix');
        if (!absolute) {
          await reveal(tester, find.byType(AppPickerField<int>));
          await tester.tap(find.byType(AppPickerField<int>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('提前14天').last);
          await tester.pumpAndSettle();
        }
        await reveal(tester, find.text('确认这条提醒'));
        await shot(tester, 'inner-reminder-$mode-rule-$suffix');
        await tester.tap(find.text('确认这条提醒'));
        await tester.pumpAndSettle();
        expect(result?['mode'], mode);
        if (absolute) {
          expect(result?['trigger_at'], '2099-10-02T09:00:00+08:00');
          expect(result?['purpose'], 'check_notice');
          expect(result?['expected_version'], 3);
        } else {
          expect(result?['lead_minutes'], 20160);
          expect(result?['purpose'], 'item');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('inner event form visual $suffix', (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        EventFormPage(
          controller: f.c,
          semester: semester(),
          original: eventRecord(),
        ),
        textScale: scale,
      );
      await settle(tester);
      expect(find.text('课题组阶段汇报'), findsOneWidget);
      expect(find.text('保存修改').hitTestable(), findsOneWidget);
      await shot(tester, 'inner-event-form-$suffix');
      await reveal(tester, find.text('提醒'));
      expect(find.text('提前30分钟提醒'), findsOneWidget);
      await shot(tester, 'inner-event-form-reminders-$suffix');
      await reveal(tester, find.text('分类与更多设置'));
      await tester.tap(find.text('分类与更多设置'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('通知原文（选填）'));
      await shot(tester, 'inner-event-form-source-$suffix');
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });

    testWidgets('inner event detail visual $suffix', (tester) async {
      final f = await fixture(tester);
      await mount(
        tester,
        EventDetailPage(controller: f.c, semester: semester(), eventId: 'e'),
        textScale: scale,
      );
      await settle(tester);
      expect(find.text('课题组阶段汇报'), findsOneWidget);
      expect(find.textContaining('10月3日 · 周六'), findsOneWidget);
      final displayedTimes = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('event-when')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(
        displayedTimes,
        scale == 1.0 ? ['14:00—15:30'] : ['开始', '14:00', '结束', '15:30'],
      );
      expect(find.byTooltip('编辑日程').hitTestable(), findsOneWidget);
      await shot(tester, 'inner-event-detail-$suffix');
      await reveal(tester, find.text('提前30分钟'));
      await shot(tester, 'inner-event-detail-reminders-$suffix');
      await tester.tap(find.text('提前30分钟'));
      await settle(tester);
      expect(find.byType(ReminderEditor), findsOneWidget);
      expect(find.byType(EventFormPage), findsNothing);
      await shot(tester, 'inner-event-reminder-edit-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReminderEditor), findsNothing);
      await reveal(tester, find.text('通知原文'));
      final source = find.text(eventRecord()['source_text']);
      expect(source, findsNothing);
      await tester.tap(find.text('通知原文'));
      await tester.pumpAndSettle();
      await reveal(tester, source);
      await shot(tester, 'inner-event-detail-source-$suffix');
      expect(source.hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }
}
