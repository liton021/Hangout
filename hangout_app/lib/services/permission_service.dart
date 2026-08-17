import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Outcome of asking for call permissions.
enum CallPermissionResult { granted, denied, permanentlyDenied }

/// Requests the runtime permissions Hangout needs for calls.
///
/// The Android manifest already declares CAMERA / RECORD_AUDIO, but Android
/// 6+ (and especially 13+) still shows a runtime prompt the first time the
/// app uses them. This service is what triggers that prompt — on first
/// launch and again before every call, so a call never silently starts
/// without the mic/camera.
class PermissionService {
  PermissionService._();

  /// Asks for the microphone (+ camera for video calls). Never throws.
  static Future<CallPermissionResult> request({bool video = false}) async {
    final permissions = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];
    try {
      final statuses = await permissions.request();
      if (statuses.values.every((s) => s.isGranted)) {
        return CallPermissionResult.granted;
      }
      if (statuses.values.any((s) => s.isPermanentlyDenied)) {
        return CallPermissionResult.permanentlyDenied;
      }
      return CallPermissionResult.denied;
    } catch (_) {
      return CallPermissionResult.denied;
    }
  }

  /// True when the permissions needed for a call are already granted.
  static Future<bool> granted({bool video = false}) async {
    try {
      final mic = await Permission.microphone.status;
      if (!mic.isGranted) return false;
      if (video) {
        final cam = await Permission.camera.status;
        if (!cam.isGranted) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Requests the camera for taking a profile picture.
  ///
  /// Needed because the manifest declares CAMERA: when that permission is
  /// present, `image_picker` requires it to be granted before it will open
  /// the capture screen. Picking from the gallery needs no permission (it
  /// goes through the system photo picker).
  ///
  /// Returns true only when the camera may be opened.
  static Future<bool> ensureCamera(BuildContext context) async {
    try {
      if (await Permission.camera.status.then((s) => s.isGranted)) return true;
    } catch (_) {
      return false;
    }

    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (_) {
      return false;
    }
    if (status.isGranted) return true;
    if (!context.mounted) return false;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        status.isPermanentlyDenied
            ? 'Camera access is blocked. Enable it in Settings to take a photo.'
            : 'Camera access is needed to take a photo.',
      ),
      duration: const Duration(seconds: 4),
      action: status.isPermanentlyDenied
          ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
          : null,
    ));
    return false;
  }

  /// Requests the permissions and, when the user denies, shows a snackbar
  /// explaining how to re-enable them (with a shortcut to the settings).
  ///
  /// Returns true only when the call may proceed.
  static Future<bool> ensureForCall(
    BuildContext context, {
    required bool video,
  }) async {
    if (await granted(video: video)) return true;
    final result = await request(video: video);
    if (result == CallPermissionResult.granted) return true;
    if (!context.mounted) return false;

    final permanently = result == CallPermissionResult.permanentlyDenied;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        permanently
            ? 'Camera & microphone access is blocked. Enable them in Settings to make calls.'
            : 'Camera & microphone access is needed to make calls.',
      ),
      duration: const Duration(seconds: 4),
      action: permanently
          ? SnackBarAction(label: 'Settings', onPressed: openAppSettings)
          : null,
    ));
    return false;
  }
}
