import 'dart:convert';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'reminder_sync.dart';

class AndroidNotifications implements NotificationPort {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  void Function(String owner, String item)? onOpen;
  Map<String, dynamic>? _launch;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    if (!Platform.isAndroid) return;
    tzdata.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: (response) => _open(response.payload),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _open(launch?.notificationResponse?.payload);
    }
  }

  void _open(String? payload) {
    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload ?? '{}'));
      if (data['owner_id'] is! String || data['item_id'] is! String) return;
      if (onOpen == null) {
        _launch = data;
      } else {
        onOpen!(data['owner_id'], data['item_id']);
      }
    } on FormatException {
      return;
    }
  }

  void consumeLaunch() {
    final data = _launch;
    if (data != null && onOpen != null) {
      _launch = null;
      onOpen!(data['owner_id'], data['item_id']);
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
    await plugin.zonedSchedule(
      id: id,
      title: data['title'],
      body: switch (data['purpose']) {
        'start_review' => '开始复习提醒 · 点击查看事项',
        'check_notice' => '记得核实正式通知 · 点击查看事项',
        _ => '事项提醒 · 点击查看详情',
      },
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'semester_items_v1',
          '学期事项提醒',
          channelDescription: '作业、考试和个人任务的已确认提醒',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({
        'owner_id': data['owner_id'],
        'item_id': data['item_id'],
      }),
    );
  }
}
