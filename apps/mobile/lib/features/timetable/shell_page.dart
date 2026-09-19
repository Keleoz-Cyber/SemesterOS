import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';

const _colors = [
  Color(0xFFEBE5FF),
  Color(0xFFDDF4EA),
  Color(0xFFFFE3DB),
  Color(0xFFFFF1C2),
  Color(0xFFE7EFFF),
];
Color courseColor(String name) =>
    _colors[name.runes.fold<int>(0, (a, b) => a + b) % _colors.length];

class ShellPage extends StatefulWidget {
  final AppController controller;
  const ShellPage({super.key, required this.controller});
  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int tab = 0;
  bool grid = true;
  AppController get c => widget.controller;

  void add() {
    if (c.semester == null) {
      context.push('/semester/new');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: const Text('从学校教务导入'),
              subtitle: const Text('在学校原始网页自行登录'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/import');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar),
              title: const Text('手工添加课程'),
              subtitle: const Text('填写课程、周次和节次'),
              onTap: () {
                Navigator.pop(sheet);
                context.push('/manual');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void details(Map<String, dynamic> e) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${e['title']}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Text(
              '${e['start_at'].toString().substring(0, 10)}  ${hhmm(schoolTime(e['start_at']))}—${hhmm(schoolTime(e['end_at']))}',
            ),
            Text(
              '地点：${e['location'].toString().isEmpty ? '未填写' : e['location']}\n教师：${e['teacher'].toString().isEmpty ? '未填写' : e['teacher']}',
            ),
            Text(
              '周次：${(e['weeks'] as List).join('、')}\n第${(e['sections'] as List).join('、')}节',
            ),
            if (e['conflict'] == true)
              const Text(
                '与另一项课程时间重叠，请核对原始安排',
                style: TextStyle(color: Color(0xFF9F241C)),
              ),
            const SizedBox(height: 14),
            const Text(
              '这是固定课程，个人规划不会自动移动它。',
              style: TextStyle(fontSize: 14, color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    ),
  );

  Widget empty(
    String title,
    String body, {
    String? button,
    VoidCallback? action,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.event_note_rounded,
            color: Color(0xFF4F46E5),
            size: 38,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(body),
          if (button != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: action, child: Text(button)),
          ],
        ],
      ),
    ),
  );

  Widget eventCard(Map<String, dynamic> e) => Card(
    color: courseColor(e['title']),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        '${e['title']}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${e['start_at'].toString().substring(5, 10)}  ${hhmm(schoolTime(e['start_at']))}—${hhmm(schoolTime(e['end_at']))}\n${e['location']}',
      ),
      trailing: Icon(
        e['conflict'] == true
            ? Icons.warning_amber_rounded
            : Icons.chevron_right,
      ),
      onTap: () => details(e),
    ),
  );

  Widget timetable() {
    final periods = List<Map<String, dynamic>>.from(c.semester!['periods']);
    final begin = int.parse(periods.first['start'].split(':')[0]);
    final end = (int.parse(periods.last['end'].split(':')[0]) + 1).clamp(
      begin + 1,
      24,
    );
    final height = (end - begin) * 48.0;
    const width = 86.0;
    final weekDate = DateTime.parse(
      c.semester!['first_monday'],
    ).add(Duration(days: (c.week - 1) * 7));
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 42,
              child: Column(
                children: [
                  const SizedBox(height: 48),
                  SizedBox(
                    height: height,
                    child: Stack(
                      children: [
                        for (var h = begin; h < end; h++)
                          Positioned(
                            top: (h - begin) * 48,
                            left: 4,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF667085),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            SizedBox(
                              height: 48,
                              child: Column(
                                children: [
                                  Text(
                                    '周${'一二三四五六日'[day - 1]}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${weekDate.add(Duration(days: day - 1)).month}/${weekDate.add(Duration(days: day - 1)).day}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: height,
                              child: Stack(
                                children: [
                                  for (var h = begin; h < end; h++)
                                    Positioned(
                                      top: (h - begin) * 48,
                                      left: 0,
                                      right: 0,
                                      child: const Divider(height: 1),
                                    ),
                                  for (final e in c.events.where(
                                    (e) => e['weekday'] == day,
                                  ))
                                    Positioned(
                                      top:
                                          ((schoolTime(e['start_at']).hour -
                                                      begin) *
                                                  60 +
                                              schoolTime(
                                                e['start_at'],
                                              ).minute) *
                                          .8,
                                      left: 2,
                                      right: 2,
                                      height:
                                          schoolTime(e['end_at'])
                                              .difference(
                                                schoolTime(e['start_at']),
                                              )
                                              .inMinutes *
                                          .8,
                                      child: Semantics(
                                        button: true,
                                        label: '${e['title']} ${e['location']}',
                                        child: InkWell(
                                          onTap: () => details(e),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: courseColor(e['title']),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: e['conflict'] == true
                                                  ? Border.all(
                                                      color: Colors.red,
                                                      width: 2,
                                                    )
                                                  : null,
                                            ),
                                            padding: const EdgeInsets.all(5),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${e['title']}',
                                                    maxLines: 3,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                                if (schoolTime(e['end_at'])
                                                        .difference(
                                                          schoolTime(
                                                            e['start_at'],
                                                          ),
                                                        )
                                                        .inMinutes >=
                                                    70)
                                                  Text(
                                                    '${e['location']}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> content() {
    if (c.semester == null) {
      return [
        empty(
          '先建立你的学期',
          '确认校历后，就能导入课程并按周查看。',
          button: '创建学期',
          action: () => context.push('/semester/new'),
        ),
      ];
    }
    if (tab == 3) {
      return [
        for (final s in c.semesters)
          Card(
            child: ListTile(
              title: Text('${s['name']}'),
              subtitle: Text('第一周 ${s['first_monday']} · ${s['total_weeks']}周'),
              trailing: c.semester!['id'] == s['id']
                  ? const Icon(Icons.check_circle, color: Color(0xFF4F46E5))
                  : null,
              onTap: () => c.selectSemester(s),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => context.push('/semester/new'),
          icon: const Icon(Icons.add),
          label: const Text('添加新学期'),
        ),
        const SizedBox(height: 20),
        empty(
          '本学期的课程入口',
          '从教务读取或手工填写，每次保存前都能核对。',
          button: '导入或添加课程',
          action: add,
        ),
      ];
    }
    if (tab == 2) {
      return [
        empty(
          '先把固定安排放好',
          '当前为课表导入测试版，个人任务和AI规划尚未开放。',
          button: '查看周课表',
          action: () => setState(() => tab = 1),
        ),
      ];
    }
    if (tab == 1) {
      return [
        Row(
          children: [
            IconButton(
              onPressed: c.week > 1 ? () => c.loadWeek(c.week - 1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一周',
            ),
            Expanded(
              child: Center(
                child: Text(
                  '第${c.week}周',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: c.week < c.semester!['total_weeks']
                  ? () => c.loadWeek(c.week + 1)
                  : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一周',
            ),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: () => c.loadWeek(c.weekNow(c.semester!)),
              child: const Text('回到当前日期'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => grid = !grid),
              child: Text(grid ? '切换列表' : '切换周视图'),
            ),
          ],
        ),
        if (c.events.isEmpty)
          empty('这一周没有已记录的课程', '你可以切换周次，或导入本学期课表。', button: '导入课程', action: add)
        else if (grid) ...[
          const Text(
            '左右滑动查看完整七天 · 点击课程查看详情',
            style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
          ),
          timetable(),
        ] else
          ...c.events.map(eventCard),
      ];
    }
    final now = schoolNow();
    final today = c.events.where((e) {
      final t = schoolTime(e['start_at']);
      return t.year == now.year && t.month == now.month && t.day == now.day;
    }).toList();
    return [
      Card(
        color: const Color(0xFFEBE5FF),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '我的学期，慢慢有序',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('${c.semester!['name']}\n已选择第${c.week}周'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: add,
                icon: const Icon(Icons.download_rounded),
                label: const Text('导入课表'),
              ),
            ],
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text(
          '今天的固定安排',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      if (today.isEmpty)
        empty(
          '今天没有已记录的课程',
          '查看周课表，了解接下来的安排。',
          button: '查看周课表',
          action: () => setState(() => tab = 1),
        )
      else
        ...today.map(eventCard),
    ];
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
          title: const Text(
            '学期OS',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: c.busy ? null : () => c.openSession(),
              icon: const Icon(Icons.refresh),
              tooltip: '同步课表',
            ),
            PopupMenuButton<String>(
              tooltip: '账户',
              onSelected: (v) {
                if (v == 'logout') c.logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text('${c.user['username']}'),
                ),
                const PopupMenuItem(value: 'logout', child: Text('退出并清理本机数据')),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => c.openSession(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              Text(
                '${schoolNow().month}月${schoolNow().day}日 · ${['今日', '周课表', '个人计划', '学期管理'][tab]}',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
              if (c.notice != null)
                Card(
                  color: const Color(0xFFFFF1C2),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(c.notice!),
                  ),
                ),
              if (c.busy) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              ...content(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: add,
          icon: const Icon(Icons.add),
          label: const Text('记录'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) {
            setState(() => tab = i);
            if (i == 0 && c.semester != null) {
              c.loadWeek(c.weekNow(c.semester!));
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '今日',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: '课表',
            ),
            NavigationDestination(
              icon: Icon(Icons.check_box_outlined),
              label: '计划',
            ),
            NavigationDestination(
              icon: Icon(Icons.view_timeline_outlined),
              label: '学期',
            ),
          ],
        ),
      );
    },
  );
}
