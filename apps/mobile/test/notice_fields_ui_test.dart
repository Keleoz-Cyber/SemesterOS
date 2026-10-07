import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:semester_os/features/notices/notice_fields.dart';
import 'package:semester_os/features/calendar/event_form.dart';
import 'package:semester_os/features/items/item_form.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'calendar_flow_test.dart' show semester;
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show route, ioTap;
import 'ui_polish_test.dart' show loadPreviewFonts, mount, capture;

void main() {
  setUpAll(loadPreviewFonts);
  test(
    'repeated broad mentions are presentation-only and keep specific conditions',
    () {
      final original = {
        'recipient': '所有人(@所有人)',
        'applicability': '所有人（@所有人）',
        'conditions': ['尚未申请的同学', '尚未申请的同学'],
      };
      final rows = noticeDetailRows(original);
      expect(rows.map((row) => row.value), ['所有人', '尚未申请的同学']);
      expect(original['recipient'], '所有人(@所有人)');
      expect(original['conditions'], ['尚未申请的同学', '尚未申请的同学']);
      expect(noticeDisplayText('负责人（@所有人）'), '负责人');
      expect(noticeDisplayText('全体成员（@所有人）'), '全体成员');
      expect(noticeDisplayText('@所有人'), '所有人');
      expect(noticeDisplayText('所有人（@负责人）'), '所有人（@负责人）');
    },
  );
  test(
    'vague time of day survives without inventing an hour; other channels keep context',
    () {
      final time = noticeTime({
        'precision': 'date',
        'date': '2026-10-09',
        'expression': '晚上',
      });
      expect(time, contains('晚上'));
      expect(time, isNot(contains('19:00')));
      expect(
        noticeDetailRows({
          'submission_channel': '办公室A201现场提交',
        }, location: '办公室A201').single.value,
        '现场提交',
      );
      expect(
        noticeDetailRows({
          'submission_channel': '先在A201核对，再到B202提交',
        }, location: 'A201').single.value,
        '先在A201核对，再到B202提交',
      );
    },
  );
  test(
    'no time remains blank and imprecise source expressions remain readable',
    () {
      expect(noticeTime({'precision': 'unknown'}), '');
      expect(
        noticeTime({'precision': 'unknown', 'expression': '方便的时候发'}),
        '方便的时候发',
      );
      expect(
        noticeTime({
          'precision': 'exact',
          'meaning': 'window',
          'at': '2026-10-09T09:00:00+08:00',
          'end_at': '2026-10-09T18:00:00+08:00',
        }),
        contains('可办理'),
      );
      expect(noticeDetailRows({}), isEmpty);
    },
  );

  testWidgets('new manual event requires no guessed time or reminder', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final old = f.api.dio.httpClientAdapter as ControlledTransport;
    Map<String, dynamic>? saved;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.path.endsWith('/semesters')) return body([semester()]);
      if (r.path.endsWith('/events') && r.method == 'POST') {
        saved = Map<String, dynamic>.from(r.data);
        return body({
          'event': {'id': 'e'},
          'semester_id': 's',
          'revision': 2,
          'affected_plan_ids': [],
        }, 201);
      }
      return old.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await route(tester, EventFormPage(controller: f.c, semester: semester()));
    await tester.enterText(find.byType(AppFormField).first, '活动地点等后续通知');
    await tester.scrollUntilVisible(
      find.widgetWithText(AppTextButton, '添加'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await ioTap(tester, find.widgetWithText(AppTextButton, '添加'));
    await ioTap(tester, find.widgetWithText(AppTile, '其他说明'));
    await tester.enterText(
      find.byKey(const Key('notice-other-notes')),
      '报名后再通知地点',
    );
    await ioTap(tester, find.byKey(const ValueKey('notice-remove-_notes')));
    await ioTap(tester, find.widgetWithText(FButton, '添加日程'));
    expect(saved?['time']?['precision'], 'unknown');
    expect(saved?['time']?['at'], isNull);
    expect(saved?['time']?['end_at'], isNull);
    expect(saved?['reminder_minutes'], isEmpty);
    expect(saved?['notes'], '');
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
  });

  testWidgets(
    'renaming a window task preserves its meaning and details without a compulsory explanation',
    (tester) async {
      final f = ScheduleFixture();
      final initial = {
        ...f.item,
        'title': '递交报名表',
        'remaining_minutes': null,
        'time': {
          'precision': 'exact',
          'meaning': 'window',
          'expression': '9点至18点可交',
          'at': '2099-10-09T09:00:00+08:00',
          'end_at': '2099-10-09T18:00:00+08:00',
        },
        'details': {
          'recipient': '班级负责人',
          'materials': ['纸质报名表'],
        },
      };
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? saved;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/items/t') && r.method == 'PATCH') {
          saved = Map<String, dynamic>.from(r.data);
          return body({...initial, ...saved!, 'version': 2, 'revision': 2});
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await route(
        tester,
        ItemFormPage(controller: f.c, semester: semester(), initial: initial),
      );
      await tester.enterText(find.byKey(const Key('item-title')), '递交纸质报名表');
      await ioTap(tester, find.widgetWithText(FButton, '保存修改'));
      expect(saved, isNotNull);
      expect(saved?['time']?['meaning'], 'window');
      expect(
        DateTime.parse(saved?['time']?['end_at']),
        DateTime.parse('2099-10-09T18:00:00+08:00'),
      );
      expect(saved?['details']?['materials'], ['纸质报名表']);
      expect(saved?['change_reason'], isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );

  testWidgets(
    'manual supplements have common choices, can be removed and re-added empty',
    (tester) async {
      for (final scale in [1.0, 1.6]) {
        final notes = TextEditingController();
        Map<String, dynamic> result = {};
        await mount(
          tester,
          Scaffold(
            body: Form(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  NoticeDetailsEditor(
                    value: const {
                      'recipient': '学院办公室',
                      'participation_status': 'optional',
                    },
                    notesController: notes,
                    onChanged: (value) => result = value,
                  ),
                ],
              ),
            ),
          ),
          width: scale == 1 ? 390 : 320,
          textScale: scale,
        );
        Future<void> add(String label) async {
          await tester.ensureVisible(find.widgetWithText(AppTextButton, '添加'));
          await ioTap(tester, find.widgetWithText(AppTextButton, '添加'));
          await ioTap(tester, find.widgetWithText(AppTile, label));
        }

        await tester.tap(find.widgetWithText(AppTextButton, '添加'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppTile, '材料清单'), findsOneWidget);
        expect(find.widgetWithText(AppTile, '交给谁'), findsNothing);
        await capture(tester, 'notice-common-options-$scale');
        await ioTap(tester, find.widgetWithText(AppTile, '材料清单'));
        final materials = find.byKey(const ValueKey('notice-detail-materials'));
        await tester.enterText(materials, '报名表\n身份证复印件');
        await tester.pump();
        await capture(tester, 'notice-edit-remove-$scale');
        await ioTap(
          tester,
          find.byKey(const ValueKey('notice-remove-materials')),
        );
        expect(materials, findsNothing);
        expect(result['materials'], isEmpty);
        expect(result['recipient'], '学院办公室');
        expect(result['participation_status'], 'optional');
        expect(tester.takeException(), isNull);
        await add('材料清单');
        final field = tester.widget<AppFormField>(materials);
        expect(field.controller!.text, '');
        await add('其他说明');
        await tester.enterText(
          find.byKey(const Key('notice-other-notes')),
          '学院提供的额外安排，请先确认负责人。',
        );
        await capture(tester, 'notice-free-description-$scale');
        await ioTap(tester, find.byKey(const ValueKey('notice-remove-_notes')));
        expect(notes.text, '');
        await tester.pumpWidget(const SizedBox());
        notes.dispose();
      }
    },
  );

  testWidgets(
    'editing a real item sends clear values and keeps untouched AI details',
    (tester) async {
      final f = ScheduleFixture();
      final initial = {
        ...f.item,
        'remaining_minutes': null,
        'notes': '旧补充说明',
        'details': {
          'recipient': '班级负责人',
          'materials': ['纸质报名表'],
          'early_arrival_minutes': 15,
          'responsibility': '核对个人信息',
          'participation_status': 'optional',
          'conditions': ['符合报名条件'],
        },
      };
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      Map<String, dynamic>? saved;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/items/t') && r.method == 'PATCH') {
          saved = Map<String, dynamic>.from(r.data);
          return body({...initial, ...saved!, 'version': 2, 'revision': 2});
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await route(
        tester,
        ItemFormPage(controller: f.c, semester: semester(), initial: initial),
      );
      for (final key in [
        'recipient',
        'materials',
        'early_arrival_minutes',
        '_notes',
      ]) {
        final remove = find.byKey(ValueKey('notice-remove-$key'));
        await tester.scrollUntilVisible(
          remove,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(remove), alignment: .3);
        await tester.pumpAndSettle();
        expect(remove.hitTestable(), findsOneWidget);
        await ioTap(tester, remove.hitTestable());
      }
      await tester.enterText(
        find.byKey(const ValueKey('notice-detail-responsibility')),
        '自行核对并提交',
      );
      await ioTap(tester, find.widgetWithText(FButton, '保存修改'));
      expect(saved?['details']?['recipient'], '');
      expect(saved?['details']?['materials'], isEmpty);
      expect(
        (saved?['details'] as Map).containsKey('early_arrival_minutes'),
        true,
      );
      expect(saved?['details']?['early_arrival_minutes'], isNull);
      expect(saved?['notes'], '');
      expect(saved?['details']?['responsibility'], '自行核对并提交');
      expect(saved?['details']?['conditions'], ['符合报名条件']);
      expect(saved?['details']?['participation_status'], 'optional');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    },
  );
}
