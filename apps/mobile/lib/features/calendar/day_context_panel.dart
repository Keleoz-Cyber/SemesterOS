import '../../ui/app_controls.dart';
import 'calendar_repository.dart' show calendarDate;
import 'dart:async';
import 'package:flutter/material.dart';
import '../items/items_controller.dart';
import '../home/day_brief_controller.dart';
import '../../ui/assistant_scope.dart';
import '../../ui/campus_theme.dart';

class DayContextPanel extends StatefulWidget {
  final ItemsController items;
  final String semesterId;
  final DateTime day;
  final int revision;
  const DayContextPanel({
    super.key,
    required this.items,
    required this.semesterId,
    required this.day,
    required this.revision,
  });
  @override
  State<DayContextPanel> createState() => _DayContextPanelState();
}

class _DayContextPanelState extends State<DayContextPanel>
    with WidgetsBindingObserver {
  late final DayBriefController c;
  Timer? timer;
  bool active = true, foreground = true;
  bool get fresh =>
      c.fresh(widget.revision) &&
      c.data?['semester_id'] == widget.semesterId &&
      c.data?['date'] == calendarDate(widget.day);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c = DayBriefController(widget.items.api, widget.items.cache)
      ..addListener(changed);
    reload();
  }

  void updateTimer() {
    timer?.cancel();
    timer = null;
    if (active && foreground) {
      timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted && !c.busy && !fresh) reload();
      });
    }
  }

  void changed() {
    if (mounted && active) setState(() {});
  }

  Future<void> reload() => c.load(widget.semesterId, widget.day);
  @override
  void didUpdateWidget(covariant DayContextPanel old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day ||
        old.revision != widget.revision ||
        old.semesterId != widget.semesterId) {
      if (active) reload();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final old = active;
    active = TickerMode.valuesOf(context).enabled;
    updateTimer();
    if (active && !old && !fresh) reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateTimer();
    if (foreground && active && !fresh) reload();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!fresh) {
      return c.error != null
          ? Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                onPressed: c.busy ? null : reload,
                child: const Text('重新查看安排提示'),
              ),
            )
          : const SizedBox();
    }
    if (c.suggestions.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.day.month}月${widget.day.day}日 · 安排提示',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final r in c.suggestions.take(3))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                color: r['kind'] == 'free_window'
                    ? CampusColors.tealSoft
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: r['kind'] == 'free_window'
                        ? CampusColors.teal
                        : CampusColors.primary,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        r['kind'] == 'free_window'
                            ? Icons.schedule_rounded
                            : Icons.info_outline_rounded,
                        size: 20,
                        color: r['kind'] == 'free_window'
                            ? CampusColors.teal
                            : CampusColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r['title'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ('${r['detail'] ?? ''}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        r['detail'],
                        style: const TextStyle(
                          color: CampusColors.muted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppTextButton.icon(
                      onPressed: () => AssistantScope.open(
                        context,
                        initialText: r['request'],
                        autoSubmit: true,
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: Text(r['action_label']),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
