import '../../ui/app_loading.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_choice_strip.dart';
import '../../ui/campus_theme.dart';
import 'profile_controller.dart';

class ProfilePage extends StatefulWidget {
  final ProfileController controller;
  final bool onboarding;
  final VoidCallback? onDone;
  const ProfilePage({
    super.key,
    required this.controller,
    this.onboarding = false,
    this.onDone,
  });
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final form = GlobalKey<FormState>();
  final school = TextEditingController(),
      college = TextEditingController(),
      major = TextEditingController(),
      className = TextEditingController(),
      role = TextEditingController(),
      year = TextEditingController();
  String? education;
  late final String? owner;
  late final int generation;
  int version = 0;
  bool initialized = false, completed = false;
  ProfileController get c => widget.controller;
  bool get validOwner => owner == c.owner && generation == c.generation;

  @override
  void initState() {
    super.initState();
    owner = c.owner;
    generation = c.generation;
    c.addListener(changed);
    if (!c.loading) apply(c.draft ?? c.profile);
  }

  void apply(UserProfile value) {
    initialized = true;
    version = value.version;
    school.text = value.school;
    college.text = value.college;
    major.text = value.major;
    className.text = value.className;
    role.text = value.classRole;
    year.text = value.entryYear?.toString() ?? '';
    education = value.educationLevel;
  }

  void changed() {
    if (!mounted) return;
    if (!initialized && !c.loading && validOwner) apply(c.draft ?? c.profile);
    setState(() {});
  }

  UserProfile get current => UserProfile(
    version: version,
    school: school.text,
    college: college.text,
    major: major.text,
    className: className.text,
    classRole: role.text,
    educationLevel: education,
    entryYear: int.tryParse(year.text.trim()),
  );

  Future<void> remember() async {
    if (initialized && !completed && validOwner) await c.rememberDraft(current);
  }

