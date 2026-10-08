import 'academic_visuals.dart';
import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../../ui/record_actions.dart';
import '../../ui/app_sheet.dart';
import '../../ui/app_number_picker.dart' show formatNumberSelection;
import '../items/items_controller.dart';
import '../items/item_widgets.dart';
import '../items/item_form.dart';
import '../import/manual_page.dart';
import '../planning/risk_widgets.dart';
import '../timetable/course_widgets.dart';
import '../changes/changes_page.dart';
import '../changes/course_change_display.dart';
import 'hub_data.dart';
import 'exam_pages.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/motion/staggered_reveal.dart';
import '../../ui/v2/motion/skeleton.dart';
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
  final String? occurrenceId;
  final String? surfaceTitle;
  final String? surfaceTag;
  const CourseHubPage({
    super.key,
    required this.controller,
    required this.courseId,
    this.occurrenceId,
    this.surfaceTitle,
    this.surfaceTag,
  });
  String? get _surfaceTag =>
      surfaceTag ??
      (occurrenceId == null ? null : 'course-surface-$occurrenceId');
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('课程事务')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: HubData(
        controller: controller,
        path: '/courses/$courseId/hub',
        placeholder: surfaceTitle?.trim().isNotEmpty == true
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_surfaceTag != null)
                    Hero(
                      tag: _surfaceTag!,
                      child: Material(
                        type: MaterialType.transparency,
                        child: AcademicRecordHeading(
                          title: surfaceTitle!,
                          label: '课程',
                          icon: Icons.menu_book_rounded,
                          color: CoursePalette.forTitle(
                            surfaceTitle!.replaceFirst(
                              RegExp(r'^(?:已请假|待请假|免听)\s*·\s*'),
                              '',
                            ),
                          ).ink,
                        ),
                      ),
                    )
                  else
                    AcademicRecordHeading(
                      title: surfaceTitle!,
                      label: '课程',
                      icon: Icons.menu_book_rounded,
                      color: CoursePalette.forTitle(surfaceTitle!).ink,
                    ),
                  const SkeletonScope(
                    semanticLabel: '正在读取课程资料',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SkeletonBox(
                          height: 148,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                        SizedBox(height: 20),
                        SkeletonBox(
                          height: 52,
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                        ),
                        SizedBox(height: 28),
                        SkeletonLine(widthFactor: .35),
                        SizedBox(height: 12),
                        SkeletonBox(
                          height: 120,
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : null,
        builder: (context, data, fresh, reload) {
          final course = data['course'];
          final all = controller.rows(data['items']);
          final occurrences = controller.rows(data['occurrences']);
          final selected = occurrences
              .where((e) => e['id'] == occurrenceId)
              .firstOrNull;
          final next = occurrences
              .where((e) => DateTime.parse(e['end_at']).isAfter(DateTime.now()))
              .firstOrNull;
          final focus = selected ?? next ?? occurrences.lastOrNull;
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
            final generation = controller.api.generation;
            final sid = controller.semesterId;
            bool current() =>
                controller.api.generation == generation &&
                controller.semesterId == sid;
            try {
              final ids = (course['course_ids'] as List? ?? [courseId])
                  .whereType<String>()
                  .toSet()
                  .toList();
              if (ids.isEmpty) ids.add(courseId);
              Map<String, dynamic>? detail;
              if (ids.length > 1) {
                final arrangements = await Future.wait([
                  for (final id in ids)
                    controller.api
                        .request('GET', '/courses/$id')
                        .then(
                          (value) => <String, dynamic>{
                            ...Map<String, dynamic>.from(value),
                            'id': id,
                          },
                        ),
                ]);
                if (!context.mounted || !current()) return;
                arrangements.sort((a, b) {
                  final x = Map<String, dynamic>.from(a['course']),
                      y = Map<String, dynamic>.from(b['course']);
                  final weekday = (x['weekday'] as int).compareTo(y['weekday']);
                  if (weekday != 0) return weekday;
                  return (x['sections'] as List).cast<int>().first.compareTo(
                    (y['sections'] as List).cast<int>().first,
                  );
                });
                detail = await showAppSheet<Map<String, dynamic>>(
                  context: context,
                  builder: (sheetContext) => Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '选择要编辑的安排',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        for (final arrangement in arrangements)
                          _CourseArrangementChoice(
                            detail: arrangement,
                            semester: Map<String, dynamic>.from(
                              data['semester'],
                            ),
                            onTap: () =>
                                Navigator.pop(sheetContext, arrangement),
                          ),
                      ],
                    ),
                  ),
                );
                if (detail == null) return;
              } else {
                detail = Map<String, dynamic>.from(
                  await controller.api.request('GET', '/courses/${ids.single}'),
                );
              }
              if (!context.mounted || !current()) return;
              final selectedDetail = detail;
              final selectedId = '${selectedDetail['id'] ?? ids.first}';
              final saved = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManualPage.edit(
                    items: controller,
                    semester: Map<String, dynamic>.from(data['semester']),
                    existing: Map<String, dynamic>.from(
                      selectedDetail['course'],
                    ),
                    revision: selectedDetail['revision'] as int,
                    courseId: selectedId,
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
                    '将删除这门课程的全部上课安排。'
                    '${(preview['linked_items'] as num? ?? 0) > 0 ? '${preview['linked_items']}条关联事项会保留，并解除课程关联。' : ''}',
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
              final navigator = Navigator.of(context);
              final route = ModalRoute.of(context);
              final result = Map<String, dynamic>.from(
                await controller.api.request(
                  'DELETE',
                  '/courses/$courseId?expected_revision=${preview['revision']}',
                ),
              );
              // Leave the deleted resource before a catalog refresh rebuilds
              // this route/context and starts a request for a missing course.
              if (navigator.mounted && route?.isCurrent == true) {
                navigator.pop();
              }
              await controller.onRealityChanged?.call(result);
              await controller.refresh();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(e))));
              }
            }
          }

          final palette = CoursePalette.forTitle(course['title']);
          Widget heading = AcademicRecordHeading(
            label: '',
            title: course['title'],
            icon: Icons.menu_book_rounded,
            color: palette.ink,
          );
          if (_surfaceTag != null) {
            heading = Hero(
              tag: _surfaceTag!,
              child: Material(type: MaterialType.transparency, child: heading),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              StaggeredReveal(
                revealKey: 'course-focus-$courseId-${focus?['id']}',
                index: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: CampusColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: v2.ShiriShadows.light.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          if ('${course['teacher'] ?? ''}'.trim().isNotEmpty)
                            _CourseMeta(
                              icon: Icons.person_outline_rounded,
                              text: '${course['teacher']}',
                            ),
                          _CourseMeta(
                            icon: Icons.calendar_view_week_rounded,
                            text:
                                '${controller.rows(data['occurrences']).length} 次上课安排',
                          ),
                        ],
                      ),
                      if (focus != null) ...[
                        const Divider(height: 24),
                        Text(
                          selected != null
                              ? '这次上课'
                              : next != null
                              ? '下次上课'
                              : '最近一次上课',
                          style: const TextStyle(
                            fontSize: 13,
                            color: CampusColors.muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          displayInterval(focus['start_at'], focus['end_at']),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ('${focus['location'] ?? ''}'.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${focus['location']}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AppButton.icon(
                onPressed: () async {
                  final kind = await showAppSheet<String>(
                    context: context,
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
                label: const Text('添加作业或考试'),
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
              if (focus != null)
                RecordActionTile(
                  title: '本次听课',
                  subtitle: focus['attendance_status'] == 'leave'
                      ? '已请假 · 原课程保留'
                      : focus['attendance_status'] == 'plan_leave'
                      ? '准备请假 · 仍保留时间占用'
                      : '正常上课',
                  icon: Icons.person_outline_rounded,
                  onTap: !fresh
                      ? null
                      : () async {
                          final kind = await showAppSheet<String>(
                            context: context,
                            builder: (sheet) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                12,
                                20,
                                24,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    displayInterval(
                                      focus['start_at'],
                                      focus['end_at'],
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  for (final option in {
                                    'plan_leave': (
                                      '准备请假',
                                      '先记录打算，继续保留课程占用',
                                      Icons.pending_actions_rounded,
                                    ),
                                    'leave': (
                                      '已请假',
                                      '本次无需到课，其他课次保持原样',
                                      Icons.event_available_outlined,
                                    ),
                                    'attend': (
                                      '正常上课',
                                      '撤销本次请假或请假打算',
                                      Icons.school_outlined,
                                    ),
                                  }.entries)
                                    RecordActionTile(
                                      title: option.value.$1,
                                      subtitle: option.value.$2,
                                      icon: option.value.$3,
                                      onTap: () =>
                                          Navigator.pop(sheet, option.key),
                                    ),
                                ],
                              ),
                            ),
                          );
                          if (kind == null || !context.mounted) return;
                          try {
                            final preview = await controller.changeRequest(
                              'POST',
                              '/semesters/${data['semester']['id']}/changes',
                              data: {
                                'kind': kind,
                                'targets': [focus['id']],
                                'title': course['title'],
                                'source_text': kind == 'leave'
                                    ? '用户确认本次课程已请假'
                                    : kind == 'plan_leave'
                                    ? '用户准备为本次课程请假'
                                    : '用户恢复本次正常上课',
                              },
                            );
                            if (!context.mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChangePreviewPage(
                                  controller: controller,
                                  preview: preview,
                                ),
                              ),
                            );
                            await reload();
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(userError(error))),
                              );
                            }
                          }
                        },
                ),
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
                      subtitle:
                          '${e['location'] ?? ''}'.trim().isNotEmpty ||
                              e['changed'] == true ||
                              e['attendance_status'] != null
                          ? Text(
                              [
                                if (e['attendance_status'] == 'leave') '已请假',
                                if (e['attendance_status'] == 'plan_leave')
                                  '待请假',
                                if ('${e['location'] ?? ''}'.trim().isNotEmpty)
                                  '${e['location']}',
                                if (e['changed'] == true) '已变更',
                              ].join(' · '),
                            )
                          : null,
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

Widget changeCard(Map<String, dynamic> change, {VoidCallback? onOpen}) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CourseChangeSummary(change: change, onOpen: onOpen),
        const Divider(height: 16),
      ],
    );

