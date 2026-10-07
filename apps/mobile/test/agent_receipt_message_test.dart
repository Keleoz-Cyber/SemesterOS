import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/agent_receipt.dart';

void main() {
  final examples = <(Map<String, dynamic>, Map<String, dynamic>, String)>[
    (
      {
        'kind': 'course_change',
        'action': 'suspend',
        'before': [
          {'title': '课程A'},
          {'title': '课程B'},
        ],
        'after': [],
      },
      {},
      '已停课 2 次',
    ),
    (
      {
        'kind': 'course_change',
        'action': 'cancel',
        'before': [
          {'title': '课程A'},
        ],
        'after': [],
      },
      {},
      '已停课 1 次',
    ),
    (
      {
        'kind': 'course_change',
        'action': 'move',
        'title': '课程A',
        'before': [
          {'title': '课程A'},
        ],
        'after': [
          {'title': '课程A'},
        ],
      },
      {},
      '已调整课程 · 课程A',
    ),
    (
      {
        'kind': 'course_change',
        'action': 'add',
        'before': [],
        'after': [
          {'title': '课程A'},
        ],
      },
      {},
      '已添加补课 · 课程A',
    ),
    (
      {
        'kind': 'event',
        'action': 'create',
        'before': null,
        'after': {'title': '班会'},
      },
      {},
      '已添加 班会',
    ),
    (
      {
        'kind': 'event',
        'action': 'cancel',
        'before': {'title': '班会'},
        'after': null,
      },
      {},
      '已取消 班会',
    ),
    (
      {
        'kind': 'item',
        'action': 'create',
        'before': null,
        'after': {'title': '实验报告'},
      },
      {},
      '已添加 实验报告',
    ),
    (
      {
        'kind': 'item_state',
        'action': 'completed',
        'before': {'title': '考试'},
        'after': {'title': '考试', 'lifecycle': 'completed'},
      },
      {},
      '已完成 考试',
    ),
    (
      {
        'kind': 'item_state',
        'action': 'cancelled',
        'before': {'title': '报告'},
        'after': {'title': '报告', 'lifecycle': 'cancelled'},
      },
      {},
      '已取消 报告',
    ),
    (
      {
        'kind': 'item_state',
        'action': 'active',
        'before': {'title': '报告'},
        'after': {'title': '报告', 'lifecycle': 'active'},
      },
      {},
      '已恢复 报告',
    ),
    (
      {
        'kind': 'operation',
        'action': 'update_reminder',
        'title': '报告',
        'before': {'enabled': true},
        'after': {'enabled': false},
      },
      {},
      '已关闭提醒 报告',
    ),
    (
      {
        'kind': 'exam_change',
        'action': 'update',
        'before': {'title': '考试'},
        'after': {'title': '考试'},
      },
      {},
      '已更新 考试',
    ),
    (
      {
        'kind': 'plan',
        'action': 'schedule',
        'before': {'tasks': [], 'blocks': []},
        'after': {'blocks': []},
      },
      {},
      '已保存学习安排',
    ),
    (
      {
        'kind': 'plan',
        'action': 'replan',
        'before': {'tasks': [], 'blocks': []},
        'after': {'blocks': []},
      },
      {},
      '已调整学习安排',
    ),
    (
      {'kind': 'batch', 'action': 'batch', 'groups': []},
      {
        'groups': [
          {'id': 'g1'},
          {'id': 'g2', 'status': 'skipped'},
        ],
      },
      '已保存 1 项安排',
    ),
    ({'kind': 'undo', 'action': 'undo', 'summary': []}, {}, '已撤销'),
  ];
  for (var i = 0; i < examples.length; i++) {
    final sample = examples[i];
    test(
      'saved ${sample.$1['kind']}/${sample.$1['action']} uses its actual result shape [$i]',
      () {
        expect(
          savedActionMessage({'preview': sample.$1, 'receipt': sample.$2}),
          sample.$3,
        );
      },
    );
  }
}