  void finish() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.maybePop(context);
    }
  }

  void skip() {
    if (!validOwner) return;
    unawaited(remember());
    completed = true;
    unawaited(c.skip());
    finish();
  }

  Future<void> save() async {
    if (!validOwner || !validateAppForm(form)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await c.save(current);
    if (!mounted || !validOwner) return;
    if (result == ProfileSaveResult.saved) {
      completed = true;
      finish();
    }
  }

  Future<void> reviewConflict() async {
    if (c.offline) {
      await c.reload();
      if (!mounted || !validOwner || c.offline) return;
    }
    final latest = c.profile;
    Map<String, String> facts(UserProfile p) => <String, String>{
      '学校': p.school,
      '学院': p.college,
      '专业': p.major,
      '班级': p.className,
      '培养层次': switch (p.educationLevel) {
        'undergraduate' => '本科',
        'postgraduate' => '研究生',
        _ => '',
      },
      '入学年份': p.entryYear?.toString() ?? '',
      '班级职务': p.classRole,
    };
    final fields = facts(latest), local = facts(current);
    final differences = fields.entries
        .where((e) => e.value != local[e.key])
        .toList();
    final useLatest = await showDialog<bool>(
      context: context,
      builder: (dialog) => AppDialog(
        title: const Text('最新保存的资料'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in differences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        field.key,
                        style: const TextStyle(
                          fontSize: 13,
                          color: CampusColors.muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (local[field.key]?.isNotEmpty == true)
                        Text(
                          '当前：${local[field.key]}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: CampusColors.muted,
                          ),
                        ),
                      Text(
                        field.value.isEmpty ? '最新：已清除' : '最新：${field.value}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: CampusColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (differences.isEmpty) const Text('内容相同，可以保留当前填写。'),
            ],
          ),
        ),
        actions: [
          AppTextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留当前填写'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('使用最新资料'),
          ),
        ],
      ),
    );
    if (useLatest == null || !mounted || !validOwner) return;
    setState(() => apply(c.resolveConflict(useLatest: useLatest)));
  }

  String? textLength(String? value) =>
      (value?.trim().length ?? 0) > 120 ? '最多填写120字' : null;

  Widget field(
    String id,
    String label,
    TextEditingController controller, {
    String? hint,
  }) => AppFormField(
    key: Key('profile-$id'),
    controller: controller,
    enabled: !c.busy && validOwner,
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator: textLength,
  );

  Widget group(String title, IconData icon, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: CampusColors.teal),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: CampusColors.line),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop || completed) return;
      if (widget.onboarding) {
        unawaited(remember());
        completed = true;
        if (validOwner) unawaited(c.skip());
      } else {
        unawaited(remember());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? '填写个人资料' : '个人资料'),
        automaticallyImplyLeading: false,
        leading: AppIconButton(
          tooltip: widget.onboarding ? '稍后填写' : '返回',
          onPressed: c.busy
              ? null
              : () {
                  if (widget.onboarding) {
                    skip();
                  } else {
                    unawaited(remember());
                    finish();
                  }
                },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          if (widget.onboarding)
            AppTextButton(
              key: const Key('profile-skip'),
              onPressed: c.busy ? null : skip,
              child: const Text('稍后填写'),
            ),
        ],
      ),
      bottomNavigationBar: initialized
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: AppButton(
                  key: const Key('profile-save'),
                  onPressed: c.busy || c.loading || c.conflict || !validOwner
                      ? null
                      : save,
                  child: Text(
                    c.busy
                        ? '正在保存…'
                        : widget.onboarding
                        ? '保存并继续'
                        : '保存资料',
                  ),
                ),
              ),
            )
          : null,
      body: !initialized
          ? const Center(child: AppLoadingIndicator(label: '正在读取资料'))
          : SafeArea(
              top: false,
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (widget.onboarding) ...[
                      const Text(
                        '资料选填，用于匹配通知对象。',
                        style: TextStyle(
                          color: CampusColors.muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (c.offline) ...[
                      const Text(
                        '暂时无法同步，正在显示本机资料。',
                        style: TextStyle(color: CampusColors.warning),
                      ),
                      const SizedBox(height: 12),
                    ],
                    group('学校与班级', Icons.school_outlined, [
                      field('school', '学校', school),
                      field('college', '学院', college),
                      field('major', '专业', major),
                      field('class', '班级', className),
                    ]),
                    const SizedBox(height: 8),
                    group('学习信息', Icons.badge_outlined, [
                      const Text(
                        '培养层次',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      AppOptionalChoiceStrip<String>(
                        key: const Key('profile-education'),
                        value: education,
                        options: const {
                          'undergraduate': '本科',
                          'postgraduate': '研究生',
                        },
                        icons: const {
                          'undergraduate': Icons.school_outlined,
                          'postgraduate': Icons.menu_book_rounded,
                        },
                        enabled: !c.busy && validOwner,
                        onChanged: (next) => setState(() => education = next),
                      ),
                      const SizedBox(height: 14),
                      AppFormField(
                        key: const Key('profile-year'),
                        controller: year,
                        enabled: !c.busy && validOwner,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(
                          labelText: '入学年份',
                          hintText: '如2024',
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final number = int.tryParse(value);
                          return number != null &&
                                  number >= 1900 &&
                                  number <= 2200
                              ? null
                              : '填写1900—2200之间的年份，或留空';
                        },
                      ),
                      field('role', '班级职务', role, hint: '如学习委员'),
                    ]),
                    const SizedBox(height: 20),
                    if (c.error != null || c.conflict) ...[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          c.error ?? '资料已更新，当前填写已保留。',
                          style: TextStyle(
                            color: c.conflict
                                ? CampusColors.primary
                                : CampusColors.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (c.conflict)
                      AppOutlineButton(
                        key: const Key('profile-review'),
                        guardAsync: false,
                        onPressed: c.busy || c.loading ? null : reviewConflict,
                        child: Text(c.offline ? '联网后核对最新资料' : '核对最新资料'),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );

  @override
  void dispose() {
    c.removeListener(changed);
    unawaited(remember());
    for (final controller in [school, college, major, className, role, year]) {
      controller.dispose();
    }
    super.dispose();
  }
}
