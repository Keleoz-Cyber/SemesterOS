import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/record_actions.dart';
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/item_form.dart';
import '../import/manual_page.dart';
import '../planning/risk_widgets.dart';
import '../timetable/course_widgets.dart';
import '../changes/changes_page.dart';
import 'hub_data.dart';
import 'exam_pages.dart';
export 'semester_timeline.dart' show SemesterHome, SemesterHomeState;

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

          Future<void> editCourse() async {
            try {
              final detail = Map<String, dynamic>.from(
                await controller.api.request('GET', '/courses/$courseId'),
              );
              if (!context.mounted) return;
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManualPage.edit(
                    items: controller,
                    existing: Map<String, dynamic>.from(detail['course']),
                    revision: detail['revision'] as int,
                    courseId: courseId,
                  ),
                ),
              );
              if (saved == true && context.mounted) await reload();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(e))));
              }
            }
          }

          Future<void> deleteCourse() async {
            try {
              final preview = Map<String, dynamic>.from(
                await controller.api.request(
                  'GET',
                  '/courses/$courseId/delete-preview',
                ),
              );
              if (!context.mounted) return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialog) => AppDialog(
                  title: Text('删除“${preview['title']}”？'),
                  content: Text(
                    '将删除 ${preview['meetings']} 条上课安排。'
                    '${preview['linked_items']} 条关联事项会保留，并解除课程关联。',
                  ),
                  actions: [
                    AppTextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('保留课程'),
                    ),
                    AppButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('确认删除'),
                    ),
                  ],
                ),
              );
              if (confirmed != true || !context.mounted) return;
              final result = Map<String, dynamic>.from(
                await controller.api.request(
                  'DELETE',
                  '/courses/$courseId?expected_revision=${preview['revision']}',
                ),
              );
              await controller.onRealityChanged?.call(result);
              await controller.refresh();
              if (context.mounted) Navigator.pop(context);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(e))));
              }
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecordHeading(
                label: '课程事务',
                title: course['title'],
                icon: Icons.menu_book_rounded,
                color: CoursePalette.forTitle(course['title']).ink,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: CoursePalette.forTitle(course['title']).background,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    if ('${course['teacher'] ?? ''}'.trim().isNotEmpty) ...[
                      RecordFact(
                        label: '任课教师',
                        value: '${course['teacher']}',
                        icon: Icons.person_outline_rounded,
                      ),
                      const Divider(height: 1),
                    ],
                    RecordFact(
                      label: '本学期课次',
                      value:
                          '${controller.rows(data['occurrences']).length} 次上课安排',
                      icon: Icons.calendar_view_week_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppButton.icon(
                onPressed: () async {
                  final kind = await showModalBottomSheet<String>(
                    context: context,
                    useSafeArea: true,
                    builder: (sheetContext) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '添加课程事项',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          RecordActionTile(
                            title: '作业',
                            icon: Icons.edit_note_rounded,
                            onTap: () =>
                                Navigator.pop(sheetContext, 'assignment'),
                          ),
                          RecordActionTile(
                            title: '学习任务',
                            icon: Icons.task_alt_rounded,
                            onTap: () => Navigator.pop(sheetContext, 'task'),
                          ),
                          RecordActionTile(
                            title: '考试',
                            icon: Icons.school_outlined,
                            onTap: () => Navigator.pop(sheetContext, 'exam'),
                          ),
                        ],
                      ),
                    ),
                  );
                  if (kind != null && context.mounted) await add(kind);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加事项'),
              ),
              const SizedBox(height: 8),
              AppTextButton.icon(
                onPressed: editCourse,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑课程安排'),
              ),
              if (all.any(
                (i) => i['kind'] != 'exam' && i['lifecycle'] == 'active',
              ))
                const SectionHeading('待办任务'),
              for (final i in orderedItems(
                all
                    .where(
                      (i) => i['kind'] != 'exam' && i['lifecycle'] == 'active',
                    )
                    .toList(),
              ))
                hubItem(context, controller, i, data, fresh, reload),
              if (all.any((i) => i['kind'] == 'exam'))
                const SectionHeading('关联考试'),
              for (final e in orderedItems(
                all.where((i) => i['kind'] == 'exam').toList(),
              ))
                hubItem(context, controller, e, data, fresh, reload),
              if (all.any(
                (i) => i['kind'] != 'exam' && i['lifecycle'] != 'active',
              ))
                AppDisclosure(
                  leading: const Icon(Icons.inventory_2_outlined),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('已完成 / 已取消任务'),
                  children: [
                    for (final i in all.where(
                      (i) => i['kind'] != 'exam' && i['lifecycle'] != 'active',
                    ))
                      hubItem(context, controller, i, data, fresh, reload),
                  ],
                ),
              const Divider(height: 32),
              const SectionHeading('上课与变更记录'),
              RecordActionTile(
                title: '调课或停课',
                icon: Icons.edit_calendar_outlined,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChangesPage(controller: controller),
                    ),
                  );
                  await reload();
                },
              ),
              for (final change in controller.rows(data['changes']))
                changeCard(change),
              AppDisclosure(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  '本学期上课安排（${controller.rows(data['occurrences']).length}次）',
                ),
                children: [
                  for (final e in controller.rows(data['occurrences']))
                    AppTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(
                        e['changed'] == true
                            ? Icons.edit_calendar_outlined
                            : Icons.event_outlined,
                        color: e['changed'] == true
                            ? CampusColors.primary
                            : CampusColors.muted,
                      ),
                      title: Text(displayInstant(e['start_at'])),
                      subtitle: Text(
                        '${e['location'] ?? ''}${e['changed'] == true ? ' · 已变更' : ''}',
                      ),
                      onTap: () => showCourseDetails(context, e),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextButton.icon(
                onPressed: deleteCourse,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除这门课程'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Widget changeCard(Map<String, dynamic> change) => Container(
  margin: const EdgeInsets.symmetric(vertical: 8),
  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
  decoration: const BoxDecoration(
    border: Border(left: BorderSide(color: CampusColors.teal, width: 3)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${changeNames[change['kind']] ?? '变化'} · ${change['title']}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      for (final e in change['before'] ?? [])
        Text(
          '原：${displayInstant(e['start_at'])}',
          style: const TextStyle(color: CampusColors.muted),
        ),
      for (final e in change['after'] ?? [])
        Text(
          '新：${displayInstant(e['start_at'])}',
          style: const TextStyle(
            color: CampusColors.teal,
            fontWeight: FontWeight.w600,
          ),
        ),
      const SizedBox(height: 8),
      Text(
        '依据：${change['source_text']}',
        style: const TextStyle(fontSize: 14, color: CampusColors.muted),
      ),
    ],
  ),
);
