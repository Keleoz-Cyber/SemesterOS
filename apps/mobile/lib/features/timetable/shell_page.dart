import '../../ui/app_controls.dart';
import '../calendar/calendar_panel.dart';
import '../../ui/app_navigation.dart';
import '../../ui/motion.dart';
import '../../ui/assistant_scope.dart';
import '../../ui/brand.dart';
import '../home/today_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../core/api.dart' show userError;
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'course_widgets.dart';
import 'today_view.dart';
import 'week_view.dart';
import 'semester_view.dart';
import '../items/items_controller.dart';
import '../items/items_view.dart';
import '../centers/semester_centers.dart';
import '../semester/semester_page.dart';
import '../media/drafts.dart';

class ShellPage extends StatefulWidget {
  final AppController controller;
  final ItemsController? items;
  const ShellPage({super.key, required this.controller, this.items});
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
  double tabDirection = 1;
  bool grid = true;
  AppController get c => widget.controller;

  void switchTab(int value) {
    if (value == tab) return;
    setState(() {
      tabDirection = value > tab ? 1 : -1;
      tab = value;
      visitedTabs.add(value);
    });
    if (value == 0 && c.semester != null && widget.items == null) {
      c.loadWeek(c.weekNow(c.semester!));
    }
  }

  void openImport() =>
      context.push(c.semester == null ? '/semester/new' : '/import');
  void manual() =>
      context.push(c.semester == null ? '/semester/new' : '/manual');

  void openCourse(Map<String, dynamic> event) {
    if (widget.items != null && event['course_id'] != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CourseHubPage(
            controller: widget.items!,
            courseId: event['course_id'],
          ),
        ),
      );
    } else {
      showCourseDetails(context, event);
    }
  }

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
        content: Text(
          '将一并删除 ${preview['courses']} 门课程、${preview['items']} 条事项、'
          '${preview['events']} 条日程、${preview['plans']} 段计划和'
          '${preview['sources']} 份来源记录，以及 ${preview['conversations']} 段助手对话与相关历史。'
          '删除后无法恢复。',
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留学期'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialog, true),
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
        await widget.items?.forgetDeletedSemester('${selected['id']}');
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学期已删除，旧图片或录音已从App移除，服务器下次启动会继续清理')),
        );
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
            child: SemesterView(
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
    await widget.items?.refresh();
    if (tab == 0) await todayKey.currentState?.reload();
    if (tab == 1) await calendarKey.currentState?.reload();
    if (tab == 3) await semesterKey.currentState?.reload();
  }

  Future<void> add() async {
    if (c.semester == null) {
      context.push('/semester/new');
      return;
    }
    await AssistantScope.open(context);
  }

  Future<void> account() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 27,
                backgroundColor: CampusColors.blueSoft,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: CampusColors.primary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.user['username']}',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      '我的账号',
                      style: TextStyle(fontSize: 13, color: CampusColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 23),
          const SoftNotice('退出后会清理本机缓存，云端已保存的课表仍保留。'),
          const SizedBox(height: 18),
          AppOutlineButton.icon(
            onPressed: () {
              Navigator.pop(sheet);
              c.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
          ),
        ],
      ),
    ),
  );

  Widget page(int index) {
    if (c.semester == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CampusHero(
            eyebrow: '',
            title: '建立学期',
            subtitle: '设置开学日期，然后导入课表',
          ),
          const SizedBox(height: 22),
          EmptyPanel(
            title: '先建立你的学期',
            message: '选择学校校历的第1周周一，再导入课程。',
            action: '创建学期',
            onAction: () => context.push('/semester/new'),
          ),
        ],
      );
    }
    final hasData =
        c.savedWeeks['${c.semester!['id']}/${c.week}']?['revision'] ==
        c.semester!['revision'];
    switch (index) {
      case 1:
        if (widget.items != null) {
          return CalendarPanel(key: calendarKey, app: c, items: widget.items!);
        }
        return WeekView(
          semester: c.semester!,
          events: c.events,
          now: DateTime.now(),
          week: c.week,
          grid: grid,
          hasData: hasData,
          onMode: (value) => setState(() => grid = value),
          onWeek: c.loadWeek,
          onCurrent: () => c.loadWeek(c.weekNow(c.semester!)),
          onImport: openImport,
          onCourse: openCourse,
        );
      case 2:
        if (widget.items != null) {
          return ItemsView(
            controller: widget.items!,
            onCreate: add,
            onOpen: (id) => context.push('/items/$id'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CampusHero(eyebrow: '', title: '个人计划', subtitle: ''),
            const SizedBox(height: 22),
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill('暂时无法加载', icon: Icons.construction_rounded),
            ),
            const SizedBox(height: 12),
            EmptyPanel(
              title: '计划暂时无法加载',
              message: '可以先查看课表，稍后重新打开App再试。',
              action: '查看本周课表',
              onAction: () => switchTab(1),
              icon: Icons.checklist_rounded,
            ),
          ],
        );
      case 3:
        if (widget.items != null) {
          return SemesterHome(
            key: semesterKey,
            controller: widget.items!,
            onManage: manageSemester,
          );
        }
        return SemesterView(
          semesters: c.semesters,
          current: c.semester!,
          onSelect: c.selectSemester,
          onCreate: () => context.push('/semester/new'),
          onImport: openImport,
          onManual: manual,
          onEdit: editSemester,
          onDelete: deleteSemester,
        );
      default:
        if (widget.items != null) {
          return TodayDashboard(
            key: todayKey,
            app: c,
            items: widget.items!,
            onCalendar: () => switchTab(1),
          );
        }
        return TodayView(
          itemsBlock: widget.items == null
              ? null
              : TodayItems(
                  controller: widget.items!,
                  onAll: () => switchTab(2),
                  onOpen: (id) => context.push('/items/$id'),
                ),
          semester: c.semester!,
          events: c.events,
          now: DateTime.now(),
          week: c.week,
          hasData: hasData,
          onTimetable: () => switchTab(1),
          onImport: openImport,
          onManual: manual,
          onCourse: openCourse,
        );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      if (!c.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        appBar: AppBar(
          toolbarHeight: 52,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ExcludeSemantics(child: BrandMark(size: 30)),
              const SizedBox(width: 9),
              const Text(
                appName,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
          actions: [
            AppIconButton(
              onPressed: account,
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
        body: IndexedStack(
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
                        child: ListView(
                          key: PageStorageKey(
                            'semester-tab-${c.user['id']}-${c.semester?['id']}-$index',
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            if (c.notice != null &&
                                (!c.notice!.startsWith('正在同步') ||
                                    c.offline)) ...[
                              SoftNotice(c.notice!, warning: c.offline),
                              const SizedBox(height: 14),
                            ],
                            page(index),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        bottomNavigationBar: AppNavigation(
          selected: tab,
          onSelected: switchTab,
        ),
      );
    },
  );
}
