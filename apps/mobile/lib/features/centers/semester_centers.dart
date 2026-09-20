import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/item_form.dart';
import '../planning/risk_widgets.dart';
import '../timetable/course_widgets.dart';
import '../changes/changes_page.dart';
import 'hub_data.dart';
import 'exam_pages.dart';

Future<void> openHubItem(
  BuildContext context,
  ItemsController c,
  Map<String, dynamic> item,
  Map<String, dynamic> semester,
) async {
  if (item['kind'] == 'exam') {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamCenterPage(
          controller: c,
          semester: semester,
          examId: item['id'],
        ),
      ),
    );
  } else {
    await context.push('/items/${item['id']}');
  }
}

Widget hubItem(
  BuildContext context,
  ItemsController c,
  Map<String, dynamic> item,
  Map<String, dynamic> data,
  bool fresh,
  Future<void> Function() reload,
) => ItemCard(
  item: item,
  onTap: () async {
    await openHubItem(
      context,
      c,
      item,
      Map<String, dynamic>.from(data['semester']),
    );
    await reload();
  },
  riskFooter: item['kind'] == 'exam' || item['lifecycle'] != 'active'
      ? null
      : RiskBadge(
          risk: fresh
              ? c
                    .rows(data['risk']?['items'])
                    .where((r) => r['item_id'] == item['id'])
                    .firstOrNull
              : null,
          onTap: () => showRiskDetails(context, c, item),
        ),
);

class CourseHubPage extends StatelessWidget {
  final ItemsController controller;
  final String courseId;
  const CourseHubPage({
    super.key,
    required this.controller,
    required this.courseId,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课程事务')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: HubData(
        controller: controller,
        path: '/courses/$courseId/hub',
        builder: (context, data, fresh, reload) {
          final course = data['course'];
          final all = controller.rows(data['items']);
          Future<void> add(String kind) async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ItemFormPage(
                  controller: controller,
                  semester: Map<String, dynamic>.from(data['semester']),
                  kind: kind,
                  candidate: {
                    'item': {'kind': kind, 'course_id': courseId},
                  },
                ),
              ),
            );
            await reload();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CampusHero(
                eyebrow: '课程事务',
                title: course['title'],
                subtitle: '${course['teacher'] ?? '教师待补充'}\n作业、考试与每一次课程变化',
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => add('assignment'),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('记作业'),
                  ),
                  TextButton.icon(
                    onPressed: () => add('task'),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('记学习任务'),
                  ),
                  TextButton.icon(
                    onPressed: () => add('exam'),
                    icon: const Icon(Icons.school_outlined),
                    label: const Text('记考试'),
                  ),
                ],
              ),
              const SectionHeading('待办任务'),
              for (final i in orderedItems(
                all
                    .where(
                      (i) => i['kind'] != 'exam' && i['lifecycle'] == 'active',
                    )
                    .toList(),
              ))
                hubItem(context, controller, i, data, fresh, reload),
              if (!all.any(
                (i) => i['kind'] != 'exam' && i['lifecycle'] == 'active',
              ))
                const CampusPanel(child: Text('没有明确关联的待办任务')),
              const SectionHeading('关联考试'),
              for (final e in orderedItems(
                all.where((i) => i['kind'] == 'exam').toList(),
              ))
                hubItem(context, controller, e, data, fresh, reload),
              ExpansionTile(
                title: const Text('已完成 / 已取消任务'),
                children: [
                  for (final i in all.where(
                    (i) => i['kind'] != 'exam' && i['lifecycle'] != 'active',
                  ))
                    hubItem(context, controller, i, data, fresh, reload),
                ],
              ),
              const SectionHeading('上课与变更记录'),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChangesPage(controller: controller),
                    ),
                  );
                  await reload();
                },
                child: const Text('记录调课或停课'),
              ),
              for (final change in controller.rows(data['changes']))
                changeCard(change),
              ExpansionTile(
                title: Text(
                  '本学期上课安排（${controller.rows(data['occurrences']).length}次）',
                ),
                children: [
                  for (final e in controller.rows(data['occurrences']))
                    ListTile(
                      title: Text(displayInstant(e['start_at'])),
                      subtitle: Text(
                        '${e['location'] ?? ''}${e['changed'] == true ? ' · 已变更' : ''}',
                      ),
                      onTap: () => showCourseDetails(context, e),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

Widget changeCard(Map<String, dynamic> change) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: CampusPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${changeNames[change['kind']] ?? '变化'} · ${change['title']}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final e in change['before'] ?? [])
          Text('原：${displayInstant(e['start_at'])}'),
        for (final e in change['after'] ?? [])
          Text('新：${displayInstant(e['start_at'])}'),
        Text('依据：${change['source_text']}'),
      ],
    ),
  ),
);

