import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'reminder_sync.dart';
import 'notification_target.dart';

class AndroidNotifications
    implements
        NotificationPort,
        PreciseNotificationPort,
        NotificationSettingsPort {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  void Function(String owner, String item)? onOpen;
  void Function(NotificationTarget target)? onTarget;
  Future<bool> Function(NotificationTarget target)? onAction;
  NotificationTarget? _launch;

  Future<void> initialize() => _initializing ??= _initializeRetryable();
  Future<void> _initializeRetryable() async {
    try {
      await _initialize();
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    if (!Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: _respond,
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final response = launch?.notificationResponse;
      if (response != null) _respond(response);
    }
  }

  void _respond(NotificationResponse response) {
    final target = NotificationTarget.decode(
      response.payload,
      actionId: response.actionId ?? '',
      notificationId: response.id,
    );
    if (target == null) return;
    // The app sets handlers after authentication and its startup reconciliation.
    if (onTarget == null && onOpen == null ||
        target.actionId.isNotEmpty && onAction == null) {
      _launch = target;
      return;
    }
    unawaited(_dispatch(target));
  }

  Future<void> _dispatch(NotificationTarget target) async {
    if (target.actionId.isNotEmpty) {
      final handled = await onAction?.call(target) ?? false;
      if (handled) return;
      // A failed/stale action opens the latest detail for review. It must not
      // be replayed a second time by the app's deferred navigation handler.
      target = NotificationTarget(
        ownerId: target.ownerId,
        resourceType: target.resourceType,
        resourceId: target.resourceId,
        semesterId: target.semesterId,
        notificationId: target.notificationId,
        data: target.data,
      );
    }
    if (onTarget != null) {
      onTarget!(target);
    } else {
      onOpen?.call(
        target.ownerId,
        target.resourceType == 'event'
            ? 'event:${target.resourceId}'
            : target.resourceId,
      );
    }
  }

  void consumeLaunch() {
    final target = _launch;
    if (target != null &&
        (onTarget != null || onOpen != null) &&
        (target.actionId.isEmpty || onAction != null)) {
      _launch = null;
      unawaited(_dispatch(target));
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (!Platform.isAndroid ||
        android == null ||
        await android.openAppNotificationSettings() != true) {
      throw Exception('无法打开通知设置，请在手机设置中找到拾日的通知。');
    }
  }

  @override
  Future<bool> permission({bool request = false}) async {
    await initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (!Platform.isAndroid || android == null) return false;
    if (request) return await android.requestNotificationsPermission() ?? false;
    return await android.areNotificationsEnabled() ?? false;
  }

  @override
  Future<bool> precisePermission({bool request = false}) async {
    await initialize();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (!Platform.isAndroid || android == null) return false;
    if (request) await android.requestExactAlarmsPermission();
    return await android.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<Map<int, Map<String, dynamic>>> pending() async {
    await initialize();
    if (!Platform.isAndroid) return {};
    final result = <int, Map<String, dynamic>>{};
    for (final request in await plugin.pendingNotificationRequests()) {
      Map<String, dynamic> payload = {};
      try {
        final decoded = jsonDecode(request.payload ?? '{}');
        if (decoded is Map<String, dynamic>) payload = decoded;
      } on FormatException {
        // Invalid/legacy payloads are unverifiable and will be reconciled away.
      }
      result[request.id] = payload;
    }
    return result;
  }

  @override
  Future<Set<int>> activeIds() async {
    await initialize();
    if (!Platform.isAndroid) return {};
    return {
      for (final notification in await plugin.getActiveNotifications())
        if (notification.id != null) notification.id!,
    };
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    if (Platform.isAndroid) await plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    if (Platform.isAndroid) await plugin.cancelAll();
  }

  @override
  Future<void> schedule(int id, Map<String, dynamic> data) async {
    await initialize();
    if (!Platform.isAndroid) return;
    final when = DateTime.parse(data['trigger_at']);
    if (!when.isAfter(DateTime.now())) return;
    final precise = await precisePermission();
    Future<void> arm(bool exact) => plugin.zonedSchedule(
      id: id,
      title: data['title'],
      body: reminderBody(data),
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'semester_items_v1',
          '学期事项提醒',
          channelDescription: '作业、考试和个人任务的已确认提醒',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          styleInformation: BigTextStyleInformation(reminderBody(data)),
          actions: [
            if (data['can_complete'] == true)
              const AndroidNotificationAction(
                'complete',
                '标记完成',
                showsUserInterface: true,
                cancelNotification: false,
              ),
            const AndroidNotificationAction(
              'snooze_10',
              '10分钟后提醒',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({...data, 'notification_id': id, 'precise': exact}),
    );
    try {
      await arm(precise);
    } on PlatformException catch (error) {
      // A user can revoke the special permission after the check. Preserve a
      // useful reminder through the OS's inexact path in that narrow race.
      if (!precise || error.code != 'exact_alarms_not_permitted') rethrow;
      await arm(false);
    }
  }
}
