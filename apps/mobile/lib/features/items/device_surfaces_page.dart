import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../core/api.dart';
import '../../core/device_surfaces.dart';
import '../../ui/app_controls.dart';
import 'items_controller.dart';

class DeviceSurfacesPage extends StatefulWidget {
  final ItemsController controller;
  const DeviceSurfacesPage({super.key, required this.controller});
  @override
  State<DeviceSurfacesPage> createState() => _DeviceSurfacesPageState();
}

class _DeviceSurfacesPageState extends State<DeviceSurfacesPage>
    with WidgetsBindingObserver {
  Map<String, dynamic> status = {};
  Map<int, Map<String, dynamic>> pending = {};
  String? error;
  bool busy = false, loaded = false;
  Timer? _reload;
  int _loadEpoch = 0;
  late final generation = widget.controller.api.generation;
  bool get valid => mounted && generation == widget.controller.api.generation;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(changed);
    load();
  }

  @override
  void dispose() {
    _reload?.cancel();
    widget.controller.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load();
  }

  Future<void> load() async {
    final stamp = ++_loadEpoch;
    try {
      final next = await DeviceSurfaces.status();
      final reminders = await widget.controller.reminders.port.pending();
      if (valid && stamp == _loadEpoch) {
        setState(() {
          status = next;
          loaded = true;
          pending = Map.fromEntries(
            reminders.entries.where(
              (e) => e.value['owner_id'] == widget.controller.owner,
            ),
          );
        });
      }
    } catch (e) {
      if (valid) setState(() => error = userError(e));
    }
  }

  void changed() {
    _reload?.cancel();
    _reload = Timer(const Duration(milliseconds: 250), load);
  }

  Future<void> action(String name, [Map<String, dynamic>? data]) async {
    if (!valid) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if ((name == 'track' || name == 'test') &&
          !await widget.controller.reminders.port.permission(request: true)) {
        throw ApiFailure('请先允许拾日发送通知');
      }
      if (!valid) return;
      if (name == 'track' || name == 'test') {
        await widget.controller.syncNotifications();
      }
      await DeviceSurfaces.action(name, data);
      await load();
    } catch (e) {
      if (valid) setState(() => error = userError(e));
    } finally {
      if (valid) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = (status['entries'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(jsonDecode(e)))
        .where((e) {
          final start = DateTime.tryParse('${e['start_at']}'),
              end = DateTime.tryParse('${e['end_at']}');
          final now = DateTime.now();
          return start != null &&
              start.isBefore(now.add(const Duration(minutes: 15))) &&
              (end?.isAfter(now) ??
                  start.isAfter(now.subtract(const Duration(hours: 12))));
        })
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('桌面卡片与实时提醒')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppTile(
            title: const Text('添加桌面日程卡'),
            subtitle: const Text('查看接下来的安排，点卡片进入详情'),
            leading: const Icon(Icons.widgets_outlined),
            onTap: busy ? null : () => action('pinWidget'),
          ),
          const SizedBox(height: 20),
          const Text(
            '跟踪当前安排',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '临近15分钟或正在进行的安排可显示倒计时；结束时间未知时显示已开始多久。Android 16及以上会尝试系统实时通知，是否显示状态栏胶囊由系统决定。',
          ),
          if ('${status['tracked'] ?? ''}'.isNotEmpty)
            AppTextButton(
              onPressed: busy ? null : () => action('stop'),
              child: const Text('停止跟踪'),
            ),
          if (entries.isEmpty && loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('暂时没有临近或进行中的安排'),
            ),
          for (final e in entries)
            AppTile(
              title: Text('${e['title']}'),
              subtitle: Text(
                '${hhmm(schoolTime(e['start_at']))} · ${e['location'] ?? ''}',
              ),
              trailing: Text(status['tracked'] == e['id'] ? '跟踪中' : '跟踪'),
              onTap: busy ? null : () => action('track', {'id': e['id']}),
            ),
          if ((status['sdk'] as num? ?? 0) >= 36)
            AppTile(
              title: const Text('系统实时通知'),
              subtitle: Text(
                status['promoted'] == true ? '系统允许增强展示' : '可在系统设置中检查权限',
              ),
              onTap: () => action('promotedSettings'),
            ),
          const Divider(height: 32),
          AppTile(
            title: const Text('发送测试提醒'),
            subtitle: const Text('立即发出一条测试通知'),
            leading: const Icon(Icons.notifications_active_outlined),
            onTap: busy ? null : () => action('test'),
          ),
          AppTile(
            title: const Text('后台电池设置'),
            subtitle: Text(
              !loaded
                  ? '正在读取系统状态'
                  : status['battery_unrestricted'] == true
                  ? '已不受电池优化限制'
                  : '当前受系统电池管理，可查看系统设置',
            ),
            onTap: () => action('batterySettings'),
          ),
          const Text(
            '普通提醒由手机系统定时触发，不需要拾日一直运行。若在系统设置中强制停止拾日，需重新打开才能恢复。电池设置和不同品牌的限制也可能影响提醒。',
          ),
          const SizedBox(height: 24),
          Text(
            loaded ? '本机已设置的提醒 · ${pending.length}' : '正在读取本机提醒',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          for (final p
              in (pending.values.toList()..sort(
                    (a, b) => '${a['snooze_until'] ?? a['trigger_at']}'
                        .compareTo('${b['snooze_until'] ?? b['trigger_at']}'),
                  ))
                  .take(100))
            AppTile(
              title: Text('${p['title'] ?? '日程提醒'}'),
              subtitle: Text(reminderTime(p)),
            ),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        ],
      ),
    );
  }

  String reminderTime(Map<String, dynamic> p) {
    final at = DateTime.tryParse('${p['snooze_until'] ?? p['trigger_at']}');
    if (at == null) return '时间待核对';
    final local = at.toUtc().add(const Duration(hours: 8));
    return '${local.month}月${local.day}日 ${hhmm(local)}${p['quiet'] == true ? ' · 静音' : ''}';
  }
}