class SemesterHome extends StatelessWidget {
  final ItemsController controller;
  final VoidCallback onManage;
  const SemesterHome({
    super.key,
    required this.controller,
    required this.onManage,
  });
  @override
  Widget build(BuildContext context) => HubData(
    controller: controller,
    path: '/semesters/${controller.semesterId}/hub',
    builder: (context, data, fresh, reload) {
      final semester = Map<String, dynamic>.from(data['semester']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampusHero(
            eyebrow: '看见整个学期',
            title: semester['name'],
            subtitle: '重要节点按周排列\n不确定的时间继续保留待确认',
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExamCenterPage(
                        controller: controller,
                        semester: semester,
                      ),
                    ),
                  );
                  await reload();
                },
                icon: const Icon(Icons.school_outlined),
                label: const Text('考试中心'),
              ),
              TextButton.icon(
                onPressed: onManage,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('管理学期与课表'),
              ),
            ],
          ),
          ExpansionTile(
            title: Text('课程事务（${controller.rows(data['courses']).length}门）'),
            children: [
              for (final course in controller.rows(data['courses']))
                ListTile(
                  title: Text(course['title']),
                  subtitle: Text(
                    '${course['teacher']} · 待办${course['task_count']} · 考试${course['exam_count']}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CourseHubPage(
                          controller: controller,
                          courseId: course['id'],
                        ),
                      ),
                    );
                    await reload();
                  },
                ),
            ],
          ),
          const SectionHeading('学期时间轴'),
          const SoftNotice('任务显示在截止日期所在周，也可以提前完成。每周忙不忙，按已安排的计划估算；紧急任务会单独提醒。'),
          for (final week in controller.rows(data['weeks']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CampusPanel(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  title: Text('第${week['week']}周 · ${week['start_date']}'),
                  subtitle: Text(
                    !fresh
                        ? '负荷待刷新'
                        : switch (week['load_level']) {
                            'high' => '计划较满或含高风险事项',
                            'unknown' => '时间信息不足，负荷待确认',
                            'past' => '已过去的周',
                            _ => '查看本周节点',
                          },
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (fresh) ...[
                            Text(
                              '未来可学习 ${week['available_minutes'] == null ? '待确认' : minutesLabel(week['available_minutes'])} · 已安排 ${minutesLabel(week['planned_minutes'])}',
                            ),
                            Text(
                              '本周明确截止的已知剩余工作 ${minutesLabel(week['known_due_remaining_minutes'])}',
                            ),
                          ],
                          for (final item in controller.rows(week['items']))
                            hubItem(
                              context,
                              controller,
                              item,
                              data,
                              fresh,
                              reload,
                            ),
                          for (final change in controller.rows(week['changes']))
                            changeCard(change),
                          if (controller.rows(week['items']).isEmpty &&
                              controller.rows(week['changes']).isEmpty)
                            const Text('没有已记录的重要节点'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (controller.rows(data['undated']).isNotEmpty) ...[
            const SectionHeading('日期待确认'),
            for (final i in controller.rows(data['undated']))
              hubItem(context, controller, i, data, fresh, reload),
          ],
          if (controller.rows(data['outside']).isNotEmpty) ...[
            const SectionHeading('学期范围外，需核对'),
            for (final i in controller.rows(data['outside']))
              hubItem(context, controller, i, data, fresh, reload),
          ],
        ],
      );
    },
  );
}
