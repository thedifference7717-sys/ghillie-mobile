// Copyright (c) 2026, The CAMO Project. BSD-3-Clause, see LICENSE.
//
// Phone reminders for subscriptions: one notification at 9:00 on each payment's next due day. The text never names
// the payment, amount or address (it shows on the lock screen); opening Ghillie and unlocking shows the details.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'subscriptions.dart';

abstract class PaymentReminders {
  /// Replaces all scheduled reminders with one for each subscription's next due date.
  Future<void> sync(List<Subscription> items, DateTime now);
}

class NoReminders implements PaymentReminders {
  @override
  Future<void> sync(List<Subscription> items, DateTime now) async {}
}

/// For tests: records what would be scheduled.
class MemoryReminders implements PaymentReminders {
  final scheduled = <int, DateTime>{};
  @override
  Future<void> sync(List<Subscription> items, DateTime now) async {
    scheduled
      ..clear()
      ..addAll({for (final (id, at) in plan(items, now)) id: at});
  }
}

const reminderHour = 9;
const reminderTitle = 'Ghillie';
const reminderBody = 'A subscription payment is due today. Open Ghillie to review and confirm it.';

/// Stable notification id per subscription (ids must fit in 31 bits on Android).
int reminderId(String subscriptionId) {
  var h = 17;
  for (final c in subscriptionId.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return h;
}

/// (id, local time) for each subscription's next reminder. Reminders already past (today after 9:00 for a payment due
/// today) are skipped: the app shows it as due anyway.
List<(int, DateTime)> plan(List<Subscription> items, DateTime now) => [
      for (final s in items)
        if (DateTime(s.nextDate(now).year, s.nextDate(now).month, s.nextDate(now).day, reminderHour).isAfter(now))
          (reminderId(s.id), DateTime(s.nextDate(now).year, s.nextDate(now).month, s.nextDate(now).day, reminderHour)),
    ];

class DeviceReminders implements PaymentReminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // ask for permission only when the first subscription is saved, not at app start
        iOS: DarwinInitializationSettings(
            requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
    );
    _ready = true;
  }

  Future<void> _askOnce() async {
    if (_asked) return;
    _asked = true;
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> sync(List<Subscription> items, DateTime now) async {
    try {
      await _init();
      await _plugin.cancelAll();
      if (items.isEmpty) return;
      await _askOnce();
      for (final (id, at) in plan(items, now)) {
        await _plugin.zonedSchedule(
          id: id,
          title: reminderTitle,
          body: reminderBody,
          // the instant of 9:00 local time; a one-off reminder, re-planned whenever the list changes or the app opens
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('payments', 'Payment reminders',
                channelDescription: 'A reminder on the day a saved subscription is due',
                visibility: NotificationVisibility.public),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // reminders are a convenience; never break the wallet over them
    }
  }
}

PaymentReminders paymentReminders = NoReminders();
