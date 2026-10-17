import 'dart:async';
import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/task_surfaces.dart';
import '../../ui/empty_scene.dart';
import '../../ui/v2/motion/skeleton.dart';
import '../../ui/v2/motion/rolling_number.dart';
import '../../ui/v2/shiri_tokens.dart' show ShiriRadius;
import 'tag_intelligence.dart';
import 'tag_records_page.dart';

class TagManagementController extends ChangeNotifier {
  final ItemsController items;
  final String? owner, semesterId;
  final int generation;
  bool busy = false, _closed = false, _invalidated = false;
  String? error, notice;
  List<Map<String, dynamic>> tags = [];
  Map<String, dynamic>? preview;
  TagManagementController(this.items)
    : owner = items.owner,
      semesterId = items.semesterId,
      generation = items.api.generation {
    items.addListener(_scopeChanged);
  }
  bool get active =>
      !_closed &&
      !_invalidated &&
      owner != null &&
      owner == items.owner &&
      generation == items.api.generation &&
      semesterId == items.semesterId;
  void _scopeChanged() {
    if (!active && !_closed) {
      _invalidated = true;
      tags = [];
      preview = null;
      busy = false;
      notifyListeners();
    }
  }

  void emit() {
    if (!_closed) notifyListeners();
  }

  Map<String, dynamic> owned(dynamic value) {
    final result = Map<String, dynamic>.from(value);
    if (result['owner_id'] != owner) throw ApiFailure('标签账号不一致，请重新打开');
    return result;
  }

  Future<void> _fetchTags() async {
    final data = await items.api.request('GET', '/tags');
    if (!active) return;
    final result = owned(data);
    tags = TagIntelligence.organize(items.rows(result['tags']));
  }

  void _observe(Map<String, dynamic> receipt) {
    for (final row in items.rows(receipt['semesters'])) {
      if (row['id'] == semesterId && row['revision'] is int) {
        items.observeRevision(row['id'], row['revision']);
      }
    }
  }

  Future<void> _organize() async {
    var changed = false;
    try {
      final value = await items.api.request('POST', '/tags/organize', data: {});
      if (!active) return;
      final result = owned(value);
      changed =
          (result['merged'] as int? ?? 0) + (result['renamed'] as int? ?? 0) >
          0;
      _observe(result);
    } on ApiFailure catch (e) {
      if (!active) return;
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
      // Older servers already have safe, version-checked rename/merge APIs.
      // Run those automatically; no suggestion card or confirmation dialog.
      final limit = tags.length * 2 + 1;
      for (var attempt = 0; active && attempt < limit; attempt++) {
        final source = tags
            .where(
              (t) => TagIntelligence.standardName('${t['name']}') != t['name'],
            )
            .firstOrNull;
        if (source == null) break;
        final name = TagIntelligence.standardName('${source['name']}');
        final target = tags
            .where((t) => t['id'] != source['id'] && t['name'] == name)
            .firstOrNull;
        final preview = owned(
          await items.api.request(
            'POST',
            '/tags/preview',
            data: {
              'operation': target == null ? 'rename' : 'merge',
              'source_id': source['id'],
              if (target == null) 'name': name else 'target_id': target['id'],
            },
          ),
        );
        if (!active) return;
        final receipt = owned(
          await items.api.request(
            'POST',
            '/tags/changes/${preview['token']}/apply',
            data: {},
          ),
        );
        if (!active) return;
        _observe(receipt);
        changed = true;
        await _fetchTags();
      }
    }
    if (changed && active) {
      // Refresh other views without making tag management wait for calendar,
      // risk and notification synchronization to finish.
      unawaited(items.refresh());
      if (active) await _fetchTags();
    }
  }

  Future<void> load() async {
    if (!active || busy) return;
    busy = true;
    error = null;
    emit();
    try {
      await _fetchTags();
      if (active) await _organize();
    } catch (e) {
      if (active) error = userError(e);
    } finally {
      if (active) {
        busy = false;
        emit();
      }
    }
  }

  Future<void> prepare(
    String sourceId, {
    String? name,
    String? targetId,
  }) async {
    if (!active || busy) return;
    busy = true;
    error = notice = null;
    preview = null;
    emit();
    try {
      final value = await items.api.request(
        'POST',
        '/tags/preview',
        data: {
          'operation': targetId == null ? 'rename' : 'merge',
          'source_id': sourceId,
          'target_id': ?targetId,
          'name': ?name,
        },
      );
      if (active) preview = owned(value);
    } catch (e) {
      if (active) error = userError(e);
    } finally {
      if (active) {
        busy = false;
        emit();
      }
    }
  }

  void cancelPreview() {
    if (busy) return;
    preview = null;
    error = null;
    emit();
  }

