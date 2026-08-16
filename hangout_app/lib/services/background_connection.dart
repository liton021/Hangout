import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Foreground-service plumbing that keeps the push WebSocket alive while
/// the app is in the background (Android).
///
/// Android kills backgrounded apps, so a foreground service with a quiet
/// sticky notification keeps the Flutter engine — and therefore
/// [PushService]'s WebSocket to the Cloudflare Worker — running. This is
/// the same approach Telegram/WhatsApp-style persistent connections use,
/// and it's what lets Hangout receive calls & messages without FCM.
class PushTaskHandler extends TaskHandler {
  int _ticks = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    _ticks += 1;
    // Refresh the notification text once a minute — cheap proof of life.
    // The WebSocket reconnect logic itself lives in PushService.
    if (_ticks % 6 == 0) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Hangout',
        notificationText: 'Connected — ready for calls & messages',
      );
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Called by the foreground service (from a background isolate when the
/// app was killed) to re-attach the task handler.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PushTaskHandler());
}

bool _initialized = false;

/// One-time init — call from `main()` before `runApp`.
void initBackgroundConnection() {
  if (_initialized) return;
  _initialized = true;

  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'hangout_connection',
      channelName: 'Background connection',
      channelDescription:
          'Keeps Hangout connected so calls and messages reach you.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

/// Starts the "background connection" service. Call once signed in.
Future<void> startBackgroundConnection() async {
  if (await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.requestNotificationPermission();
  await FlutterForegroundTask.startService(
    notificationTitle: 'Hangout',
    notificationText: 'Connected — ready for calls & messages',
    callback: startCallback,
  );
}

/// Stops the service. Call on sign-out.
Future<void> stopBackgroundConnection() async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}
