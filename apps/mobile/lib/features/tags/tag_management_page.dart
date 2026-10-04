import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';
import '../items/task_surfaces.dart';

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
    tags = items.rows(owned(data)['tags']);
  }

  Future<void> load() async {
    if (!active || busy) return;
    busy = true;
    error = null;
    emit();
    try {
      await _fetchTags();
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
  @override
  void initState() {
    super.initState();
    c = TagManagementController(widget.controller)..addListener(_changed);
    c.load();
  }

  void _changed() {
    if (mounted) setState(() {});
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
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('将“${tag['name']}”合并到'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final other in c.tags)
                  if (other['id'] != tag['id'])
                    AppTile(
                      onTap: () => Navigator.pop(context, other['id']),
                      leading: const Icon(Icons.label_outline),
                      title: Text(other['name']),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
              ],
            ),
          ),
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
                    Text(
                      '${counts[entry.key]}',
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton(
              onPressed: c.busy ? null : c.apply,
              child: Text(merge ? '确认合并' : '确认重命名'),
            ),
            AppTextButton(
              onPressed: c.busy ? null : c.cancelPreview,
              child: const Text('取消预览'),
            ),
          ],
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
    body: !c.active
        ? const Center(child: Text('账号或学期已切换，请重新打开标签管理'))
        : AppLoadingOverlay(
            loading: c.busy,
            label: '正在更新',
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  child: Text(
                    '所有学期共用 · ${c.tags.length}个标签',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                ),
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
                if (!c.busy && c.tags.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('还没有标签。在事项或日程中添加标签后，即可在这里管理。'),
                  ),
                if (c.tags.isNotEmpty) const SectionHeading('现有标签'),
                for (final tag in c.tags) tagRow(tag),
              ],
            ),
          ),
  );

  Widget tagRow(Map<String, dynamic> tag) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CampusColors.line)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final name = Row(
          children: [
            const Icon(Icons.label_outline, size: 20, color: CampusColors.teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${tag['name']}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: 4,
          children: [
            AppTextButton(
              onPressed: c.busy || c.preview != null ? null : () => rename(tag),
              child: const Text('重命名'),
            ),
            AppTextButton(
              onPressed: c.busy || c.preview != null || c.tags.length < 2
                  ? null
                  : () => merge(tag),
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
