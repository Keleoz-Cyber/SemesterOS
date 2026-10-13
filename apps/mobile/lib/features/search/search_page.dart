import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../ui/app_controls.dart';
import '../items/items_controller.dart';
import '../media/source_view.dart';

class SearchPage extends StatefulWidget {
  final ItemsController controller;
  const SearchPage({super.key, required this.controller});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  List<Map<String, dynamic>> results = [];
  String kind = 'all';
  String? error;
  Timer? debounce;
  int request = 0;
  bool busy = false, more = false;
  late final generation = widget.controller.api.generation;
  late final sid = widget.controller.semesterId;
  bool get valid =>
      mounted &&
      generation == widget.controller.api.generation &&
      sid == widget.controller.semesterId;
  Future<void> search({bool next = false}) async {
    final stamp = ++request, text = input.text.trim();
    if (!valid) return;
    if (text.isEmpty) {
      setState(() {
        results = [];
        busy = false;
        more = false;
        error = null;
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
      if (!next) results = [];
    });
    try {
      final value = await widget.controller.api.request(
        'GET',
        '/semesters/$sid/search',
        queryParameters: {
          'q': text,
          'kind': kind,
          'offset': next ? results.length : 0,
        },
      );
      if (!valid || stamp != request) return;
      setState(() {
        results = [
          ...results,
          ...(value['results'] as List).map(
            (r) => Map<String, dynamic>.from(r),
          ),
        ];
        more = value['has_more'] == true;
      });
    } catch (e) {
      if (valid && stamp == request) setState(() => error = userError(e));
    } finally {
      if (valid && stamp == request) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('搜索安排')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: input,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(
              hintText: '搜标题、地点或通知原文',
              prefixIcon: Icon(Icons.search_rounded),
              counterText: '',
            ),
            onChanged: (_) {
              debounce?.cancel();
              request++;
              debounce = Timer(const Duration(milliseconds: 300), search);
            },
            onSubmitted: (_) {
              debounce?.cancel();
              search();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final e in const {
                'all': '全部',
                'course': '课程',
                'event': '日程',
                'item': '任务与考试',
                'source': '通知原文',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AppFilterChip(
                    label: Text(e.value),
                    selected: kind == e.key,
                    onSelected: (_) {
                      setState(() => kind = e.key);
                      search();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
        if (error != null)
          AppTextButton(
            onPressed: busy ? null : search,
            child: const Text('重试搜索'),
          ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    error != null
                        ? '暂时无法搜索'
                        : input.text.trim().isEmpty
                        ? '输入你记得的关键词'
                        : busy
                        ? '正在查找'
                        : '没有找到匹配的安排',
                  ),
                )
              : ListView.builder(
                  itemCount: results.length + (more ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == results.length) {
                      return AppTextButton(
                        onPressed: busy ? null : () => search(next: true),
                        child: const Text('加载更多'),
                      );
                    }
                    final row = results[index];
                    final label = const {
                      'course': '课程',
                      'event': '日程',
                      'item': '任务与考试',
                      'source': '通知',
                    }[row['kind']];
                    final status = const {
                      'completed': '已完成',
                      'cancelled': '已取消',
                    }[row['lifecycle']];
                    return AppTile(
                      title: Text(row['title']),
                      subtitle: Text(
                        '$label${status == null ? '' : ' · $status'}\n${row['excerpt']}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        if (row['kind'] == 'source') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SourceViewPage(
                                controller: widget.controller,
                                id: row['id'],
                              ),
                            ),
                          );
                        } else {
                          context.push(
                            '/${const {'course': 'courses', 'event': 'events', 'item': 'items'}[row['kind']]}/${row['id']}',
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
