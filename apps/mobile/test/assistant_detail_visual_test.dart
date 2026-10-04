import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:semester_os/features/accounts/recovery_code_dialog.dart';
import 'package:semester_os/features/media/source_view.dart';
import 'package:semester_os/features/agent/agent_widgets.dart';
import 'package:semester_os/features/media/hold_voice_button.dart';
import 'hold_voice_test.dart' show HoldInput;
import 'package:semester_os/features/agent/agent_page.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'planning_flow_test.dart' show ioTap;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount, capture, loadPreviewFonts;

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPreviewFonts);
  for (final size in [(390.0, 1.0), (320.0, 1.6)]) {
    testWidgets('assistant detail message history menu failure at $size', (
      tester,
    ) async {
      final f = ScheduleFixture();
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/history')) {
          return body({
            'threads': [
              {
                'id': 't',
                'title': 'Java实验报告和周五组会',
                'updated_at': '2026-10-03T10:00:00+08:00',
              },
              {
                'id': 'b',
                'title': '国庆期间课程调整',
                'updated_at': '2026-10-03T09:00:00+08:00',
              },
              {
                'id': 'c',
                'title': '本周学习安排',
                'updated_at': '2026-10-02T17:00:00+08:00',
              },
            ],
            'has_more': false,
          });
        }
        if (r.path.endsWith('/agent/threads/t')) {
          return body({
            'runs': [
              {
                'id': 'preview',
                'status': 'needs_confirmation',
                'text': '请各位同学于周五下午四点参加课程实验答疑。地点在莲7号楼402，请提前10分钟到场，带上实验报告和电脑。',
                'answer': '**实验答疑**已整理，核对后添加。',
                'source': {'id': 'notice', 'kind': 'image'},
                'cards': [],
                'preview': {
                  'kind': 'item',
                  'action': 'create',
                  'token': 'p',
                  'provided_fields': ['title', 'time', 'location', 'details'],
                  'after': {
                    'title': '课程实验答疑',
                    'kind': 'event',
                    'certainty': 'formal',
                    'time': {
                      'at': '2026-10-09T16:00:00+08:00',
                      'meaning': 'start',
                    },
                    'location': '莲7号楼402',
                    'details': {
                      'materials': ['实验报告', '电脑'],
                      'early_arrival_minutes': 10,
                    },
                  },
                },
              },
              {
                'id': 'error',
                'status': 'failed',
                'text': '这周什么时候有一小时空闲？',
                'answer': '',
                'cards': [],
                'error': '网络连接中断，尚未完成这次查询。',
              },
            ],
          });
        }
        return old.respond(r);
      });
      await tester.runAsync(() => f.c.bind('s'));
      await mount(
        tester,
        AgentPage(
          controller: f.c,
          semester: {'id': 's', 'name': '2026—2027 第一学期'},
          initialThreadId: 't',
        ),
        width: size.$1,
        textScale: size.$2,
      );
      await _settle(tester);
      await tester.ensureVisible(find.text('确认添加'));
      await tester.pumpAndSettle();
      await capture(tester, 'assistant-detail-preview-${size.$1}-${size.$2}');
      await tester.ensureVisible(find.text('网络连接中断，尚未完成这次查询。'));
      await tester.pumpAndSettle();
      await capture(tester, 'assistant-detail-failed-${size.$1}-${size.$2}');
      await ioTap(tester, find.byTooltip('最近对话'));
      await _settle(tester);
      await capture(tester, 'assistant-detail-history-${size.$1}-${size.$2}');
      await ioTap(tester, find.byTooltip('返回对话'));
      await _settle(tester);
      await ioTap(tester, find.byTooltip('添加图片或手动记录'));
      await tester.pumpAndSettle();
      await capture(tester, 'assistant-detail-menu-${size.$1}-${size.$2}');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.c.dispose();
    });
  }
  testWidgets('source delete preview and copyable recovery dialog remain local', (
    tester,
  ) async {
    final f = ScheduleFixture();
    final previous = f.api.dio.httpClientAdapter as ControlledTransport;
    var deletes = 0;
    f.api.dio.httpClientAdapter = ControlledTransport((r) async {
      if (r.method == 'DELETE') deletes++;
      if (r.path.endsWith('/sources/a')) {
        return body({
          'id': 'a',
          'kind': 'image',
          'version': 1,
          'file_deleted': false,
          'status': 'recognized',
          'text': '周五下午四点在6412开组会',
          'reference_at': '2026-10-03T10:00:00+08:00',
        });
      }
      if (r.path.endsWith('/content')) {
        return ResponseBody.fromBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3RkAAAAASUVORK5CYII=',
          ),
          200,
          headers: {
            'content-type': ['image/png'],
          },
        );
      }
      return previous.respond(r);
    });
    await tester.runAsync(() => f.c.bind('s'));
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SourceViewPage(controller: f.c, id: 'a'),
              ),
            ),
            child: const Text('打开来源'),
          ),
        ),
      ),
      width: 320,
      textScale: 1.6,
    );
    await ioTap(tester, find.text('打开来源'));
    await _settle(tester);
    await tester.tap(find.byTooltip('来源操作'));
    await tester.pumpAndSettle();
    await capture(tester, 'source-actions-small');
    await tester.tap(find.text('删除原文件'));
    await _settle(tester);
    expect(find.text('删除原图片？'), findsOneWidget);
    expect(deletes, 0);
    await capture(tester, 'source-delete-preview-small');
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    f.c.dispose();
    await mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  const RecoveryCodeDialog(code: '7L3D-K6TX-QY49-AB23'),
            ),
            child: const Text('恢复码'),
          ),
        ),
      ),
      width: 320,
      textScale: 1.6,
    );
    await tester.tap(find.text('恢复码'));
    await tester.pumpAndSettle();
    await capture(tester, 'recovery-code-small');
    await ioTap(tester, find.text('复制恢复码'));
    expect(find.text('已复制'), findsOneWidget);
    await capture(tester, 'recovery-code-copied-small');
    await tester.tap(find.text('我已保存'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'long text stays in its message and recording shows real elapsed time',
    (tester) async {
      const long =
          '请各位同学于周五下午四点参加课程实验答疑。地点在莲7号楼402，请提前10分钟到场，带上实验报告和电脑。\n'
          '本次主要讨论数据结构实验的实现思路和测试结果，请准备好实验代码及遇到的问题。小组成员都可以参加，暂时没有其他安排的同学也可以旁听。\n'
          '实验报告需包含实验目的、具体步骤、实现方法、测试结果和问题分析，文件以学号及姓名命名。\n'
          '如有课程冲突，请向课程老师说明情况；答疑结束时间没有在这份通知中给出。后续具体安排以课程通知为准。';
      final input = HoldInput();
      await mount(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                AssistantUserMessage(
                  text: long,
                  attachment: '图片通知',
                  onEdit: () {},
                  onSource: () {},
                ),
                const SizedBox(height: 20),
                HoldVoiceButton(
                  input: input,
                  onRecorded: (_) async {},
                  onError: (_) {},
                ),
              ],
            ),
          ),
        ),
        width: 320,
        textScale: 1.6,
      );
      await capture(tester, 'long-message-collapsed-small');
      await tester.tap(find.text('展开消息'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      await capture(tester, 'long-message-expanded-small');
      await tester.ensureVisible(find.text('收起'));
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(HoldVoiceButton));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(HoldVoiceButton)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await capture(tester, 'voice-recording-small');
      await gesture.moveBy(const Offset(0, -90));
      await tester.pump();
      await capture(tester, 'voice-cancel-small');
      await gesture.up();
      await tester.pump();
      expect(input.starts, 1);
      expect(input.stops, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
