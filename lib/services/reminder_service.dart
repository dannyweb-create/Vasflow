import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../models/application_record.dart';
import '../models/task_record.dart';

/// Local deadline reminders (tasks, applications, overdue nudges), built on
/// flutter_local_notifications. No backend push notification system is
/// wired yet - these fire for reminders created while the app is open and
/// persist across reboots through the plugin's boot receiver.
///
/// Platform setup (manifest permissions, boot receiver) lives in
/// tool/prepare_android.sh. Until a device build is tested, treat these
/// reminders as experimental: every scheduling call is wrapped so failures
/// never break the UI.
class ReminderService {
  static const _enabledKey = 'reminders_enabled';
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> init() => _ensureReady();

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    if (!value) await cancelAll();
  }

  static Future<void> _ensureReady() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    try {
      final localName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // Without the device zone, reminders still fire based on UTC.
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    try {
      await _plugin.initialize(settings: settings);
      _ready = true;
    } catch (e) {
      debugPrint('Reminder init failed: $e');
    }
  }

  static int _hash(String id) => id.hashCode & 0x7fffffff;

  static DateTime? _alarmFor(DateTime? date, int daysBefore) {
    if (date == null) return null;
    final when = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: daysBefore)).add(const Duration(hours: 9));
    return when.isAfter(DateTime.now()) ? when : null;
  }

  /// One-off nudge at 08:00 the morning after something became overdue.
  static DateTime? _overdueAlarm(DateTime due) {
    final when = DateTime(
      due.year,
      due.month,
      due.day,
    ).add(const Duration(days: 1, hours: 8));
    return when.isAfter(DateTime.now()) ? when : null;
  }

  static Future<void> schedule(
    String id,
    String title,
    String body,
    DateTime when,
  ) async {
    try {
      final android =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
    try {
      await _plugin.zonedSchedule(
        id: _hash(id),
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'vasflow_deadlines',
            'Deadlines & tasks',
            channelDescription: 'Task and application deadline reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
    }
  }

  static Future<void> cancel(String id) async {
    try {
      await _plugin.cancel(id: _hash(id));
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    await _ensureReady();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static String _dateSuffix(DateTime? date) =>
      date == null ? '' : ' \u00b7 ${date.month}/${date.day}';

  /// Keeps a task's reminder in sync after add, edit, tick or delete.
  static Future<void> syncTask(TaskRecord task) async {
    await cancel('task-${task.id}');
    await cancel('overdue-${task.id}');
    if (task.done) return;
    final oneDayBefore = _alarmFor(task.dueDate, 1);
    if (oneDayBefore != null) {
      await schedule(
        'task-${task.id}',
        'Task due soon',
        task.title,
        oneDayBefore,
      );
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (task.dueDate != null && task.dueDate!.isBefore(today)) {
      final overdueWhen = _overdueAlarm(task.dueDate!);
      if (overdueWhen != null) {
        await schedule(
          'overdue-${task.id}',
          'Task overdue',
          task.title,
          overdueWhen,
        );
      }
    }
  }

  /// Reminds 7 days and 1 day before an application deadline.
  static Future<void> syncApplication(ApplicationRecord app) async {
    await cancel('app1-${app.id}');
    await cancel('app7-${app.id}');
    final oneDayBefore = _alarmFor(app.deadline, 1);
    if (oneDayBefore != null) {
      await schedule(
        'app1-${app.id}',
        'Deadline tomorrow',
        app.institution.isEmpty
            ? 'Application deadline${_dateSuffix(app.deadline)}'
            : '${app.institution} deadline${_dateSuffix(app.deadline)}',
        oneDayBefore,
      );
    }
    final weekBefore = _alarmFor(app.deadline, 7);
    if (weekBefore != null) {
      await schedule(
        'app7-${app.id}',
        'Deadline next week',
        app.institution.isEmpty
            ? 'Application deadline${_dateSuffix(app.deadline)}'
            : '${app.institution} deadline${_dateSuffix(app.deadline)}',
        weekBefore,
      );
    }
  }
}