class _CourseMeta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CourseMeta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: CampusColors.muted),
      const SizedBox(width: 6),
      Flexible(child: Text(text, style: const TextStyle(fontSize: 14))),
    ],
  );
}

class _CourseArrangementChoice extends StatelessWidget {
  final Map<String, dynamic> detail, semester;
  final VoidCallback onTap;
  const _CourseArrangementChoice({
    required this.detail,
    required this.semester,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final course = Map<String, dynamic>.from(detail['course']);
    final sections = List<int>.from(course['sections']);
    final weeks = List<int>.from(course['weeks']);
    final periods =
        List<Map<String, dynamic>>.from(
            semester['periods'] ?? [],
          ).where((p) => sections.contains(p['number'])).toList()
          ..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
    final consecutive =
        sections.length <= 1 ||
        List.generate(
          sections.length - 1,
          (i) => sections[i + 1] - sections[i],
        ).every((difference) => difference == 1);
    final clock = course['start_time'] != null && course['end_time'] != null
        ? '${course['start_time']}–${course['end_time']}'
        : consecutive && periods.isNotEmpty && periods.length == sections.length
        ? '${periods.first['start']}–${periods.last['end']}'
        : null;
    final rawLocation = '${course['location'] ?? ''}'.trim();
    final location =
        {
          '待定',
          '待通知',
          '待确认',
          '未确定',
          '未填写',
          '暂无',
          'unknown',
          'unspecified',
          'none',
        }.contains(rawLocation)
        ? ''
        : rawLocation;
    return AppTile(
      key: ValueKey('course-arrangement-${detail['id']}'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      leading: const Icon(Icons.calendar_view_week_outlined),
      title: Text(
        '周${'一二三四五六日'[(course['weekday'] as int) - 1]} · '
        '${formatNumberSelection(sections, unit: '节')}',
      ),
      subtitle: Text(
        [
          if (weeks.isNotEmpty) formatNumberSelection(weeks, unit: '周'),
          ?clock,
          if (location.isNotEmpty) location,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
