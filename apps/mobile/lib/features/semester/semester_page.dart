import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/controller.dart';
import 'semester_validation.dart';
import '../../ui/campus_widgets.dart';

class SemesterPage extends StatefulWidget {
  final AppController controller;
  const SemesterPage({super.key, required this.controller});
  @override
  State<SemesterPage> createState() => _SemesterPageState();
}

class _SemesterPageState extends State<SemesterPage> {
  final form = GlobalKey<FormState>();
  final nameField = GlobalKey<FormFieldState<String>>();
  final mondayField = GlobalKey<FormFieldState<String>>();
  final weeksField = GlobalKey<FormFieldState<String>>();
  final periodsField = GlobalKey<FormFieldState<String>>();
  final name = TextEditingController(text: '2026—2027学年第一学期');
  final monday = TextEditingController(),
      weeks = TextEditingController(text: '20');
  final times = TextEditingController(
    text:
        '1 08:00 08:50\n2 09:00 09:50\n3 10:10 11:00\n4 11:10 12:00\n5 14:00 14:50\n6 15:00 15:50\n7 16:10 17:00\n8 17:10 18:00\n9 19:00 19:50\n10 20:00 20:50',
  );
  bool confirmed = false, busy = false, submitted = false;
  String? error;
  @override
  void dispose() {
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final periods = parseSemesterPeriods(times.text);
      final created = await widget.controller.api.request(
        'POST',
        '/semesters',
        data: {
          'name': name.text.trim(),
          'first_monday': monday.text.trim(),
          'total_weeks': int.parse(weeks.text.trim()),
          'periods': periods,
        },
      );
      await widget.controller.openSession(null, '${created['id']}');
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
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
    appBar: AppBar(title: const Text('建立我的学期')),
    body: Form(
      key: form,
      autovalidateMode: submitted
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CampusHero(
            eyebrow: '学期设置',
            title: '新的学期',
            subtitle: '把课程安排\n放在正确的日期',
          ),
          const SizedBox(height: 16),
          const SoftNotice('下面的作息仅为可编辑示例。请按学校校历核对第1周与节次时间。'),
          const SectionHeading('基本信息'),
          TextFormField(
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
            child: TextFormField(
              key: mondayField,
              controller: monday,
              enabled: !busy,
              readOnly: true,
              onTap: chooseMonday,
              validator: validateFirstMonday,
              decoration: InputDecoration(
                labelText: '第一周周一（必填）',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                hintText: '点击选择日期',
                helperText: '按学校校历选择，不能留空；日历仅可选周一',
                helperMaxLines: 2,
                errorMaxLines: 2,
                suffixIcon: IconButton(
                  onPressed: busy ? null : chooseMonday,
                  icon: const Icon(Icons.calendar_month_outlined),
                  tooltip: '选择第1周周一',
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: weeksField,
            controller: weeks,
            enabled: !busy,
            validator: validateTotalWeeks,
            decoration: const InputDecoration(labelText: '学期总周数'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: periodsField,
            controller: times,
            enabled: !busy,
            validator: validateSemesterPeriods,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '节次与时间（示例，可修改）',
              helperText: '每行：节次 开始时间 结束时间',
              errorMaxLines: 3,
            ),
          ),
          CheckboxListTile(
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
          FilledButton(
            onPressed: confirmed && !busy ? save : null,
            child: Text(busy ? '正在保存…' : '确认创建学期'),
          ),
        ],
      ),
    ),
  );
}
