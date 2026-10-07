import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../calendar/calendar_panel.dart';
import '../../ui/app_navigation.dart';
import '../../ui/motion.dart';
import '../../ui/assistant_scope.dart';
import '../../ui/brand.dart';
import '../media/clipboard_notice_prompt.dart';
import '../profile/student_profile_prompt.dart';
import '../agent/assistant_sheet.dart';
import '../home/today_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../core/api.dart' show userError;
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'semester_view.dart';
import '../items/items_controller.dart';
import '../items/items_view.dart';
import '../items/item_form.dart';
import '../centers/semester_centers.dart';
import '../semester/semester_page.dart';
import '../media/drafts.dart';

class ShellPage extends StatefulWidget {
  final AppController controller;
  final ItemsController items;
  final int initialTab;
  const ShellPage({
    super.key,
    required this.controller,
    required this.items,
    this.initialTab = 0,
  });
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  var calendarKey = GlobalKey<CalendarPanelState>();
  var todayKey = GlobalKey<TodayDashboardState>();
  var semesterKey = GlobalKey<SemesterHomeState>();
  String? actor;
  final visitedTabs = <int>{0};
  int tab = 0;
  AxisDirection tabDirection = AxisDirection.right;
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    tab = widget.initialTab.clamp(0, 3);
    visitedTabs.add(tab);
  }

  @override
  void didUpdateWidget(covariant ShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      switchTab(widget.initialTab.clamp(0, 3));
    }
  }

  void switchTab(int value) {
    if (value == tab) return;
    setState(() {
      tabDirection = value > tab ? AxisDirection.right : AxisDirection.left;
      tab = value;
      visitedTabs.add(value);
    });
  }

  void openImport() =>
      context.push(c.semester == null ? '/semester/new' : '/import');
  void manual() =>
      context.push(c.semester == null ? '/semester/new' : '/manual');

  Future<void> editSemester() async {
    final selected = c.semester;
    if (selected == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SemesterPage(
          controller: c,
          existing: Map<String, dynamic>.from(selected),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> deleteSemester() async {
    final selected = c.semester;
    if (selected == null) return;
    Map<String, dynamic> preview;
    try {
      preview = Map<String, dynamic>.from(
        await c.api.request(
          'GET',
          '/semesters/${selected['id']}/delete-preview',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(e))));
      }
      return;
    }
    if (!mounted || c.semester?['id'] != selected['id']) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: Text('删除“${preview['name']}”？'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('该学期的以下内容将一并删除：'),
            const SizedBox(height: 12),
            for (final entry in {
              '课程': preview['courses'],
              '任务': preview['items'],
              '日程': preview['events'],
              '学习安排': preview['plans'],
              '通知来源': preview['sources'],
              '助手对话': preview['conversations'],
            }.entries)
              if ((entry.value as num? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(entry.key)),
                      Text(
                        '${entry.value}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            const Text(
              '相关历史也会删除，无法恢复。',
              style: TextStyle(color: CampusColors.error),
            ),
          ],
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留学期'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialog, true),
            style: AppButton.styleFrom(
              backgroundColor: CampusColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted || c.semester?['id'] != selected['id']) return;
    try {
      final owner = '${c.user['id']}';
      final receipt = await c.deleteSemester(
        '${selected['id']}',
        preview['revision'] as int,
      );
      try {
        await widget.items.forgetDeletedSemester('${selected['id']}');
        await CaptureDrafts.clearSemester(c.cache, owner, '${selected['id']}');
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('学期已删除，本机提醒或草稿清理未完成，请重新打开App核对')),
          );
        }
      }
      if (mounted) Navigator.pop(context);
      if (mounted &&
          (receipt['media_files_pending_cleanup'] as int? ?? 0) > 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('学期已删除，附件正在清理')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(e))));
      }
    }
  }

  Future<void> manageSemester() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('管理学期与课表')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: c.semester == null
                ? const SizedBox.shrink()
                : SemesterView(
                    semesters: c.semesters,
                    current: c.semester!,
                    onSelect: (s) async {
                      await c.selectSemester(s);
                      if (mounted && context.mounted) Navigator.pop(context);
                    },
                    onCreate: () => context.push('/semester/new'),
                    onImport: openImport,
                    onManual: manual,
                    onEdit: editSemester,
                    onDelete: deleteSemester,
                  ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> refresh() async {
    if (tab == 1 && c.semester != null) {
      await c.loadWeek(c.week);
    } else {
      await c.openSession();
    }
    await widget.items.refresh();
    if (tab == 0) await todayKey.currentState?.reload();
    if (tab == 1) await calendarKey.currentState?.reload();
    if (tab == 3) await semesterKey.currentState?.reload();
  }

  Future<void> add() async {
    if (c.semester == null) {
      context.push('/semester/new');
      return;
    }
    final semester = c.semester!;
    final generation = widget.items.api.generation;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ItemFormPage(controller: widget.items, semester: semester),
      ),
    );
    if (saved == true && mounted && generation == widget.items.api.generation) {
      await widget.items.refresh();
    }
  }

  Future<void> account() => showAppSheet<void>(
    context: context,
    builder: (sheet) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSheetHeading(title: '账户', closeLabel: '关闭'),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: CampusColors.blueSoft,
                child: c.isDemo
                    ? const Icon(
                        Icons.person_outline_rounded,
                        color: CampusColors.primary,
                        size: 27,
                      )
                    : Text(
                        '${c.user['username']}'.trim().isEmpty
                            ? '拾'
                            : '${c.user['username']}'
                                  .trim()
                                  .characters
                                  .first
                                  .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: CampusColors.primary,
                        ),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.isDemo ? '体验账号' : '${c.user['username']}',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Column(
            children: [
              AppTile(
                key: const Key('account-profile'),
                onTap: () {
                  Navigator.pop(sheet);
                  context.push('/profile');
                },
                leading: const Icon(Icons.badge_outlined),
                title: const Text('个人资料'),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
              const Divider(height: 1),
              AppTile(
                onTap: () {
                  Navigator.pop(sheet);
                  context.push('/help');
                },
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('使用说明'),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
              ...[
                const Divider(height: 1),
                AppTile(
                  onTap: () {
                    Navigator.pop(sheet);
                    context.push('/reminders');
                  },
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('提醒设置'),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 6),
              AppTextButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  c.logout();
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出登录'),
                style: AppTextButton.styleFrom(
                  foregroundColor: CampusColors.error,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  '本机缓存将清理，已保存课表保留。',
                  style: TextStyle(fontSize: 12, color: CampusColors.muted),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void showCalendarDay(DateTime day) {
    switchTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) calendarKey.currentState?.selectDay(day);
    });
  }

  Future<void> editTask(Map<String, dynamic> row) async {
    final items = widget.items, semester = c.semester;
    if (semester == null) return;
    final generation = items.api.generation, owner = items.owner;
    try {
      final latest = await items.get('${row['id']}');
      if (!mounted ||
          generation != items.api.generation ||
          owner != items.owner ||
          c.semester?['id'] != semester['id']) {
        return;
      }
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ItemFormPage(
            controller: items,
            semester: semester,
            initial: latest,
          ),
        ),
      );
      if (saved == true && mounted && generation == items.api.generation) {
        await items.refresh();
      }
    } catch (e) {
      if (mounted && generation == items.api.generation) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(e))));
      }
    }
  }

  Widget page(int index) {
    if (c.semester == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EmptyPanel(
            title: '还没有学期',
            message: '设置第1周周一，然后导入课表。',
            action: '创建学期',
            onAction: () => context.push('/semester/new'),
          ),
        ],
      );
    }
    return switch (index) {
      1 => CalendarPanel(key: calendarKey, app: c, items: widget.items),
      2 => ItemsView(
        controller: widget.items,
        onCreate: add,
        onCapture: () => AssistantScope.open(context),
        onOpen: (id) => context.push('/items/$id'),
        onEdit: editTask,
        sliver: true,
      ),
      3 => SemesterHome(
        key: semesterKey,
        controller: widget.items,
        onManage: manageSemester,
      ),
      _ => TodayDashboard(
        key: todayKey,
        app: c,
        items: widget.items,
        onCalendar: () => switchTab(1),
        onCalendarDay: showCalendarDay,
        onTaskEdit: editTask,
        onAllTasks: () => switchTab(2),
        onRetry: refresh,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.ready) {
        return const Scaffold(
          body: Center(child: AppLoadingIndicator(label: '正在打开拾日')),
        );
      }
      final nextActor = '${c.user['id']}:${c.semester?['id']}';
      if (actor != nextActor) {
        actor = nextActor;
        calendarKey = GlobalKey<CalendarPanelState>();
        todayKey = GlobalKey<TodayDashboardState>();
        semesterKey = GlobalKey<SemesterHomeState>();
        visitedTabs
          ..clear()
          ..add(tab);
      }
      return Scaffold(
        appBar: tab == 1
            ? null
            : AppBar(
                toolbarHeight: 48,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ExcludeSemantics(child: BrandMark(size: 26)),
                    const SizedBox(width: 9),
                    Text(
                      tab == 0
                          ? appName
                          : tab == 2
                          ? '任务'
                          : '学期',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                      ),
                    ),
                  ],
                ),
                actions: [
                  AppIconButton(
                    onPressed: account,
                    guardAsync: false,
                    tooltip: '账户',
                    icon: const CircleAvatar(
                      radius: 18,
                      backgroundColor: CampusColors.blueSoft,
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 23,
                        color: CampusColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: tab,
            children: [
              for (var index = 0; index < 4; index++)
                if (!visitedTabs.contains(index))
                  const SizedBox()
                else
                  KeyedSubtree(
                    key: ValueKey(
                      'tab-${c.user['id']}-${c.semester?['id']}-$index',
                    ),
                    child: TickerMode(
                      enabled: tab == index,
                      child: TabEntrance(
                        active: tab == index,
                        animateOnMount: index != 0,
                        direction: tabDirection,
                        child: RefreshIndicator(
                          onRefresh: refresh,
                          child: CustomScrollView(
                            key: PageStorageKey(
                              'semester-tab-${c.user['id']}-${c.semester?['id']}-$index',
                            ),
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  22,
                                ),
                                sliver: SliverMainAxisGroup(
                                  slivers: [
                                    if (index == 0 && c.semester != null)
                                      SliverToBoxAdapter(
                                        child: Column(
                                          children: [
                                            const StudentProfilePrompt(),
                                            ClipboardNoticePrompt(
                                              onImport: (text) =>
                                                  openAssistantSheet(
                                                    context,
                                                    controller: widget.items,
                                                    semester: c.semester!,
                                                    initialText: text,
                                                    noticeInput: true,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (c.notice != null &&
                                        (!c.notice!.startsWith('正在同步') ||
                                            c.offline))
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
                                          child: SoftNotice(
                                            c.notice!,
                                            warning: c.offline,
                                          ),
                                        ),
                                      ),
                                    if (index == 2 && c.semester != null)
                                      page(index)
                                    else
                                      SliverToBoxAdapter(child: page(index)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        bottomNavigationBar: AppNavigation(
          selected: tab,
          onSelected: switchTab,
          showAssistant: tab != 1,
        ),
      );
    },
  );
}
