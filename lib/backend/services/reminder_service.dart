import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

/// Shows and schedules reminders on this phone.
///
/// Everything is scheduled on the device, so reminders arrive without a
/// connection and without the app open. The plan of what to send lives in
/// [planReminders]; this only hands it to Android.
class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// The set-up under way, shared by everyone who asks while it runs.
  static Future<void>? _starting;

  /// The payload of a reminder the user tapped, waiting to be opened. Set
  /// before the app has signed in too, so it is opened once it can be.
  static final ValueNotifier<String?> opened = ValueNotifier(null);

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: 'Bills due, saving plans and logging your spending.',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    color: Color(0xFF1976D2),
  );

  static const _details = NotificationDetails(android: _channel);

  /// The sample reminder's id. Planned reminders use hashed ids, and planning
  /// again leaves this one alone.
  static const _testId = 1;

  /// Sets up time zones and the plugin. Safe to call more than once, even
  /// while it is still running, and never throws: an app without reminders
  /// still works. A failed set-up is tried again on the next call.
  static Future<void> init() async {
    if (_ready) return;
    await (_starting ??= _start().whenComplete(() => _starting = null));
  }

  static Future<void> _start() async {
    try {
      tz_data.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        // A peso app: Manila is the right guess when the phone won't say.
        tz.setLocalLocation(tz.getLocation('Asia/Manila'));
      }

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
        ),
        onDidReceiveNotificationResponse: (response) {
          opened.value = response.payload;
        },
      );

      // Exact delivery when Android allows it, inexact otherwise; a reminder
      // still arrives either way.
      await _refreshExactPermission();

      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        opened.value = launch?.notificationResponse?.payload;
      }

      _ready = true;
    } catch (error) {
      debugPrint('Reminders unavailable: $error');
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Asks for notification permission where Android needs it (13 and up),
  /// and for exact alarms where the phone allows that choice (12 and up).
  /// True when reminders can be shown.
  static Future<bool> requestPermission() async {
    try {
      await init();
      final notifications =
          await _android?.requestNotificationsPermission() ?? false;
      final exact = _android;
      if (exact != null) {
        try {
          await exact.requestExactAlarmsPermission();
          await _refreshExactPermission();
        } catch (_) {
          // Inexact delivery is still fine.
        }
      }
      return notifications;
    } catch (_) {
      return false;
    }
  }

  /// Whether the phone will let FinAssist schedule an exact alarm. False on
  /// older Android and when the user has not granted it; scheduling then
  /// falls back to an inexact alarm instead of failing.
  static bool _exactScheduling = false;

  static Future<void> _refreshExactPermission() async {
    try {
      _exactScheduling =
          await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      _exactScheduling = false;
    }
  }

  /// Clears every reminder, on screen and still to come. Used when the
  /// signed-in account changes, so one account's reminders never show while
  /// another is signed in.
  static Future<void> cancelAll() async {
    await init();
    if (!_ready) return;

    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('Could not clear reminders: $error');
    }
  }

  /// Replaces whatever was scheduled with [reminders].
  ///
  /// Reminders no longer in the plan are cancelled one by one, rather than
  /// clearing everything, so notifications already on screen stay there.
  static Future<void> schedule(List<PlannedReminder> reminders) async {
    await init();
    if (!_ready) return;

    try {
      final wanted = {for (final reminder in reminders) reminder.id};
      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.id == _testId || wanted.contains(pending.id)) continue;
        await _plugin.cancel(id: pending.id);
      }

      for (final reminder in reminders) {
        await _scheduleOne(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          payload: reminder.payload,
          at: tz.TZDateTime.from(reminder.at, tz.local),
        );
      }
    } catch (error) {
      debugPrint('Could not schedule reminders: $error');
    }
  }

  /// Schedules one notification, exactly when the phone allows it and
  /// inexactly otherwise. The fallback also covers a permission revoked
  /// after the last check, so a reminder is never silently dropped.
  static Future<void> _scheduleOne({
    required int id,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime at,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: payload,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: _exactScheduling
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      _exactScheduling = false;
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        payload: payload,
        scheduledDate: at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Schedules a sample reminder a few seconds from now, the same way real
  /// reminders are scheduled, so the user can see one arrive and tap it.
  static Future<bool> showTest({
    Duration after = const Duration(seconds: 10),
  }) async {
    final allowed = await requestPermission();
    if (!allowed || !_ready) return false;

    try {
      await _plugin.zonedSchedule(
        id: _testId,
        title: 'Reminders are on',
        body:
            'This is how FinAssist reminds you about bills and savings. '
            'Tap to open the app.',
        payload: 'test',
        scheduledDate: tz.TZDateTime.now(tz.local).add(after),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
