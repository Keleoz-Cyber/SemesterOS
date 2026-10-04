import '../../ui/app_loading.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import '../../core/api.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_sheet.dart';
import '../../ui/campus_theme.dart';
import '../items/items_controller.dart';

/// Tags remain individual values from selection through submission.
class TagPickerField extends StatelessWidget {
  final ItemsController controller;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  const TagPickerField({
    super.key,
    required this.controller,
    required this.values,
    required this.onChanged,
    this.enabled = true,
  });

  Future<void> choose(BuildContext context) async {
    final generation = controller.api.generation;
    final semester = controller.semesterId;
    final result = await showAppSheet<List<String>>(
      context: context,
      heightFactor: .75,
      builder: (_) => _TagPicker(controller: controller, initial: values),
    );
    if (result != null &&
        context.mounted &&
        generation == controller.api.generation &&
        semester == controller.semesterId) {
      onChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text('标签', style: TextStyle(fontSize: 14)),
      ),
      FButton(
        onPress: enabled ? () => choose(context) : null,
        variant: FButtonVariant.outline,
        size: FButtonSizeVariant.lg,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        suffix: const Icon(Icons.chevron_right_rounded, size: 20),
        child: Flexible(
          child: values.isEmpty
              ? const Text(
                  '选择标签',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in values)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: CampusColors.blueSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 14,
                            color: CampusColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    ],
  );
}

class _TagPicker extends StatefulWidget {
  final ItemsController controller;
  final List<String> initial;
  const _TagPicker({required this.controller, required this.initial});
  @override
  State<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<_TagPicker> {
  final input = TextEditingController();
  late final List<String> selected = [...widget.initial];
  List<String> options = [];
  bool loading = true;
  String? loadError, fieldError;
  String get query => input.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  @override
  void initState() {
    super.initState();
    options = [...selected];
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        loadError = null;
      });
    }
    try {
      final data = await widget.controller.api.request('GET', '/tags');
      if (!mounted) return;
      if (data['owner_id'] != widget.controller.owner) {
        throw ApiFailure('账号已切换，请重新打开');
      }
      final names = (data['tags'] as List? ?? [])
          .whereType<Map>()
          .map((tag) => '${tag['name'] ?? ''}')
          .where((name) => name.isNotEmpty);
      setState(() => options = {...selected, ...names}.toList());
    } catch (_) {
      if (mounted) setState(() => loadError = '已有标签暂未加载');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void toggle(String name) {
    setState(() {
      fieldError = null;
      if (selected.contains(name)) {
        selected.remove(name);
      } else if (selected.length < 12) {
        selected.add(name);
      } else {
        fieldError = '最多选择12个标签';
      }
    });
  }

  void add() {
    final name = query;
    if (name.isEmpty) return;
    final existing = options
        .where((s) => s.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      if (!selected.contains(existing)) toggle(existing);
    } else if (name.length > 24) {
      setState(() => fieldError = '标签最多24字');
      return;
    } else if (selected.length >= 12) {
      setState(() => fieldError = '最多选择12个标签');
      return;
    } else {
      setState(() {
        options.add(name);
        selected.add(name);
        fieldError = null;
      });
    }
    input.clear();
    setState(() {});
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = options
        .where(
          (name) =>
              (query.isNotEmpty || !selected.contains(name)) &&
              name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final canAdd =
        query.isNotEmpty &&
        !options.any((name) => name.toLowerCase() == query.toLowerCase());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '选择标签',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              AppLoadingIndicator(
                compact: true,
                visible: loading,
                label: '正在读取标签',
              ),
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                AppField(
                  key: const Key('tag-name-input'),
                  controller: input,
                  decoration: const InputDecoration(labelText: '搜索或添加标签'),
                  onChanged: (_) => setState(() => fieldError = null),
                  onSubmitted: (_) => add(),
                ),
                if (fieldError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      fieldError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in selected)
                          AppOutlineButton.icon(
                            onPressed: () => toggle(name),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: Text(name),
                          ),
                      ],
                    ),
                  ),
                if (loadError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          loadError!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                      AppTextButton(onPressed: load, child: const Text('重试')),
                    ],
                  ),
                if (canAdd)
                  AppTextButton.icon(
                    onPressed: add,
                    icon: const Icon(Icons.add_rounded),
                    label: Text('添加“$query”'),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in matches)
                      AppFilterChip(
                        label: Text(name),
                        selected: selected.contains(name),
                        onSelected: (_) => toggle(name),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: AppButton(
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context, [...selected]);
              },
              child: const Text('确认标签'),
            ),
          ),
        ],
      ),
    );
  }
}
