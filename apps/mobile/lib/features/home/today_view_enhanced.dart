import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_selection.dart';
import '../../ui/breathing_card.dart';
import '../../ui/campus_theme.dart';
import '../../ui/empty_scene.dart';
import '../../ui/time_river.dart';
import '../calendar/calendar_repository.dart';
import '../items/item_widgets.dart';
import 'home_preferences.dart';

/// Live Today modes share the same event/task data. Explicit choices and task
/// ordering persist through the parent's owner-and-semester-scoped store.
class TodayViewSwitch extends StatefulWidget {
  final List<Map<String, dynamic>> timeline;
  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> otherEntries;
  final DateTime now;
  final DateTime day;
  final ValueChanged<Map<String, dynamic>> onEventTap;
  final ValueChanged<Map<String, dynamic>> onTaskTap;
  final ValueChanged<Map<String, dynamic>>? onTaskEdit;
  final VoidCallback? onAllTasks;
  final HomePreferences? preferences;
  final bool dayFinished;
  final bool scheduleAvailable;
  final bool scheduleLoading;
  final Widget? scheduleLeading;
  const TodayViewSwitch({
    super.key,
    required this.timeline,
    required this.tasks,
    this.otherEntries = const [],
    required this.now,
    required this.day,
    required this.onEventTap,
    required this.onTaskTap,
    this.onTaskEdit,
    this.onAllTasks,
    this.preferences,
    this.dayFinished = false,
    this.scheduleAvailable = true,
    this.scheduleLoading = false,
    this.scheduleLeading,
  });
  @override
  State<TodayViewSwitch> createState() => _TodayViewSwitchState();
}

