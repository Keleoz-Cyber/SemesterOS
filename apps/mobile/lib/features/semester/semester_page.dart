import '../../ui/app_controls.dart';
import '../../ui/app_date_time_picker.dart' show appDatePickerBounds;
import 'dart:convert';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import 'semester_validation.dart';
import 'period_editor.dart';
import '../../ui/detail_widgets.dart';
import '../../ui/campus_widgets.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/campus_theme.dart';
import '../../ui/date_labels.dart' show studentDate;
import '../centers/academic_visuals.dart';

DateTime firstMondayFromCurrentWeek(int week, {DateTime? today}) {
  final now = today ?? schoolNow();
  final date = DateTime.utc(now.year, now.month, now.day);
  return date.subtract(Duration(days: date.weekday - 1 + (week - 1) * 7));
}

String _calendarDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class SemesterPage extends StatefulWidget {
  final AppController controller;
  final Map<String, dynamic>? existing;
  final int pendingNoticeCount;
  const SemesterPage({
    super.key,
    required this.controller,
    this.existing,
    this.pendingNoticeCount = 0,
  });
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
  final currentWeek = TextEditingController();
  bool inferMonday = false;
  bool busy = false, submitted = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    inferMonday = existing == null;
    final now = schoolNow();
    final autumn = now.month >= 8 || now.month == 1;
    final startYear = now.month >= 8 ? now.year : now.year - 1;
    name = TextEditingController(
      text:
          existing?['name'] ??
          '$startYear—${startYear + 1}学年${autumn ? '第一' : '第二'}学期',
    );
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
    for (final c in [name, monday, weeks, times, currentWeek]) {
      c.dispose();
    }
    super.dispose();
  }

  void inferFromWeek(String value) {
    final week = int.tryParse(value.trim());
    setState(() {
      monday.text =
          week != null && week > 0 && week <= (int.tryParse(weeks.text) ?? 60)
          ? _calendarDate(firstMondayFromCurrentWeek(week))
          : '';
      error = null;
    });
    if (submitted) mondayField.currentState?.validate();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() {
      submitted = true;
      error = null;
    });
    if (inferMonday) {
      final value = int.tryParse(currentWeek.text.trim());
      final total = int.tryParse(weeks.text.trim());
      if (value == null || value < 1 || (total != null && value > total)) {
        form.currentState!.validate();
        setState(() => error = '请核对本学期当前周次和总周数');
        revealInvalid(1);
        return;
      }
    }
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
    if (!validateAppForm(form)) {
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing['first_monday'] != monday.text.trim())
                  _CalendarChange(
                    label: '第1周周一',
                    before: '${existing['first_monday']}',
                    after: monday.text.trim(),
                  ),
                if (existing['total_weeks'] != int.parse(weeks.text.trim()))
                  _CalendarChange(
                    label: '学期周数',
                    before: '${existing['total_weeks']}周',
                    after: '${weeks.text.trim()}周',
                  ),
                if (jsonEncode(existing['periods']) != jsonEncode(periods))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '每天的节次时间已调整',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '课表随之更新',
                  style: TextStyle(fontSize: 14, color: CampusColors.muted),
                ),
              ],
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
        if ((saved['affected_plan_count'] as num? ?? 0) > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('设置已保存，${saved['affected_plan_count']} 段个人计划需要调整'),
            ),
          );
        }
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !scroll.hasClients) return;
      final key = [nameField, mondayField, weeksField, periodsField][index];
      if (key.currentContext == null) {
        await scroll.animateTo(
          index < 3 ? 0 : scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted || key.currentContext == null) return;
      key.currentState?.validate();
      await Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 250),
        alignment: .15,
      );
    });
  }

  Future<void> chooseMonday() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final now = schoolNow();
    final saved = DateTime.tryParse(monday.text) ?? now;
    final day = DateTime.utc(saved.year, saved.month, saved.day);
    final initial = day.subtract(Duration(days: day.weekday - DateTime.monday));
    final bounds = appDatePickerBounds(
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    final chosen = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: bounds.start,
      lastDate: bounds.end,
      currentDate: DateTime.utc(now.year, now.month, now.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
      helpText: '选择学校校历第1周的周一',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (chosen == null || !mounted) return;
    setState(() {
      inferMonday = false;
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
      onPressed: !busy ? save : null,
    ),
    body: Form(
      key: form,
      autovalidateMode: submitted
          ? AutovalidateMode.always
          : AutovalidateMode.disabled,
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.existing == null && widget.pendingNoticeCount > 0)
            const SoftNotice('通知已暂存，建立学期后继续核对。'),
          AcademicEditorSection(
            title: '学期校历',
            icon: Icons.date_range_outlined,
            children: [
              AppFormField(
                key: nameField,
                controller: name,
                enabled: !busy,
                minLines: 1,
                maxLines: 3,
                validator: validateSemesterName,
                decoration: const InputDecoration(labelText: '学期名称'),
              ),
              const SizedBox(height: 14),
              AppPickerField<bool>(
                key: const Key('semester-monday-mode'),
                initialValue: inferMonday,
                decoration: const InputDecoration(labelText: '开学日期'),
                items: const [
                  DropdownMenuItem(value: false, child: Text('按校历选择')),
                  DropdownMenuItem(value: true, child: Text('按当前周推算')),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => inferMonday = value);
                        if (value) inferFromWeek(currentWeek.text);
                      },
              ),
              if (inferMonday) ...[
                const SizedBox(height: 14),
                AppFormField(
                  key: const Key('semester-current-week'),
                  controller: currentWeek,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  onChanged: inferFromWeek,
                  decoration: const InputDecoration(labelText: '现在是第几周'),
                  validator: (value) {
                    final week = int.tryParse(value?.trim() ?? '');
                    final total = int.tryParse(weeks.text.trim());
                    if (week == null || week < 1) return '填写本学期当前周次';
                    if (total != null && week > total) return '当前周不能超过学期总周数';
                    return null;
                  },
                ),
              ],
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
                onChanged: (_) => setState(() {}),
              ),
              if (DateTime.tryParse(monday.text) != null &&
                  (int.tryParse(weeks.text) ?? 0) > 0 &&
                  (int.tryParse(weeks.text) ?? 0) <= 60)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.south_east_rounded,
                        size: 18,
                        color: CampusColors.teal,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '学期至 ${studentDate(DateTime.parse(monday.text).add(Duration(days: int.parse(weeks.text) * 7 - 1)))}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: CampusColors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          AcademicEditorSection(
            title: '每天的节次',
            icon: Icons.schedule_rounded,
            accent: CampusColors.teal,
            subtitle: widget.existing == null ? '示例时间，按学校作息修改' : null,
            children: [
              PeriodEditor(
                controller: times,
                fieldKey: periodsField,
                enabled: !busy,
              ),
            ],
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

class _CalendarChange extends StatelessWidget {
  const _CalendarChange({
    required this.label,
    required this.before,
    required this.after,
  });
  final String label, before, after;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: CampusColors.muted),
        ),
        const SizedBox(height: 6),
        Text(
          before,
          style: const TextStyle(fontSize: 14, color: CampusColors.muted),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 18,
              color: CampusColors.teal,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                after,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: CampusColors.teal,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
