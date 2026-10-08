import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/media/clipboard_notice_classifier.dart';
import 'package:semester_os/features/media/clipboard_notice_prompt.dart';
import 'package:semester_os/features/media/incoming_notice_draft.dart';
import 'package:semester_os/ui/forui_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local clipboard hint accepts loose schedules and incomplete notices',
    () {
      for (final text in [
        '通知📢：明早8:10各节目到25-119进行候场等待联排，届时进行考勤。',
        '通知📢：各节目进行联排，请负责人组织考勤。',
        '周三 5、6节 Python',
        '第5节 摄影测量学',
        '明天下午三点半开会',
        '10月8日上午考试',
        '周末去图书馆自习',
        '明晚和同学吃火锅',
        '8号去医院',
        '明天买牛奶',
        '19:00—21:00',
        '记得提交申请',
        '请班长领取教材',
        '报名截止啦',
        'Oct 8: meeting in room 201',
        'Friday 3pm rehearsal',
        'Class starts tomorrow at 10:00',
        'From tomorrow our class meets at 10:00',
        'Call Mom tomorrow',
        'Reminder: bring your student card',
        'Tomorrow class link: https://example.edu/lecture',
      ]) {
        expect(isPlausibleClipboardNotice(text), isTrue, reason: text);
      }
      for (final text in [
        '',
        'Hello world',
        '今天风很大，注意保暖。',
        '这是关于学习的文章，没有约定时间。',
        'https://example.edu/course',
        'student@example.edu',
        r'C:\Users\me\lecture.pdf',
        'QWAS_example_password_1234',
        '账号: 123456\n密码: example_password',
        '明天开会\nAPI_KEY=sk_example_only',
        'const event = {"time": "明天", "title": "开会"};',
        '{"title":"明天开会","start":"10:00"}',
        '```python\nprint("明天开会")\n```',
      ]) {
        expect(isPlausibleClipboardNotice(text), isFalse, reason: text);
      }
    },
  );

  testWidgets(
    'clipboard inspection is local, quiet for prose and explicit for paste',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var text = '今天风很大，注意保暖。';
      var clipboardToken = 'clipboard-test-prose';
      var reads = 0;
      var imports = <String>[];
      final handled = <String>{};
      messenger.setMockMethodCallHandler(noticeInputChannel, (call) async {
        if (call.method == 'clipboardStatus') {
          return {
            'has_text': true,
            'token': clipboardToken,
            'handled': handled.contains(clipboardToken),
          };
        }
        if (call.method == 'markClipboardHandled') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          expect(args.keys, ['token']);
          handled.add(args['token'] as String);
          return null;
        }
        fail(
          'Clipboard hint must not issue another platform action: ${call.method}',
        );
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          reads++;
          return {'text': text};
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(noticeInputChannel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      Future<void> mount({bool visible = true}) => tester.pumpWidget(
        MaterialApp(
          builder: (_, child) => ShiriForuiTheme(child: child!),
          home: Scaffold(
            body: TickerMode(
              enabled: visible,
              child: ClipboardNoticePrompt(onImport: imports.add),
            ),
          ),
        ),
      );
      await mount();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clipboard-import')), findsNothing);
      expect(reads, 1);
      expect(imports, isEmpty);

      text = '明早8:10到25-119彩排';
      clipboardToken = 'clipboard-test-notice';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('整理复制的内容'), findsOneWidget);
      expect(imports, isEmpty);
      final classificationReads = reads;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        reads,
        classificationReads,
        reason: 'Same OS token does not reread clipboard contents',
      );
      await tester.tap(find.byKey(const Key('clipboard-import')));
      await tester.pumpAndSettle();
      expect(imports, [text]);
      expect(handled, contains(clipboardToken));
      expect(find.byKey(const Key('clipboard-import')), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clipboard-import')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      clipboardToken = 'clipboard-test-hidden';
      final hiddenReads = reads;
      await mount(visible: false);
      await tester.pumpAndSettle();
      expect(
        reads,
        hiddenReads,
        reason: 'Hidden tabs do not inspect clipboard text',
      );
      await mount();
      await tester.pumpAndSettle();
      expect(reads, hiddenReads + 1);
      expect(
        find.text('整理复制的内容'),
        findsOneWidget,
        reason: 'Returning to the visible tab can inspect its new token',
      );
    },
  );

  testWidgets(
    'compact clipboard action stays aligned at 360dp and large type',
    (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var pasted = 0, dismissed = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ShiriForuiTheme(
            child: MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipboardNoticeRibbon(
                onImport: () async => pasted++,
                onDismiss: () => dismissed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final paste = find.byKey(const Key('clipboard-import'));
      final dismiss = find.byKey(const Key('clipboard-dismiss'));
      expect(tester.getSize(paste).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(dismiss).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(dismiss).height, greaterThanOrEqualTo(48));
      expect(
        tester.getRect(find.text('整理复制的内容')).center.dy,
        closeTo(
          tester.getRect(find.byIcon(Icons.content_paste_rounded)).center.dy,
          .5,
        ),
      );
      await tester.tap(paste);
      await tester.pumpAndSettle();
      await tester.tap(dismiss);
      await tester.pumpAndSettle();
      expect(pasted, 1);
      expect(dismissed, 1);
    },
  );
}
