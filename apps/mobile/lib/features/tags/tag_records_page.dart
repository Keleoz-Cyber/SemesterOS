import 'package:flutter/material.dart';
import '../../core/api.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_loading.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import '../calendar/event_form.dart';
import '../items/item_detail.dart';
import '../items/item_widgets.dart';
import '../items/items_controller.dart';
import '../notices/notice_fields.dart';

class TagRecordsController extends ChangeNotifier {
  final ItemsController items;
  final String tagId;
  final String? owner, semesterId;
  final int generation;
  bool busy = false, hasMore = false, _closed = false;
  int _request = 0, total = 0;
  String? error;
  List<Map<String, dynamic>> records = [];
  final semesters = <String, Map<String, dynamic>>{};

  TagRecordsController(this.items, this.tagId)
    : owner = items.owner,
      generation = items.api.generation,
      semesterId = items.semesterId {
    items.addListener(_scopeChanged);
  }
  bool get active =>
      !_closed &&
      owner != null &&
      owner == items.owner &&
      generation == items.api.generation &&
      semesterId == items.semesterId;
  void _scopeChanged() {
    if (!active && !_closed) {
      records = [];
      semesters.clear();
      notifyListeners();
    }
  }

  Future<void> load({bool next = false}) async {
    if (!active || busy) return;
    final request = ++_request;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final value = Map<String, dynamic>.from(
        await items.api.request(
          'GET',
          '/tags/$tagId/records',
          queryParameters: {'offset': next ? records.length : 0, 'limit': 50},
        ),
      );
      if (!active || request != _request) return;
      if (value['owner_id'] != owner) throw ApiFailure('标签账号已变化，请重新打开');
      final incoming = items.rows(value['records']);
      records = next ? [...records, ...incoming] : incoming;
      if (!next) semesters.clear();
      for (final semester in items.rows(value['semesters'])) {
        semesters['${semester['id']}'] = semester;
      }
      total = value['total'] as int;
      hasMore = value['has_more'] == true;
    } catch (e) {
      if (active && request == _request) error = userError(e);
    } finally {
      if (active && request == _request) {
        busy = false;
        notifyListeners();
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

class TagRecordsPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> tag;
  const TagRecordsPage({
    super.key,
    required this.controller,
    required this.tag,
  });
  @override
  State<TagRecordsPage> createState() => _TagRecordsPageState();
}

class _TagRecordsPageState extends State<TagRecordsPage> {
  late final c = TagRecordsController(widget.controller, '${widget.tag['id']}');
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
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

  Future<void> open(Map<String, dynamic> row) async {
    final semester = c.semesters[row['semester_id']];
    if (!c.active || semester == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TagRecordDetail(
          controller: widget.controller,
          semester: semester,
          record: row,
        ),
      ),
    );
    if (mounted && c.active) await c.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${widget.tag['name']}'),
      actions: [
        AppIconButton(
          tooltip: '刷新事项',
          onPressed: c.active && !c.busy ? c.load : null,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: !c.active
        ? const Center(child: Text('账号或学期已切换，请重新打开'))
        : AppLoadingOverlay(
            loading: c.busy,
            child: RefreshIndicator(
              onRefresh: c.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (c.error != null) ...[
                    SoftNotice(c.error!, warning: true),
                    AppTextButton(
                      onPressed: c.busy
                          ? null
                          : () => c.load(next: c.records.isNotEmpty),
                      child: const Text('重新加载'),
                    ),
                  ],
                  if (!c.busy && c.error == null && c.records.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 64),
                      child: Center(child: Text('这个标签下还没有事项或日程')),
                    ),
                  if (c.records.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        '共${c.total}项',
                        style: const TextStyle(color: CampusColors.muted),
                      ),
                    ),
                    for (final row in c.records)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: AppTile(
                            key: ValueKey(
                              'tag-record-${row['resource_type']}-${row['id']}',
                            ),
                            leading: Icon(
                              row['resource_type'] == 'event'
                                  ? Icons.event_outlined
                                  : Icons.task_alt_rounded,
                            ),
                            title: Text('${row['title']}'),
                            subtitle: Text(
                              [
                                [
                                  row['resource_type'] == 'event'
                                      ? '日程'
                                      : kindLabel(row['kind']),
                                  if (row['lifecycle'] == 'completed') '已完成',
                                  if (row['lifecycle'] == 'cancelled') '已取消',
                                ].join(' · '),
                                noticeTime(
                                  row['time'],
                                  task:
                                      row['resource_type'] != 'event' &&
                                      row['kind'] != 'exam',
                                ),
                                '${row['location'] ?? ''}',
                                if (row['semester_id'] != c.semesterId)
                                  '${c.semesters[row['semester_id']]?['name'] ?? ''}',
                              ].where((s) => s.isNotEmpty).join('\n'),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: CampusColors.muted,
                            ),
                            onTap: () => open(row),
                          ),
                        ),
                      ),
                    if (c.hasMore)
                      AppTextButton(
                        onPressed: c.busy ? null : () => c.load(next: true),
                        child: const Text('加载更多'),
                      ),
                  ],
                ],
              ),
            ),
          ),
  );
}

/// Other semesters get their own controller, so editing never changes the
/// semester selected in the main app or writes through its current scope.
class _TagRecordDetail extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester, record;
  const _TagRecordDetail({
    required this.controller,
    required this.semester,
    required this.record,
  });
  @override
  State<_TagRecordDetail> createState() => _TagRecordDetailState();
}

class _TagRecordDetailState extends State<_TagRecordDetail> {
  ItemsController? scoped;
  bool ready = false;
  String? error;
  late final generation = widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    if (widget.controller.semesterId == widget.semester['id']) {
      ready = true;
    } else {
      scoped =
          ItemsController(
              widget.controller.api,
              widget.controller.cache,
              widget.controller.reminders,
            )
            ..onUnauthorized = widget.controller.onUnauthorized
            ..onRealityChanged = widget.controller.onRealityChanged;
      bind();
    }
  }

  Future<void> bind() async {
    setState(() => error = null);
    try {
      await scoped!.bind(widget.semester['id']);
      if (mounted && generation == widget.controller.api.generation) {
        setState(() => ready = true);
      }
    } catch (e) {
      if (mounted && generation == widget.controller.api.generation) {
        setState(() => error = userError(e));
      }
    }
  }

  @override
  void dispose() {
    scoped?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (generation != widget.controller.api.generation) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('账号已切换，请重新打开')),
      );
    }
    if (!ready) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error!),
                    AppTextButton(onPressed: bind, child: const Text('重新加载')),
                  ],
                ),
        ),
      );
    }
    final controller = scoped ?? widget.controller;
    return widget.record['resource_type'] == 'event'
        ? EventDetailPage(
            controller: controller,
            semester: widget.semester,
            eventId: widget.record['id'],
          )
        : ItemDetailPage(
            controller: controller,
            semester: widget.semester,
            id: widget.record['id'],
          );
  }
}
