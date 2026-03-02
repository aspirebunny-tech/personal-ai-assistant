import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );
    await _notifications.initialize(settings);
  }

  static Future<void> showReminder({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'reminders_channel',
      'Reminders',
      channelDescription: 'Personal AI Assistant Reminders',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _notifications.show(id, '⏰ $title', body, details);
  }

  static Future<void> showSyncSuccess() async {
    const androidDetails = AndroidNotificationDetails(
      'sync_channel', 'Sync',
      channelDescription: 'Sync notifications',
      importance: Importance.low,
      priority: Priority.low,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notifications.show(999, '✅ Sync Complete', 'Notes sync ho gaye!', details);
  }
}