class _TodayViewSwitchState extends State<TodayViewSwitch>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  TodayViewMode? _localChoice;
  List<String> _localOrder = [];
  late final AnimationController _contentMotion;
  late final CurvedAnimation _contentCurve;
  double _slideFrom = .035;
  bool _foreground = true;
  bool _ordering = false;

  @override
  void initState() {
    super.initState();
    _contentMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _contentCurve = CurvedAnimation(
      parent: _contentMotion,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _canAnimate =>
      _foreground &&
      !MediaQuery.disableAnimationsOf(context) &&
      !MediaQuery.accessibleNavigationOf(context) &&
      TickerMode.valuesOf(context).enabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canAnimate) {
      _contentMotion.stop();
      _contentMotion.value = 1;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _contentMotion.stop();
      _contentMotion.value = 1;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contentCurve.dispose();
    _contentMotion.dispose();
    super.dispose();
  }

  TodayViewMode get _mode =>
      widget.preferences?.todayView ??
      _localChoice ??
      defaultTodayViewMode(
        events: widget.timeline.length + widget.otherEntries.length,
        tasks: widget.tasks.length,
      );
  Future<void> _save({TodayViewMode? mode, List<String>? order}) async {
    final changingMode = mode != null && mode != _mode;
    setState(() {
      if (mode != null) {
        _localChoice = mode;
        _ordering = false;
      }
      if (order != null) _localOrder = order;
      if (changingMode) {
        _slideFrom = mode == TodayViewMode.tasks ? .035 : -.035;
      }
    });
    if (changingMode) {
      if (_canAnimate) {
        _contentMotion.forward(from: 0);
      } else {
        _contentMotion.value = 1;
      }
    }
    try {
      await widget.preferences?.change(todayView: mode, taskOrder: order);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('本机视图设置未保存，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppSegmentedControl<TodayViewMode>(
        value: _mode,
        options: const {
          TodayViewMode.schedule: '日程',
          TodayViewMode.tasks: '待办',
        },
        onChanged: (mode) => _save(mode: mode),
      ),
      const SizedBox(height: 8),
      // Only the incoming body moves. The control and the dashboard header
      // retain their place; rapid taps never stack outgoing interactive views.
      ClipRect(
        child: FadeTransition(
          opacity: _contentCurve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(_slideFrom, 0),
              end: Offset.zero,
            ).animate(_contentCurve),
            child: KeyedSubtree(
              key: ValueKey(_mode),
              child: _mode == TodayViewMode.schedule
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.scheduleLeading != null)
                          widget.scheduleLeading!,
                        _schedule(),
                      ],
                    )
                  : _tasks(),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _schedule() {
    if (!widget.scheduleAvailable &&
        widget.timeline.isEmpty &&
        widget.otherEntries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          widget.scheduleLoading ? '正在读取今日安排…' : '暂时无法读取今日安排',
          style: const TextStyle(color: CampusColors.muted),
        ),
      );
    }
    final rail = widget.timeline.isEmpty
        ? widget.otherEntries.isEmpty
              ? const _TodayEmptyView(
                  kind: EmptySceneKind.agenda,
                  title: '今天没有安排',
                )
              : const SizedBox.shrink()
        : TimeRiverView(
            events: widget.timeline,
            now: widget.now,
            day: widget.day,
            showNow: !widget.dayFinished,
            onEventTap: widget.onEventTap,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.dayFinished)
          AppDisclosure(
            title: Text('今天已结束 · ${widget.timeline.length}项'),
            children: [rail],
          )
        else
          rail,
        if (widget.otherEntries.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              '其他事项',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final row in widget.otherEntries)
            AppTile(
              onTap: () => widget.onEventTap(row),
              title: Text('${row['title'] ?? ''}'),
              subtitle: calendarTimeLabel(row, includeMissing: false).isEmpty
                  ? null
                  : Text(calendarTimeLabel(row, includeMissing: false)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
            ),
        ],
      ],
    );
  }

  Widget _tasks() {
    if (widget.tasks.isEmpty) {
      return const _TodayEmptyView(kind: EmptySceneKind.tasks, title: '暂无待办事项');
    }
    final order = widget.preferences?.taskOrder ?? _localOrder;
    final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
    final sourceIndex = {
      for (var i = 0; i < widget.tasks.length; i++)
        '${widget.tasks[i]['id']}': i,
    };
    final tasks = [...widget.tasks]
      ..sort((a, b) {
        final aRank = rank['${a['id']}'], bRank = rank['${b['id']}'];
        if (aRank != null || bRank != null) {
          return (aRank ?? order.length).compareTo(bRank ?? order.length);
        }
        final aDue = itemDeadline(a), bDue = itemDeadline(b);
        final byDeadline = (aDue ?? DateTime.utc(9999)).compareTo(
          bDue ?? DateTime.utc(9999),
        );
        return byDeadline != 0
            ? byDeadline
            : sourceIndex['${a['id']}']!.compareTo(sourceIndex['${b['id']}']!);
      });
    final previewCount = tasks.length < 8 ? tasks.length : 8;
    final list = ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: previewCount,
      onReorderItem: (oldIndex, newIndex) {
        final next = tasks.map((row) => '${row['id']}').toList();
        next.insert(newIndex, next.removeAt(oldIndex));
        final remainingIds = next.toSet();
        next.addAll(order.where((id) => !remainingIds.contains(id)));
        _save(order: next);
      },
      itemBuilder: (context, index) {
        final task = tasks[index];
        return Padding(
          key: ValueKey('today-task-${task['id']}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ItemCard(
                  item: task,
                  onTap: () => widget.onTaskTap(task),
                  onDoubleTap: widget.onTaskEdit == null
                      ? null
                      : () => widget.onTaskEdit!(task),
                ),
              ),
              if (_ordering)
                Column(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Semantics(
                        label: '拖动调整 ${task['title']} 的顺序',
                        child: const Tooltip(
                          message: '拖动排序',
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.drag_handle_rounded,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tasks.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: AppTextButton.icon(
              guardAsync: false,
              onPressed: () => setState(() => _ordering = !_ordering),
              icon: Icon(
                _ordering ? Icons.done_rounded : Icons.swap_vert_rounded,
                size: 18,
              ),
              label: Text(_ordering ? '完成排序' : '调整顺序'),
            ),
          ),
        list,
        if (tasks.length > previewCount)
          AppTextButton(
            onPressed: widget.onAllTasks,
            child: Text('查看全部 ${tasks.length} 项'),
          ),
      ],
    );
  }
}

class _TodayEmptyView extends StatelessWidget {
  final EmptySceneKind kind;
  final String title;
  const _TodayEmptyView({required this.kind, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      children: [
        AppEmptyScene(kind: kind),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: CampusColors.muted,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// The single top-priority cue uses only a known deadline for countdown/color.
class UrgentItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final DateTime? now;
  const UrgentItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.now,
  });
  @override
  Widget build(BuildContext context) {
    final due = itemDeadline(item, schoolClock: true);
    final remaining = due?.difference(now ?? schoolNow()).inMinutes;
    final color = TimeUrgency.getColor(remaining);
    return BreathingCard(
      key: ValueKey('urgent-cue-${item['id']}'),
      remainingMinutes: remaining,
      enabled: remaining != null && remaining > 0 && remaining < 120,
      child: Material(
        color: remaining == null
            ? CampusColors.blueSoft
            : color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.priority_high_rounded, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remaining == null
                            ? '优先处理'
                            : TimeUrgency.getLabel(remaining),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item['title'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (itemTimeLabel(item).isNotEmpty)
                        Text(
                          itemTimeLabel(item),
                          style: const TextStyle(
                            fontSize: 12,
                            color: CampusColors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
