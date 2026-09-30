import '../../ui/app_controls.dart';
import 'dart:convert';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import 'semester_validation.dart';
import 'period_editor.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_widgets.dart';

class SemesterPage extends StatefulWidget {
  final AppController controller;
  final Map<String, dynamic>? existing;
  const SemesterPage({super.key, required this.controller, this.existing});
  @override
  State<SemesterPage> createState() => _SemesterPageState();
}

class _SemesterPageState extends State<SemesterPage> {
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final nameField = GlobalKey<FormFieldState<String>>();
  final mondayField = GlobalKey<FormFieldState<String>>();
  final weeksField = GlobalKey<FormFieldState<String>>();
  final periodsField = GlobalKey<FormFieldState<String>>();
  late final TextEditingController name, monday, weeks, times;
  bool confirmed = false, busy = false, submitted = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    name = TextEditingController(text: existing?['name'] ?? '2026—2027学年第一学期');
    monday = TextEditingController(text: existing?['first_monday'] ?? '');
    weeks = TextEditingController(text: '${existing?['total_weeks'] ?? 20}');
    final periods = existing?['periods'] as List?;
    times = TextEditingController(
      text: periods == null
          ? '1 08:00 08:50\n2 09:00 09:50\n3 10:10 11:00\n4 11:10 12:00\n5 14:00 14:50\n6 15:00 15:50\n7 16:10 17:00\n8 17:10 18:00\n9 19:00 19:50\n10 20:00 20:50'
          : periods
                .map((p) => '${p['number']} ${p['start']} ${p['end']}')
                .join('\n'),
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    for (final c in [name, monday, weeks, times]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !confirmed) return;
    setState(() {
      submitted = true;
      error = null;
    });
    // A long period list can unmount earlier form fields; validate the model too.
    final validations = [
      validateSemesterName(name.text),
      validateFirstMonday(monday.text),
      validateTotalWeeks(weeks.text),
      validateSemesterPeriods(times.text),
    ];
    final invalidIndex = validations.indexWhere((value) => value != null);
    final invalid = invalidIndex < 0 ? null : validations[invalidIndex];
    if (invalid != null) {
      form.currentState!.validate();
      setState(() => error = invalid);
      revealInvalid(invalidIndex);
      return;
    }
    if (!form.currentState!.validate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final field in [
          nameField,
          mondayField,
          weeksField,
          periodsField,
        ]) {
          if (field.currentState?.hasError == true &&
              field.currentContext != null) {
            Scrollable.ensureVisible(
              field.currentContext!,
              duration: const Duration(milliseconds: 250),
              alignment: .15,
            );
            break;
          }
        }
      });
      return;
    }
    final periods = parseSemesterPeriods(times.text);
    final existing = widget.existing;
    if (existing != null) {
      final differences = <String>[
        if (existing['first_monday'] != monday.text.trim())
          '第一周周一：${existing['first_monday']} → ${monday.text.trim()}',
        if (existing['total_weeks'] != int.parse(weeks.text.trim()))
          '总周数：${existing['total_weeks']} → ${weeks.text.trim()}',
        if (jsonEncode(existing['periods']) != jsonEncode(periods))
          '每天的节次时间已调整',
      ];
      if (differences.isNotEmpty) {
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AppDialog(
            title: const Text('确认修改校历？'),
            content: Text(
              '${differences.join('\n')}\n已导入课程会按新校历重新计算，请核对变更后的课表。',
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('返回核对'),
              ),
              AppButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('确认修改'),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.controller.api.request(
        existing == null ? 'POST' : 'PUT',
        existing == null ? '/semesters' : '/semesters/${existing['id']}',
        data: {
          if (existing != null) 'expected_revision': existing['revision'],
          'name': name.text.trim(),
          'first_monday': monday.text.trim(),
          'total_weeks': int.parse(weeks.text.trim()),
          'periods': periods,
        },
      );
      await widget.controller.openSession(null, '${saved['id']}');
      if (mounted) {
        if (existing == null) {
          context.go('/');
        } else {
          Navigator.of(context).pop(saved);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void revealInvalid(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scroll.hasClients) return;
      final key = [nameField, mondayField, weeksField, periodsField][index];
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 250),
          alignment: .15,
        );
      } else {
        scroll.animateTo(
          index < 3 ? 0 : scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> chooseMonday() async {
    if (busy) return;
    final now = schoolNow();
    final chosen = await showDatePicker(
      context: context,
      initialDate: monday.text.isEmpty ? null : DateTime.tryParse(monday.text),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
      currentDate: DateTime(now.year, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
      helpText: '选择学校校历第1周的周一',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (chosen == null || !mounted) return;
    setState(() {
      monday.text =
          '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
      error = null;
    });
    if (submitted) mondayField.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? '建立我的学期' : '修改学期设置')),
    bottomNavigationBar: ActionFooter(
      label: busy
          ? '正在保存…'
          : widget.existing == null
          ? '确认创建学期'
          : '保存学期设置',
      icon: Icons.check_rounded,
      onPressed: confirmed && !busy ? save : null,
    ),
    body: Form(
      key: form,
      autovalidateMode: submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          SoftNotice(
            widget.existing == null
                ? '节次时间为示例，请按学校作息调整。'
                : '修改校历或节次后，课程时间会重新计算。',
          ),
          const SizedBox(height: 16),
          EditorSection(
            title: '学期校历',
            icon: Icons.date_range_outlined,
            children: [
              AppFormField(
                key: nameField,
                controller: name,
                enabled: !busy,
                validator: validateSemesterName,
                decoration: const InputDecoration(labelText: '学期名称'),
              ),
              const SizedBox(height: 14),
              Semantics(
                key: const Key('first-monday'),
                button: true,
                child: AppFormField(
                  key: mondayField,
                  controller: monday,
                  enabled: !busy,
                  readOnly: true,
                  onTap: chooseMonday,
                  validator: validateFirstMonday,
                  decoration: InputDecoration(
                    labelText: '第1周周一',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: '点击选择日期',
                    helperText: '请按校历选择第1周的周一',
                    helperMaxLines: 2,
                    errorMaxLines: 2,
                    suffixIcon: AppIconButton(
                      onPressed: busy ? null : chooseMonday,
                      icon: const Icon(Icons.calendar_month_outlined),
                      tooltip: '选择第1周周一',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppFormField(
                key: weeksField,
                controller: weeks,
                enabled: !busy,
                validator: validateTotalWeeks,
                decoration: const InputDecoration(labelText: '学期总周数'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
            ],
          ),
          EditorSection(
            title: '每天的节次',
            icon: Icons.schedule_rounded,
            subtitle: '点时间即可调整，请与学校作息核对。',
            children: [
              PeriodEditor(
                controller: times,
                fieldKey: periodsField,
                enabled: !busy,
              ),
            ],
          ),
          AppCheckRow(
            contentPadding: EdgeInsets.zero,
            value: confirmed,
            onChanged: busy
                ? null
                : (v) => setState(() => confirmed = v ?? false),
            title: const Text('我已核对学期起始日与节次时间'),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}
