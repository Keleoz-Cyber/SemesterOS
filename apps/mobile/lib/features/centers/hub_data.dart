import 'dart:async';
import 'package:flutter/material.dart';
import '../../ui/campus_widgets.dart';
import '../items/items_controller.dart';

class HubData extends StatefulWidget {
  final ItemsController controller;
  final String path;
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
  });
  @override
  State<HubData> createState() => _HubDataState();
}

class _HubDataState extends State<HubData> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  int request = 0;
  late final generation = widget.controller.api.generation;
  late final sid = widget.controller.semesterId;
  Timer? timer;
  bool get same =>
      generation == widget.controller.api.generation &&
      sid == widget.controller.semesterId;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
    load();
    timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!busy && same) load();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    request++;
    widget.controller.removeListener(changed);
    super.dispose();
  }

  Future<void> load() async {
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
      setState(() => data = value);
    } catch (e) {
      if (mounted && stamp == request) {
        setState(() {
          error = '$e';
          data = null;
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
        !widget.controller.offline &&
        !widget.controller.revisionIsStale(sid, value['revision']) &&
        until != null &&
        DateTime.parse(until).isAfter(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新本页'),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) SoftNotice(error!, warning: true),
        if (value != null) ...[
          if (!fresh)
            const SoftNotice('安排已更新或分析过期，请刷新后查看最新余量与负荷。', warning: true),
          widget.builder(context, value, fresh, load),
        ],
      ],
    );
  }
}
