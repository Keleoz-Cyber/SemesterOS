import '../../ui/app_loading.dart';
import 'package:flutter/material.dart';
import '../../core/api.dart';
import 'items_controller.dart';
import 'reminder_preferences.dart';
import 'reminder_sync.dart';
import '../../ui/app_controls.dart';
import '../../ui/app_picker_field.dart';
import '../../ui/campus_theme.dart';
import '../../ui/detail_widgets.dart';

class ReminderSettingsPage extends StatefulWidget {
  final ItemsController controller;
  const ReminderSettingsPage({super.key, required this.controller});
  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  bool? notificationAllowed, preciseAllowed;
  bool busy = false;
  int permissionRequest = 0;
  String? error;
  ItemsController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    _permissions();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _permissions(syncOnChange: true);
    }
  }

  Future<void> _permissions({bool syncOnChange = false}) async {
    final request = ++permissionRequest;
    try {
      final allowed = await controller.reminders.port.permission();
      final port = controller.reminders.port;
      final precise = port is PreciseNotificationPort
          ? await (port as PreciseNotificationPort).precisePermission()
          : false;
      if (mounted && request == permissionRequest) {
        final newlyAllowed =
            allowed && notificationAllowed != true ||
            precise && preciseAllowed != true;
        setState(() {
          notificationAllowed = allowed;
          preciseAllowed = precise;
          error = null;
        });
        if (syncOnChange && newlyAllowed) {
          await controller.syncNotifications();
        }
      }
    } catch (_) {
      if (mounted && request == permissionRequest) {
        setState(() {
          notificationAllowed = null;
          preciseAllowed = null;
          error = '暂时无法读取通知权限，请重试';
        });
      }
    }
  }

  Future<void> _openNotifications() async {
    final port = controller.reminders.port;
    if (port is NotificationSettingsPort) {
      await (port as NotificationSettingsPort).openNotificationSettings();
    } else {
      await controller.syncNotifications(requestPermission: true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      await _permissions();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = userError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.reminderPreferences;
    final status = switch (controller.notificationStatus) {
      '已设置准时提醒' || '已设置系统提醒；未开启准时提醒权限，系统可能延迟' => '提醒已同步',
      final message => message,
    };
    final choices = {0, 15, 30, 60, settings.classLeadMinutes}.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('提醒设置')),
      bottomNavigationBar: ActionFooter(
        label: '同步提醒',
        icon: Icons.sync_rounded,
        onPressed: busy ? null : () => _run(controller.refreshOwnerReminders),
      ),
      body: AppLoadingOverlay(
        loading: busy,
        label: '正在更新',
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            EditorSection(
              title: '课程提醒',
              icon: Icons.school_outlined,
              children: [
                const Text('上课提醒仅在这台设备生效。'),
                const SizedBox(height: 16),
                AppSwitchRow(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('上课提醒'),
                  subtitle: const Text('停课、调课后自动更新'),
                  value: settings.classReminders,
                  onChanged: busy
                      ? null
                      : (enabled) => _run(() async {
                          await controller.saveReminderPreferences(
                            ReminderPreferences(
                              classReminders: enabled,
                              classLeadMinutes: settings.classLeadMinutes,
                            ),
                          );
                          if (enabled) {
                            await controller.syncNotifications(
                              requestPermission: true,
                            );
                          }
                        }),
                ),
                if (settings.classReminders)
                  AppPickerField<int>(
                    key: ValueKey(settings.classLeadMinutes),
                    initialValue: settings.classLeadMinutes,
                    decoration: const InputDecoration(labelText: '课程提前多久提醒'),
                    items: [
                      for (final minutes in choices)
                        DropdownMenuItem(
                          value: minutes,
                          child: Text(minutes == 0 ? '上课时' : '提前$minutes分钟'),
                        ),
                    ],
                    onChanged: busy || !settings.classReminders
                        ? null
                        : (lead) {
                            if (lead != null) {
                              _run(
                                () => controller.saveReminderPreferences(
                                  ReminderPreferences(
                                    classReminders: true,
                                    classLeadMinutes: lead,
                                  ),
                                ),
                              );
                            }
                          },
                  ),
              ],
            ),
            EditorSection(
              title: '系统权限',
              icon: Icons.notifications_outlined,
              accent: CampusColors.teal,
              children: [
                AppTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('系统通知'),
                  leading: Icon(
                    notificationAllowed == true
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_none_rounded,
                    color: notificationAllowed == true
                        ? CampusColors.teal
                        : CampusColors.muted,
                  ),
                  subtitle: notificationAllowed == null
                      ? Text(error == null ? '正在检查通知权限' : '暂未读取到权限状态')
                      : Text(notificationAllowed! ? '已允许' : '未开启'),
                  trailing: AppTextButton(
                    style: AppTextButton.styleFrom(
                      backgroundColor: CampusColors.blueSoft,
                      foregroundColor: CampusColors.primary,
                    ),
                    onPressed: busy ? null : () => _run(_openNotifications),
                    child: Text(notificationAllowed == true ? '设置' : '开启'),
                  ),
                ),
                AppTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('准时提醒'),
                  leading: Icon(
                    preciseAllowed == true
                        ? Icons.alarm_on_rounded
                        : Icons.alarm_rounded,
                    color: preciseAllowed == true
                        ? CampusColors.teal
                        : CampusColors.muted,
                  ),
                  subtitle: preciseAllowed == true
                      ? const Text('已开启')
                      : notificationAllowed == false
                      ? const Text('先开启系统通知')
                      : preciseAllowed == false
                      ? const Text('未开启时，系统可能延迟提醒')
                      : Text(error == null ? '正在检查准时提醒权限' : '暂未读取到权限状态'),
                  trailing: preciseAllowed == true
                      ? const Icon(Icons.check_circle_outline)
                      : AppTextButton(
                          style: AppTextButton.styleFrom(
                            backgroundColor: CampusColors.blueSoft,
                            foregroundColor: CampusColors.primary,
                          ),
                          onPressed:
                              busy ||
                                  notificationAllowed != true ||
                                  controller.reminders.port
                                      is! PreciseNotificationPort
                              ? null
                              : () => _run(() async {
                                  await (controller.reminders.port
                                          as PreciseNotificationPort)
                                      .precisePermission(request: true);
                                  await controller.syncNotifications();
                                }),
                          child: const Text('开启'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (status != null)
              Text(
                status,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
