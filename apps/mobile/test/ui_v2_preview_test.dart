import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/timetable/shell_page.dart';
import 'package:semester_os/features/agent/agent_page.dart';
import 'package:semester_os/features/items/item_detail.dart';
import 'package:semester_os/ui/empty_states.dart';
import 'api_session_test.dart' show ControlledTransport, body;
import 'ui_polish_test.dart'
    show sampleController, sampleItems, mount, capture, loadPreviewFonts;

void main() {
  setUpAll(loadPreviewFonts);
  for (final mode in [
    (390.0, 1.0, false),
    (360.0, 1.6, false),
    (412.0, 1.0, false),
    (360.0, 1.6, true),
  ]) {
    testWidgets('v2 production pages fit $mode', (tester) async {
      final app = sampleController();
      final now = DateTime.now().toUtc();
      final localNow = now.toLocal();
      final meetingAt = DateTime(
        localNow.year,
        localNow.month,
        localNow.day + 1,
        15,
      ).toUtc();
      final task = <String, dynamic>{
        'id': 'v2-task',
        'semester_id': 'sample',
        'kind': 'assignment',
        'version': 1,
        'title': '整理实验报告',
        'lifecycle': 'active',
        'certainty': 'formal',
        'remaining_minutes': 20,
        'start_policy': 'now',
        'priority': 'normal',
        'splittable': true,
        'category_id': 'study',
        'course_title': '数据结构',
        'time': {
          'precision': 'exact',
          'at': now.add(const Duration(hours: 3)).toIso8601String(),
        },
        'anchor_at': now.add(const Duration(hours: 3)).toIso8601String(),
        'reminders': [],
      };
      final original = app.api.dio.httpClientAdapter as ControlledTransport;
      app.api.dio.httpClientAdapter = ControlledTransport((request) async {
        if (request.path.endsWith('/items/v2-task')) return body(task);
        if (request.path.endsWith('/items')) {
          return body({
            'revision': 1,
            'items': [task],
          });
        }
        if (request.path.endsWith('/agent/threads/v2')) {
          return body({
            'runs': [
              {
                'id': 'v2-run',
                'status': 'needs_confirmation',
                'text': '明天下午三点开会，地点在办公室。',
                'answer': '已整理出一项日程，请核对时间与地点。',
                'cards': [],
                'preview': {
                  'kind': 'item',
                  'action': 'create',
                  'token': 'v2-preview',
                  'provided_fields': ['title', 'time', 'location'],
                  'after': {
                    'title': '开会',
                    'kind': 'event',
                    'certainty': 'formal',
                    'time': {
                      'at': meetingAt.toIso8601String(),
                      'meaning': 'start',
                    },
                    'location': '办公室',
                  },
                },
              },
            ],
          });
        }
        return original.respond(request);
      });
      final items = (await tester.runAsync(() => sampleItems(app)))!;
      await tester.runAsync(
        () => app.cache.write('home-layout:${app.user['id']}:sample', {
          'enabled': ['deadlines', 'plans', 'windows', 'exams', 'week_heatmap'],
        }),
      );
      Future<void> render(Widget page, String name) async {
        await mount(
          tester,
          MediaQuery(
            data: MediaQueryData(
              disableAnimations: mode.$3,
              textScaler: TextScaler.linear(mode.$2),
              size: Size(mode.$1, 844),
            ),
            child: page,
          ),
          width: mode.$1,
          height: 844,
          textScale: mode.$2,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: name);
        await capture(
          tester,
          'v2-$name-${mode.$1.toInt()}-${mode.$2}-${mode.$3 ? 'reduced' : 'motion'}',
        );
        await tester.pumpWidget(const SizedBox());
      }

      for (final (index, name) in [
        'today',
        'schedule',
        'tasks',
        'semester',
      ].indexed) {
        await render(
          ShellPage(controller: app, items: items, initialTab: index),
          name,
        );
      }
      await render(
        AgentPage(
          controller: items,
          semester: app.semester!,
          initialThreadId: 'v2',
        ),
        'assistant',
      );
      await render(
        ItemDetailPage(
          controller: items,
          semester: app.semester!,
          id: 'v2-task',
        ),
        'detail',
      );
      await render(
        Scaffold(
          body: EmptyItems(
            title: '暂无任务',
            actionLabel: '新建任务',
            onAddItem: () {},
          ),
        ),
        'empty',
      );
      items.dispose();
      app.dispose();
    });
  }
}