  Future<void> apply() async {
    if (!active || busy || preview == null) return;
    final token = preview!['token'];
    busy = true;
    error = notice = null;
    emit();
    try {
      final value = await items.api.request(
        'POST',
        '/tags/changes/$token/apply',
        data: {},
      );
      if (!active) return;
      final receipt = owned(value);
      if (receipt['token'] != token) throw ApiFailure('标签回执不一致，请重新核对');
      for (final row in items.rows(receipt['semesters'])) {
        if (row['id'] == semesterId && row['revision'] is int) {
          items.observeRevision(row['id'], row['revision']);
        }
      }
      preview = null;
      notice = '标签已更新';
      await items.refresh();
      if (active) await _fetchTags();
    } catch (e) {
      if (active) {
        error = userError(e);
        if (e is ApiFailure && (e.statusCode == 409 || e.statusCode == 404)) {
          preview = null;
        }
      }
    } finally {
      if (active) {
        busy = false;
        emit();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    items.removeListener(_scopeChanged);
    super.dispose();
  }
}

class TagManagementPage extends StatefulWidget {
  final ItemsController controller;
  const TagManagementPage({super.key, required this.controller});
  @override
  State<TagManagementPage> createState() => _TagManagementPageState();
}

class _TagManagementPageState extends State<TagManagementPage> {
  late final TagManagementController c;
  String query = '';
  List<Map<String, dynamic>> get visibleTags => c.tags.where((tag) {
    final group = TagIntelligence.groups.firstWhere(
      (g) => g['id'] == tag['group_id'],
    );
    return (query.isNotEmpty &&
            TagIntelligence.canonicalName('${tag['name']}') ==
                TagIntelligence.canonicalName(query)) ||
        TagIntelligence.normalize(
          '${tag['name']} ${group['name']} ${(tag['aliases'] as List? ?? []).join(' ')}',
        ).contains(TagIntelligence.normalize(query));
  }).toList();
  @override
  void initState() {
    super.initState();
    c = TagManagementController(widget.controller)..addListener(_changed);
    c.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> openTag(Map<String, dynamic> tag) async {
    if (!c.active || c.busy || c.preview != null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TagRecordsPage(controller: widget.controller, tag: tag),
      ),
    );
    if (mounted && c.active) await c.load();
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    super.dispose();
  }

  Future<void> rename(Map<String, dynamic> tag) async {
    var input = tag['name'] as String;
    final form = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('重命名标签'),
        content: Form(
          key: form,
          child: AppFormField(
            initialValue: input,
            onChanged: (value) => input = value,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(labelText: '新名称'),
            validator: (value) =>
                value?.trim().isNotEmpty == true ? null : '请输入标签名称',
          ),
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppButton(
            onPressed: () {
              if (validateAppForm(form)) {
                Navigator.pop(context, input.trim());
              }
            },
            child: const Text('查看影响'),
          ),
        ],
      ),
    );
    if (mounted && name != null && name.isNotEmpty) {
      await c.prepare(tag['id'], name: name);
    }
  }

