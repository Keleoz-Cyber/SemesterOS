import '../../ui/app_controls.dart';
import '../../ui/app_selection.dart';
import '../../ui/brand.dart';
import '../../ui/campus_theme.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import 'recovery_code_dialog.dart';

class AuthPage extends StatefulWidget {
  final AppController controller;
  final int initialMode, pendingNoticeCount;
  const AuthPage({
    super.key,
    required this.controller,
    this.initialMode = 0,
    this.pendingNoticeCount = 0,
  });
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController(),
      password = TextEditingController(),
      recovery = TextEditingController();
  final form = GlobalKey<FormState>();
  int mode = 0;
  bool busy = false, obscure = true;
  String? error, success;
  @override
  void initState() {
    super.initState();
    mode = widget.initialMode;
  }

  @override
  void didUpdateWidget(covariant AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      mode = widget.initialMode;
      error = null;
      success = null;
    }
  }

  Future<void> tryDemo() async {
    if (busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      await widget.controller.startDemo();
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    recovery.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!validateAppForm(form) || busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
      success = null;
    });
    try {
      final data = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'POST',
          mode == 2
              ? '/auth/recover'
              : mode == 1
              ? '/auth/register'
              : '/auth/login',
          authenticated: false,
          data: mode == 2
              ? {
                  'username': username.text.trim(),
                  'recovery_code': recovery.text.trim(),
                  'new_password': password.text,
                }
              : {'username': username.text.trim(), 'password': password.text},
        ),
      );
      if (!mounted) return;
      if (data['recovery_code'] != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => RecoveryCodeDialog(code: '${data['recovery_code']}'),
        );
      }
      if (mode == 2) {
        if (mounted) {
          setState(() {
            mode = 0;
            success = '密码已更新，请登录';
          });
        }
      } else {
        await widget.controller.openSession(data);
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        BrandMark(size: 36),
                        SizedBox(width: 12),
                        Text(
                          appName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: CampusColors.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      mode == 2
                          ? '恢复账户'
                          : mode == 1
                          ? '创建账户'
                          : '登录拾日',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: CampusColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mode == 2
                          ? '输入账户恢复码，设置新密码。'
                          : mode == 1
                          ? '课表与安排将保存在这个账户中。'
                          : '继续查看课表与安排。',
                      style: const TextStyle(
                        fontSize: 14,
                        color: CampusColors.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (widget.pendingNoticeCount > 0) ...[
                      const Text(
                        '分享的通知已暂存。登录或先体验后，可以继续核对。',
                        style: TextStyle(
                          color: CampusColors.primary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (mode != 2)
                          AppSegmentedControl<int>(
                            options: const {0: '登录', 1: '注册'},
                            value: mode,
                            enabled: !busy,
                            onChanged: (value) => setState(() {
                              mode = value;
                              error = null;
                              success = null;
                            }),
                          ),
                        const SizedBox(height: 20),
                        AppFormField(
                          key: const Key('username'),
                          controller: username,
                          enabled: !busy,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: '用户名',
                            helperText: mode == 1 ? '4—32位字母、数字或下划线' : null,
                            helperMaxLines: 2,
                          ),
                          validator: (v) =>
                              RegExp(
                                r'^[a-zA-Z0-9_]{4,32}$',
                              ).hasMatch(v?.trim() ?? '')
                              ? null
                              : '用户名需4—32位字母、数字或下划线',
                        ),
                        const SizedBox(height: 16),
                        if (mode == 2) ...[
                          AppFormField(
                            controller: recovery,
                            enabled: !busy,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '账户恢复码',
                            ),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? '请填写账户恢复码'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        AppFormField(
                          key: const Key('password'),
                          controller: password,
                          enabled: !busy,
                          obscureText: obscure,
                          autofillHints: [
                            mode == 0
                                ? AutofillHints.password
                                : AutofillHints.newPassword,
                          ],
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => submit(),
                          decoration: InputDecoration(
                            labelText: mode == 2 ? '新密码' : '密码',
                            helperText: mode == 0 ? null : '至少8位',
                            suffixIcon: AppIconButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => obscure = !obscure),
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              tooltip: obscure ? '显示密码' : '隐藏密码',
                            ),
                          ),
                          validator: (v) =>
                              (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                              ? null
                              : '密码需要8—128位',
                        ),
                        const SizedBox(height: 20),
                        if (error != null || success != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  success != null
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.error_outline_rounded,
                                  size: 20,
                                  color: success != null
                                      ? CampusColors.teal
                                      : CampusColors.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      success ?? error!,
                                      style: TextStyle(
                                        height: 1.5,
                                        fontSize: 14,
                                        color: success != null
                                            ? CampusColors.teal
                                            : CampusColors.error,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        AppButton(
                          key: const Key('auth-submit'),
                          onPressed: busy ? null : submit,
                          child: Text(
                            busy
                                ? '请稍候…'
                                : mode == 2
                                ? '设置新密码'
                                : mode == 1
                                ? '创建账户'
                                : '登录',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      children: [
                        if (mode != 2)
                          AppTextButton.icon(
                            key: const Key('auth-demo'),
                            onPressed: busy ? null : tryDemo,
                            icon: const Icon(Icons.explore_outlined, size: 18),
                            label: const Text('先体验'),
                          ),
                        AppTextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  mode = mode == 2 ? 0 : 2;
                                  error = null;
                                  success = null;
                                }),
                          child: Text(mode == 2 ? '返回登录' : '忘记密码'),
                        ),
                      ],
                    ),
                    if (mode != 2)
                      const Text(
                        '体验使用独立演示数据。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: CampusColors.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
