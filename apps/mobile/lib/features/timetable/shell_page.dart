import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import '../../ui/campus_theme.dart';
import '../../ui/campus_widgets.dart';
import 'course_widgets.dart';
import 'today_view.dart';
import 'week_view.dart';
import 'semester_view.dart';

class ShellPage extends StatefulWidget {
  final AppController controller;
  const ShellPage({super.key, required this.controller});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int tab = 0;
  bool grid = true;
  Timer? clock;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    clock?.cancel();
    super.dispose();
  }

  void switchTab(int value) {
    setState(() => tab = value);
    if (value == 0 && c.semester != null) c.loadWeek(c.weekNow(c.semester!));
  }

  void openImport() =>
      context.push(c.semester == null ? '/semester/new' : '/import');
  void manual() =>
      context.push(c.semester == null ? '/semester/new' : '/manual');

  Future<void> add() async {
    if (c.semester == null) {
      context.push('/semester/new');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '把课程放进学期',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              '选择一种方式，保存前都可以核对。',
              style: TextStyle(color: CampusColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 22),
            CampusPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    leading: const Icon(
                      Icons.language_rounded,
                      color: CampusColors.primary,
                      size: 28,
                    ),
                    title: const Text(
                      '从学校教务导入',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      '在学校原始网页自行登录',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheet);
                      openImport();
                    },
                  ),
                  const Divider(height: 1, indent: 58, endIndent: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    leading: const Icon(
                      Icons.edit_calendar_outlined,
                      color: Color(0xFF328774),
                      size: 28,
                    ),
                    title: const Text(
                      '手工添加课程',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text(
                      '填写名称、周次、节次和地点',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheet);
                      manual();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                backgroundColor: Color(0xFFE7E5FC),
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
                      '我的学期OS账号',
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
          OutlinedButton.icon(
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

  Widget page() {
    if (c.semester == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CampusHero(
            eyebrow: 'HELLO / 新的开始',
            title: '我的新学期',
            subtitle: '从一张课表开始\n让安排清晰起来',
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
    switch (tab) {
      case 1:
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
          onCourse: (event) => showCourseDetails(context, event),
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CampusHero(
              eyebrow: 'PLAN / 给重要的事留时间',
              title: '个人计划',
              subtitle: '课程先安顿好\n再安排自己的时间',
            ),
            const SizedBox(height: 22),
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill('暂未开放', icon: Icons.construction_rounded),
            ),
            const SizedBox(height: 12),
            EmptyPanel(
              title: '规划能力正在准备中',
              message: '当前版本已支持真实课表导入与查看。个人任务和AI规划还没有开放，课程不会被自动移动。',
              action: '查看本周课表',
              onAction: () => switchTab(1),
              icon: Icons.checklist_rounded,
            ),
          ],
        );
      case 3:
        return SemesterView(
          semesters: c.semesters,
          current: c.semester!,
          onSelect: c.selectSemester,
          onCreate: () => context.push('/semester/new'),
          onImport: openImport,
          onManual: manual,
        );
      default:
        return TodayView(
          semester: c.semester!,
          events: c.events,
          now: DateTime.now(),
          week: c.week,
          hasData: hasData,
          onTimetable: () => switchTab(1),
          onImport: openImport,
          onManual: manual,
          onCourse: (event) => showCourseDetails(context, event),
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
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 68,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: CampusColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                '学期OS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: c.busy
                  ? null
                  : () => tab == 1 && c.semester != null
                        ? c.loadWeek(c.week)
                        : c.openSession(),
              tooltip: '同步课表',
              icon: c.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, color: CampusColors.muted),
            ),
            IconButton(
              onPressed: account,
              tooltip: '账户',
              icon: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE9EDFA),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 23,
                  color: Color(0xFF6F78A3),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => tab == 1 && c.semester != null
              ? c.loadWeek(c.week)
              : c.openSession(),
          child: ListView(
            key: PageStorageKey('semester-tab-$tab'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 106),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (c.notice != null &&
                  (!c.notice!.startsWith('正在同步') || c.offline)) ...[
                SoftNotice(c.notice!, warning: c.offline),
                const SizedBox(height: 14),
              ],
              page(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add,
          icon: const Icon(Icons.add_rounded, size: 24),
          label: const Text(
            '记录',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: CampusColors.line)),
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: switchTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '今日',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month_rounded),
                label: '课表',
              ),
              NavigationDestination(
                icon: Icon(Icons.check_box_outlined),
                selectedIcon: Icon(Icons.check_box_rounded),
                label: '计划',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined),
                selectedIcon: Icon(Icons.auto_stories_rounded),
                label: '学期',
              ),
            ],
          ),
        ),
      );
    },
  );
}
