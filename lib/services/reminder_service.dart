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
    channelDescription: 'Bills due, saving plans and leftover money.',
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

  /// Asks for notification permission where Android needs it (13 and up).
  /// True when reminders can be shown.
  static Future<bool> requestPermission() async {
    try {
      await init();
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
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
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          payload: reminder.payload,
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
          notificationDetails: _details,
          // Inexact: Android may deliver a few minutes late to save battery,
          // and no extra alarm permission is needed.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (error) {
      debugPrint('Could not schedule reminders: $error');
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
