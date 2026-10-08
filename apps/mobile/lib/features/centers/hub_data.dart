import '../../ui/app_loading.dart';
import '../../ui/app_controls.dart';
import '../../core/api.dart' show userError;
import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/v2/motion/skeleton.dart';
import '../items/items_controller.dart';

class HubData extends StatefulWidget {
  final ItemsController controller;
  final String path;
  final Widget? placeholder;
  final Widget Function(
    BuildContext,
    Map<String, dynamic>,
    bool,
    Future<void> Function(),
  )
  builder;
  const HubData({
    super.key,
    required this.controller,
    required this.path,
    required this.builder,
    this.placeholder,
  });
  @override
  HubDataState createState() => HubDataState();
}

class HubDataState extends State<HubData> with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  int request = 0;
  late final generation = widget.controller.api.generation;
  late final sid = widget.controller.semesterId;
  Timer? timer;
  Future<void>? _pending;
  DateTime? _loadedAt;
  bool _visible = false;
  bool _foreground = true;
  bool get active => _visible && _foreground;
  bool get stale =>
      data == null ||
      error != null ||
      _expired ||
      widget.controller.revisionIsStale(sid, data!['revision']) ||
      _loadedAt == null ||
      DateTime.now().difference(_loadedAt!) >= const Duration(seconds: 45);
  bool get _expired {
    final until = data?['valid_until'] ?? data?['risk']?['valid_until'];
    return until != null &&
        DateTime.tryParse('$until')?.isAfter(DateTime.now()) != true;
  }

  bool get same =>
      generation == widget.controller.api.generation &&
      sid == widget.controller.semesterId;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    widget.controller.addListener(changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _updateActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateActivity();
  }

  void _updateActivity() {
    timer?.cancel();
    if (!active || !same) return;
    if (stale && !busy) load();
    timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (active && !busy && same) load();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    request++;
    widget.controller.removeListener(changed);
    super.dispose();
  }

  Future<void> load() {
    if (_pending != null) return _pending!;
    final pending = _load();
    _pending = pending;
    return pending.whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    if (!same) return;
    final stamp = ++request;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.controller.changeRequest('GET', widget.path);
      if (!mounted || stamp != request || !same) return;
      if (widget.controller.revisionIsStale(sid, value['revision'])) {
        throw Exception('查询期间安排已更新，请刷新');
      }
      widget.controller.observeRevision(sid!, value['revision']);
      setState(() {
        data = value;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (mounted && stamp == request && same) {
        setState(() {
          error = userError(e);
        });
      }
    } finally {
      if (mounted && stamp == request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!same) return const SoftNotice('账号或学期已切换，请返回重新打开', warning: true);
    final value = data;
    final until = value?['valid_until'] ?? value?['risk']?['valid_until'];
    final fresh =
        value != null &&
        error == null &&
        !widget.controller.offline &&
        !widget.controller.revisionIsStale(sid, value['revision']) &&
        until != null &&
        DateTime.parse(until).isAfter(DateTime.now());
    if (value == null && busy) {
      return widget.placeholder ??
          const SkeletonScope(
            child: Column(
              children: [
                SkeletonBox(height: 112),
                SizedBox(height: 20),
                SkeletonBox(height: 80),
                SizedBox(height: 12),
                SkeletonBox(height: 80),
              ],
            ),
          );
    }
    return AppLoadingOverlay(
      loading: busy,
      label: '正在更新',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            SoftNotice(
              value == null ? error! : '更新失败，保留上次记录。$error',
              warning: true,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton.icon(
                onPressed: busy ? null : load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ),
          ],
          if (value != null) ...[
            if (!fresh && error == null) ...[
              const SoftNotice('安排已更新或分析过期，时间余量待更新。', warning: true),
              Align(
                alignment: Alignment.centerLeft,
                child: AppTextButton(
                  onPressed: busy ? null : load,
                  child: const Text('更新数据'),
                ),
              ),
            ],
            widget.builder(context, value, fresh, load),
          ],
        ],
      ),
    );
  }
}
