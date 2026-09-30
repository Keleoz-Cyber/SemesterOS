import '../../ui/app_controls.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/app_selection.dart';
import '../items/items_controller.dart';
import '../calendar/calendar_repository.dart';
import 'insights_controller.dart';

class InsightsPage extends StatefulWidget {
  final ItemsController controller;
  final Map<String, dynamic> semester;
  final Map<String, String> initialQuery;
  const InsightsPage({
    super.key,
    required this.controller,
    required this.semester,
    this.initialQuery = const {},
  });
  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late final InsightsController c;
  String mode = 'scheduled', range = 'week';
  String? selectedDate;
  int visible = 30;
  static const colors = {
    'study': CampusColors.primary,
    'research': CampusColors.teal,
    'affairs': CampusColors.warning,
    'life': CampusColors.chartPurple,
    'unclassified': CampusColors.muted,
  };
  static const names = {
    'study': '学业',
    'research': '科研',
    'affairs': '校园事务',
    'life': '生活',
    'unclassified': '未分类',
  };
  DateTime get termStart => DateTime.parse(widget.semester['first_monday']);
  DateTime get termEnd => termStart.add(
    Duration(days: (widget.semester['total_weeks'] as int) * 7 - 1),
  );
  DateTime get today {
    final now = schoolNow();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    final a = today.subtract(Duration(days: today.weekday - 1));
    c = InsightsController(
      widget.controller,
      widget.semester['id'],
      a,
      a.add(const Duration(days: 6)),
    );
    final initialFrom = DateTime.tryParse(widget.initialQuery['from'] ?? '');
    final initialTo = DateTime.tryParse(widget.initialQuery['to'] ?? '');
    if (initialFrom != null &&
        initialTo != null &&
        !initialTo.isBefore(initialFrom) &&
        initialTo.difference(initialFrom).inDays <= 365) {
      c.from = initialFrom;
      c.to = initialTo;
      range = initialFrom == termStart && initialTo == termEnd
          ? 'term'
          : 'custom';
    }
    final category = widget.initialQuery['category'];
    if (category != null && names.containsKey(category)) c.category = category;
    c.tags = (widget.initialQuery['tags'] ?? '')
        .split(',')
        .where((t) => t.isNotEmpty)
        .take(12)
        .toSet();
    c.load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> chooseRange(String value) async {
    DateTime a, b;
    if (value == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: termStart.subtract(const Duration(days: 366)),
        lastDate: termEnd.add(const Duration(days: 366)),
        initialDateRange: DateTimeRange(start: c.from, end: c.to),
        helpText: '选择统计日期',
      );
      if (picked == null || !mounted) return;
      if (picked.end.difference(picked.start).inDays > 365) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('每次最多查看366天')));
        }
        return;
      }
      a = picked.start;
      b = picked.end;
    } else if (value == 'term') {
      a = termStart;
      b = termEnd;
    } else if (value == 'month') {
      a = today.subtract(const Duration(days: 27));
      b = today;
    } else {
      a = today.subtract(Duration(days: today.weekday - 1));
      b = a.add(const Duration(days: 6));
    }
    setState(() {
      range = value;
      selectedDate = null;
      visible = 30;
    });
    await c.range(a, b);
  }

  String tagName(String id) {
    for (final tag in insightRows(c.data?['tags'])) {
      if (tag['id'] == id) return '${tag['name']}';
    }
    return '已选标签';
  }

  Future<void> chooseFilters() async {
    var category = c.category;
    final tags = {...c.tags};
    final availableTags = {
      for (final tag in insightRows(c.data?['tags']))
        '${tag['id']}': '${tag['name']}',
      for (final id in c.tags) id: tagName(id),
    };
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    '筛选统计',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      const Text(
                        '分类',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (final entry in <String?, String>{
                        null: '全部分类',
                        ...names,
                      }.entries)
                        AppTile(
                          key: ValueKey('category-${entry.key ?? 'all'}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          selected: category == entry.key,
                          selectedTileColor: CampusColors.blueSoft,
                          title: Text(entry.value),
                          trailing: Icon(
                            category == entry.key
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 22,
                          ),
                          onTap: () =>
                              setSheetState(() => category = entry.key),
                        ),
                      if (availableTags.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          '标签',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '可多选，包含任一标签即可',
                          style: TextStyle(
                            fontSize: 13,
                            color: CampusColors.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in availableTags.entries)
                              AppFilterChip(
                                label: Text(tag.value),
                                selected: tags.contains(tag.key),
                                onSelected: (selected) => setSheetState(() {
                                  selected
                                      ? tags.add(tag.key)
                                      : tags.remove(tag.key);
                                }),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
                    children: [
                      AppTextButton(
                        onPressed: () => setSheetState(() {
                          category = null;
                          tags.clear();
                        }),
                        child: const Text('重置'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: const Text('应用筛选'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (apply != true || !mounted) return;
    setState(() {
      selectedDate = null;
      visible = 30;
    });
    c.category = category;
    c.tags = tags;
    await c.load();
  }

  Duration get animation => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 350);
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('时间统计'),
        actions: [
          AppTextButton.icon(
            key: const ValueKey('insights-filters'),
            onPressed: chooseFilters,
            icon: const Icon(Icons.tune_rounded, size: 20),
            label: Text(
              c.category == null && c.tags.isEmpty
                  ? '筛选'
                  : '筛选 · ${c.tags.length + (c.category == null ? 0 : 1)}',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: c.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            Text(
              widget.semester['name'],
              style: const TextStyle(color: CampusColors.muted),
            ),
            const SizedBox(height: 12),
            AppSegmentedControl<String>(
              value: range,
              options: const {
                'week': '本周',
                'month': '近4周',
                'term': '本学期',
                'custom': '自定义',
              },
              onChanged: chooseRange,
            ),
            const SizedBox(height: 12),
            Text(
              '${calendarDate(c.from)} — ${calendarDate(c.to)}',
              style: const TextStyle(fontSize: 13, color: CampusColors.muted),
            ),
            const SizedBox(height: 16),
            if (c.category != null || c.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  if (c.category != null)
                    AppInputChip(
                      label: Text(names[c.category] ?? '分类'),
                      onDeleted: () {
                        selectedDate = null;
                        visible = 30;
                        c.filterCategory(null);
                      },
                    ),
                  for (final tagId in c.tags)
                    AppInputChip(
                      label: Text(tagName(tagId)),
                      onDeleted: () {
                        selectedDate = null;
                        visible = 30;
                        c.toggleTag(tagId);
                      },
                    ),
                ],
              ),
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            if (c.offline)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CampusColors.warningSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  c.data == null
                      ? (c.error ?? '暂时无法读取统计，请下拉重试。')
                      : '当前显示缓存统计，下拉可重新同步。',
                ),
              ),
            if (c.data != null)
              ExcludeSemantics(
                excluding: c.busy,
                child: IgnorePointer(
                  ignoring: c.busy,
                  child: AnimatedOpacity(
                    opacity: c.busy && !c.matchesCurrentQuery
                        ? 0
                        : c.busy
                        ? 0.5
                        : 1,
                    duration: c.busy && !c.matchesCurrentQuery
                        ? Duration.zero
                        : animation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: content(c.data!),
                    ),
                  ),
                ),
              ),
            if (c.data == null && !c.busy)
              AppTextButton(onPressed: c.load, child: const Text('重新加载')),
          ],
        ),
      ),
    ),
  );
  List<Widget> content(Map<String, dynamic> data) {
    final summary = Map<String, dynamic>.from(data['summary'] ?? {});
    final daily = insightRows(data['daily']);
    final categories = insightRows(data['categories']);
    final records = insightRows(
      data['records'],
    ).where((r) => matchesDay(r, selectedDate)).toList();
    final shown = records
        .where((r) => mode != 'actual' || r['resource_type'] == 'progress')
        .toList();
    return [
      const SizedBox(height: 10),
      overview(summary),
      const SizedBox(height: 12),
      Text(
        '日历占用已扣除重叠时段 · ${summary['entry_count'] ?? 0}条记录',
        style: const TextStyle(fontSize: 12, color: CampusColors.muted),
      ),
      if ((summary['unknown_duration_count'] as num? ?? 0) > 0 ||
          (summary['undated_count'] as num? ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${summary['unknown_duration_count'] ?? 0}条安排缺少起止时间 · ${summary['undated_count'] ?? 0}条日期待确认',
            style: const TextStyle(color: CampusColors.warning, fontSize: 12),
          ),
        ),
      const SizedBox(height: 24),
      AppSegmentedControl<String>(
        value: mode,
        options: const {'scheduled': '已安排', 'actual': '实际记录'},
        onChanged: (value) => setState(() {
          mode = value;
          selectedDate = null;
          visible = 30;
        }),
      ),
      const SizedBox(height: 14),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading(
              mode == 'scheduled' ? '每天的安排' : '每天记录的投入',
              sub: mode == 'scheduled' ? '点选柱形，查看当天来源' : '按进度录入日期统计',
            ),
            const SizedBox(height: 18),
            if (mode == 'actual' && summary['actual_minutes'] == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('还没有实际投入记录。完成任务后，可以在任务详情记录用时。'),
              )
            else
              trend(daily),
            if (selectedDate != null)
              Align(
                alignment: Alignment.centerLeft,
                child: AppInputChip(
                  label: Text('$selectedDate 的记录'),
                  onDeleted: () => setState(() => selectedDate = null),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading(
              '分类分布',
              sub: mode == 'scheduled' ? '按安排时长 · 重叠安排分别计入' : '按已填写的实际分钟数',
            ),
            const SizedBox(height: 14),
            distribution(categories),
            if (MediaQuery.textScalerOf(context).scale(1) <= 1.4)
              Wrap(
                spacing: 18,
                runSpacing: 10,
                children: [
                  for (final category in categories)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors[category['id']],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${category['name']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      heading(
        selectedDate == null ? '统计来源' : '$selectedDate 的来源',
        sub: '${shown.length}条',
      ),
      const SizedBox(height: 12),
      if (shown.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Text('这个范围内没有对应记录。')),
      for (final r in shown.take(visible)) sourceTile(r),
      if (shown.length > visible)
        AppTextButton(
          onPressed: () => setState(() => visible += 30),
          child: Text('继续查看（剩余${shown.length - visible}条）'),
        ),
      if (insightRows(data['undated']).isNotEmpty)
        AppDisclosure(
          tilePadding: EdgeInsets.zero,
          title: Text('日期待确认（${insightRows(data['undated']).length}条）'),
          subtitle: const Text('不分配到任意日期，也不计入本次时长'),
          children: [
            for (final r in insightRows(data['undated']).take(30))
              sourceTile(r),
          ],
        ),
      const SizedBox(height: 16),
      AppDisclosure(
        tilePadding: EdgeInsets.zero,
        title: const Text('统计口径'),
        children: [
          for (final d in Map<String, dynamic>.from(
            data['definitions'] ?? {},
          ).values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '$d',
                style: const TextStyle(fontSize: 13, color: CampusColors.muted),
              ),
            ),
        ],
      ),
    ];
  }

  Widget heading(String title, {String? sub}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      if (sub != null)
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            sub,
            style: const TextStyle(fontSize: 12, color: CampusColors.muted),
          ),
        ),
    ],
  );
  Widget panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
  Widget overview(Map<String, dynamic> summary) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.schedule_rounded, size: 20, color: CampusColors.primary),
            SizedBox(width: 8),
            Text(
              '日历占用',
              style: TextStyle(
                fontSize: 14,
                color: CampusColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: animation,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            insightHours(summary['occupied_union_minutes']),
            key: ValueKey(summary['occupied_union_minutes']),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: CampusColors.primary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 16),
        Wrap(
          spacing: 32,
          runSpacing: 16,
          children: [
            subtotal(
              '固定安排',
              summary['fixed_scheduled_minutes'],
              CampusColors.ink,
            ),
            subtotal(
              '个人计划',
              summary['personal_planned_minutes'],
              CampusColors.teal,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: CampusColors.tealSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 6,
            children: [
              const Text(
                '实际记录',
                style: TextStyle(fontSize: 14, color: CampusColors.teal),
              ),
              Text(
                insightHours(summary['actual_minutes']),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: CampusColors.teal,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget subtotal(String label, dynamic minutes, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 13, color: CampusColors.muted),
      ),
      const SizedBox(height: 4),
      Text(
        insightHours(minutes),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
  Widget trend(List<Map<String, dynamic>> daily) {
    if (daily.isEmpty) return const Text('暂无可绘制的数据');
    double amount(Map<String, dynamic> r) => mode == 'actual'
        ? (r['actual_minutes'] as num? ?? 0).toDouble() / 60
        : ((r['fixed_scheduled_minutes'] as num? ?? 0) +
                      (r['personal_planned_minutes'] as num? ?? 0))
                  .toDouble() /
              60;
    final maxValue = daily.map(amount).fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        SizedBox(
          height: 210 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 2,
          child: LayoutBuilder(
            builder: (context, size) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: daily.length > 14 ? daily.length * 25.0 : size.maxWidth,
                child: BarChart(
                  BarChartData(
                    maxY: (maxValue * 1.15).ceilToDouble(),
                    minY: 0,
                    barGroups: [
                      for (var i = 0; i < daily.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: amount(daily[i]),
                              width: daily.length > 14 ? 12 : 18,
                              borderRadius: BorderRadius.circular(5),
                              color: selectedDate == daily[i]['date']
                                  ? CampusColors.ink
                                  : CampusColors.primary,
                              rodStackItems: mode == 'actual'
                                  ? null
                                  : [
                                      BarChartRodStackItem(
                                        0,
                                        (daily[i]['fixed_scheduled_minutes']
                                                    as num? ??
                                                0) /
                                            60,
                                        CampusColors.primary,
                                      ),
                                      BarChartRodStackItem(
                                        (daily[i]['fixed_scheduled_minutes']
                                                    as num? ??
                                                0) /
                                            60,
                                        amount(daily[i]),
                                        CampusColors.teal,
                                      ),
                                    ],
                            ),
                          ],
                        ),
                    ],
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: CampusColors.line,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: MediaQuery.textScalerOf(
                            context,
                          ).scale(36),
                          getTitlesWidget: (value, meta) => Text(
                            '${value.toInt()}h',
                            style: const TextStyle(
                              fontSize: 12,
                              color: CampusColors.muted,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize:
                              MediaQuery.textScalerOf(context).scale(22) + 12,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= daily.length) {
                              return const SizedBox();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '${DateTime.parse(daily[i]['date']).day}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CampusColors.muted,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent && response?.spot != null) {
                          final i = response!.spot!.touchedBarGroupIndex;
                          if (i >= 0 && i < daily.length) {
                            setState(() => selectedDate = daily[i]['date']);
                          }
                        }
                      },
                    ),
                  ),
                  duration: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (mode == 'scheduled')
          const Text(
            '蓝色：固定安排　青色：个人计划',
            style: TextStyle(color: CampusColors.muted, fontSize: 11),
          ),
        // Text controls are also keyboard/screen-reader accessible and cover zero-height bars.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final d in daily)
                AppTextButton(
                  onPressed: () => setState(
                    () => selectedDate = selectedDate == d['date']
                        ? null
                        : d['date'],
                  ),
                  child: Text(
                    '${DateTime.parse(d['date']).month}/${DateTime.parse(d['date']).day} ${mode == 'actual' ? insightHours(d['actual_minutes']) : insightHours((d['fixed_scheduled_minutes'] as num? ?? 0) + (d['personal_planned_minutes'] as num? ?? 0))}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget distribution(List<Map<String, dynamic>> rows) {
    final key = mode == 'actual' ? 'actual_minutes' : 'scheduled_minutes';
    final parts = rows.where((r) => (r[key] as num? ?? 0) > 0).toList();
    final sum = parts.fold<num>(0, (v, r) => v + (r[key] as num));
    if (parts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 25),
        child: Text('暂无可统计的时长'),
      );
    }
    if (MediaQuery.textScalerOf(context).scale(1) > 1.4) {
      return Column(
        children: [
          for (final part in parts)
            AppTile(
              contentPadding: EdgeInsets.zero,
              title: Text(part['name']),
              subtitle: Text(insightHours(part[key])),
              trailing: Text('${((part[key] as num) / sum * 100).round()}%'),
              onTap: () {
                selectedDate = null;
                c.filterCategory(c.category == part['id'] ? null : part['id']);
              },
            ),
        ],
      );
    }
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Semantics(
            label: parts
                .map((r) => '${r['name']} ${insightHours(r[key])}')
                .join('，'),
            child: PieChart(
              PieChartData(
                centerSpaceRadius: 57,
                sectionsSpace: 4,
                startDegreeOffset: -90,
                sections: [
                  for (final p in parts)
                    PieChartSectionData(
                      value: (p[key] as num).toDouble(),
                      color: colors[p['id']],
                      radius: c.category == p['id'] ? 34 : 27,
                      title: '${((p[key] as num) / sum * 100).round()}%',
                      titleStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                ],
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    final index = response?.touchedSection?.touchedSectionIndex;
                    if (event is FlTapUpEvent &&
                        index != null &&
                        index >= 0 &&
                        index < parts.length) {
                      selectedDate = null;
                      c.filterCategory(
                        c.category == parts[index]['id']
                            ? null
                            : parts[index]['id'],
                      );
                    }
                  },
                ),
              ),
              duration: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  insightHours(sum),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  mode == 'actual' ? '实际记录' : '安排时长',
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
  }

  bool matchesDay(Map<String, dynamic> r, String? day) {
    if (day == null) return true;
    if (r['start_at'] != null) {
      final a = schoolTime(r['start_at']),
          b = r['end_at'] == null
              ? a.add(const Duration(microseconds: 1))
              : schoolTime(r['end_at']);
      final start = DateTime.parse(day);
      final wallA = DateTime(a.year, a.month, a.day, a.hour, a.minute),
          wallB = DateTime(
            b.year,
            b.month,
            b.day,
            b.hour,
            b.minute,
            b.second,
            b.millisecond,
            b.microsecond,
          );
      return wallA.isBefore(start.add(const Duration(days: 1))) &&
          wallB.isAfter(start);
    }
    if (r['due_at'] != null) {
      return calendarDate(schoolTime(r['due_at'])) == day;
    }
    if (r['date'] != null) {
      return '${r['date']}'.compareTo(day) <= 0 &&
          '${r['end_date'] ?? r['date']}'.compareTo(day) >= 0;
    }
    if (r['week'] != null) {
      final a = termStart.add(Duration(days: ((r['week'] as int) - 1) * 7));
      return !DateTime.parse(day).isBefore(a) &&
          DateTime.parse(day).isBefore(a.add(const Duration(days: 7)));
    }
    return false;
  }

  Widget sourceTile(Map<String, dynamic> r) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: AppTile(
        leading: Container(
          width: 5,
          height: 38,
          decoration: BoxDecoration(
            color: colors[r['category_id']] ?? CampusColors.muted,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          r['title'],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          r['resource_type'] == 'progress'
              ? '${r['date']} · 进度记录'
              : calendarTimeLabel(r),
        ),
        trailing: Text(
          insightHours(
            mode == 'actual' ? r['actual_minutes'] : r['scheduled_minutes'],
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onTap: () async {
          final id = r['resource_id'];
          if (id == null) return;
          await context.push(switch (r['resource_type']) {
            'course' => '/courses/$id',
            'event' => '/events/$id',
            'exam' => '/exams/$id',
            _ => '/items/$id',
          });
          if (mounted) await c.load();
        },
      ),
    ),
  );
}