  Future<void> merge(Map<String, dynamic> tag) async {
    var query = '';
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('将“${tag['name']}”合并到'),
        content: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final matches = c.tags
                .where(
                  (other) =>
                      other['id'] != tag['id'] &&
                      '${other['name']}'.toLowerCase().contains(
                        query.trim().toLowerCase(),
                      ),
                )
                .toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppField(
                  decoration: const InputDecoration(
                    labelText: '搜索合并目标',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setDialogState(() => query = value),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.maxFinite,
                  height:
                      (matches.length *
                              72.0 *
                              MediaQuery.textScalerOf(dialogContext).scale(1))
                          .clamp(80.0, 240.0)
                          .toDouble(),
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      for (final other in matches)
                        AppTile(
                          onTap: () => Navigator.pop(context, other['id']),
                          leading: const Icon(Icons.label_outline),
                          title: Text(other['name']),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                      if (matches.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('没有匹配的标签，请修改搜索词。'),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (mounted && target != null) await c.prepare(tag['id'], targetId: target);
  }

  Widget previewCard(Map<String, dynamic> p) {
    final merge = p['operation'] == 'merge';
    final counts = Map<String, dynamic>.from(p['affected']);
    final semesters = widget.controller.rows(p['semesters']);
    return EditorSection(
      title: merge ? '核对标签合并' : '核对重命名',
      icon: merge ? Icons.merge_type_rounded : Icons.drive_file_rename_outline,
      accent: CampusColors.teal,
      children: [
        TaskChangeFacts(
          beforeLabel: '原标签',
          afterLabel: merge ? '合并到' : '新名称',
          before: '${p['source']['name']}',
          after: '${p['target']['name']}',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 24,
          runSpacing: 16,
          children: [
            for (final entry in {
              'items': '事项',
              'events': '日程',
              'plans': '计划',
              'progress': '历史进度',
            }.entries)
              if (counts[entry.key] is num)
                Column(
                  key: ValueKey('tag-impact-${entry.key}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RollingNumber(
                      value: (counts[entry.key] as num).toInt(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: CampusColors.teal,
                      ),
                    ),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CampusColors.muted,
                      ),
                    ),
                  ],
                ),
          ],
        ),
        const SizedBox(height: 16),
        if (semesters.isNotEmpty)
          Text('涉及学期：${semesters.map((s) => s['name']).join('、')}'),
        const SizedBox(height: 8),
        Text(
          merge
              ? '旧标签将并入所选标签，重复标签只保留一个。历史统计同步归类，旧名称仍可识别。'
              : '相关记录将显示新名称，旧名称仍可识别。',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('标签管理'),
      actions: [
        AppIconButton(
          tooltip: '刷新标签',
          onPressed: c.busy || !c.active ? null : c.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    bottomNavigationBar: !c.active || c.preview == null
        ? null
        : ActionFooter(
            secondary: Align(
              alignment: Alignment.centerRight,
              child: AppTextButton(
                onPressed: c.busy ? null : c.cancelPreview,
                child: const Text('取消预览'),
              ),
            ),
            label: c.preview!['operation'] == 'merge' ? '确认合并' : '确认重命名',
            icon: Icons.check_rounded,
            onPressed: c.busy ? null : c.apply,
          ),
    body: !c.active
        ? const Center(child: Text('账号或学期已切换，请重新打开标签管理'))
        : AppLoadingOverlay(
            loading: c.busy,
            label: '正在更新',
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (c.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SoftNotice(c.error!, warning: true),
                  ),
                if (c.notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: SoftNotice(c.notice!),
                  ),
                if (c.preview != null) previewCard(c.preview!),
                if (c.busy && c.tags.isEmpty)
                  const SkeletonScope(
                    child: Column(
                      children: [
                        SkeletonBox(
                          height: 64,
                          borderRadius: ShiriRadius.smAll,
                        ),
                        SizedBox(height: 12),
                        SkeletonBox(
                          height: 64,
                          borderRadius: ShiriRadius.smAll,
                        ),
                        SizedBox(height: 12),
                        SkeletonBox(
                          height: 64,
                          borderRadius: ShiriRadius.smAll,
                        ),
                      ],
                    ),
                  ),
                if (!c.busy && c.tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        AppEmptyScene(kind: EmptySceneKind.tasks, size: 160),
                        SizedBox(height: 12),
                        Text('还没有标签。在事项或日程中添加标签后，即可在这里管理。'),
                      ],
                    ),
                  ),
                if (c.tags.isNotEmpty) ...[
                  AppField(
                    key: const Key('tag-management-search'),
                    decoration: const InputDecoration(
                      hintText: '搜索标签或分组',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  for (final group in TagIntelligence.groups)
                    if (visibleTags.any(
                      (tag) => tag['group_id'] == group['id'],
                    ))
                      tagGroup(
                        group,
                        visibleTags
                            .where((tag) => tag['group_id'] == group['id'])
                            .toList(),
                      ),
                  if (visibleTags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('没有匹配的标签'),
                    ),
                ],
              ],
            ),
          ),
  );

  Widget tagGroup(Map<String, String> group, List<Map<String, dynamic>> tags) =>
      Column(
        key: ValueKey('tag-group-${group['id']}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeading('${group['name']} · ${tags.length}'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(children: [for (final tag in tags) tagRow(tag)]),
          ),
        ],
      );

  Widget tagRow(Map<String, dynamic> tag) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CampusColors.line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final name = AppTile(
          key: ValueKey('open-tag-${tag['id']}'),
          onTap: c.busy || c.preview != null ? null : () => openTag(tag),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: CampusColors.muted,
            size: 18,
          ),
          title: Row(
            children: [
              const Icon(
                Icons.label_outline,
                size: 20,
                color: CampusColors.teal,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tag['name']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tag['usage_count'] is int)
                      Text(
                        '${tag['usage_count']}项使用',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        final actions = PopupMenuButton<String>(
          tooltip: '管理${tag['name']}',
          enabled: !c.busy && c.preview == null,
          icon: const Icon(Icons.more_horiz_rounded, color: CampusColors.muted),
          onSelected: (value) => value == 'rename' ? rename(tag) : merge(tag),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(
              value: 'merge',
              enabled: c.tags.length > 1,
              child: const Text('合并到'),
            ),
          ],
        );
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [name, const SizedBox(height: 4), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: name),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    ),
  );
}
