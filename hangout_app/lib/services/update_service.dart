import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// A newer release found on GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
  });

  /// Release version, e.g. `1.0.1` (the `v` prefix is stripped).
  final String version;

  /// Release notes from the GitHub release body (may be empty).
  final String notes;

  /// Direct download URL of the universal APK asset.
  final String apkUrl;

  /// Asset file name, e.g. `Hangout-v1.0.1.apk`.
  final String apkName;

  /// Asset size in bytes (0 when unknown).
  final int apkSize;
}

/// Thrown when the user must grant "install unknown apps" first.
class UpdateNeedsInstallPermission implements Exception {}

/// In-app auto-update: checks GitHub Releases for a newer APK, downloads it
/// and hands it to the system installer.
///
/// No Cloudflare/FCM involved — GitHub's public releases API is the source
/// of truth, and the prompt is a plain in-app dialog shown when the user
/// opens the app.
class UpdateService {
  UpdateService._();

  static const MethodChannel _installer = MethodChannel('hangout/installer');

  static bool _checkedThisSession = false;

  /// Checks for an update once per app session and prompts if one exists.
  ///
  /// [navigatorContext] must be a context *below* the root Navigator (the
  /// HangoutApp's own context is above MaterialApp and cannot show dialogs).
  static Future<void> checkOnLaunch(BuildContext navigatorContext) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    await promptIfAvailable(navigatorContext);
  }

  /// Fetches the latest release and, when it is newer than the installed
  /// version, shows the update dialog. Silent (returns false) when the
  /// check fails or there is nothing new.
  static Future<bool> promptIfAvailable(BuildContext navigatorContext) async {
    final info = await fetchUpdateInfo();
    if (info == null) return false;
    if (!navigatorContext.mounted) return false;
    await showUpdateDialog(navigatorContext, info);
    return true;
  }

  /// Fetches the latest releases and returns the best candidate update.
  ///
  /// GitHub's `releases/latest` endpoint is unreliable here: this repo gets
  /// auto-generated releases with tags like `v-<commit-sha>` on every push
  /// (from the build pipeline), so "latest" is usually one of those junk
  /// releases. Instead we list the newest releases and pick the highest
  /// *strict* semver tag (`v1.2.3`) that is newer than the installed version
  /// AND carries an APK asset. Returns null when nothing qualifies or the
  /// check fails.
  static Future<UpdateInfo?> fetchUpdateInfo() async {
    if (!AppConfig.useAutoUpdate) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/${AppConfig.githubRepo}/releases'
        '?per_page=30',
      );
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      // GitHub requires a User-Agent on API calls.
      request.headers.set(HttpHeaders.userAgentHeader, 'Hangout-Android');
      final response = await request.close().timeout(const Duration(seconds: 15));

      // 404 = repo has no releases yet.
      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;

      final body = await response.transform(utf8.decoder).join();
      final releases = jsonDecode(body);
      if (releases is! List) return null;

      final current = _AppVersion.parse(AppConfig.appVersion);
      UpdateInfo? best;
      _AppVersion? bestVersion;

      for (final raw in releases) {
        if (raw is! Map<String, dynamic>) continue;

        // Skip drafts/prereleases and auto-generated v-<sha> tags (strict
        // semver only, e.g. "v1.2.3").
        if (raw['draft'] == true || raw['prerelease'] == true) continue;
        final tag = (raw['tag_name'] as String? ?? '').trim();
        final version = _AppVersion.parseStrict(tag);
        if (version == null || !version.isNewerThan(current)) continue;

        // The release must actually carry an APK.
        Map<String, dynamic>? asset;
        for (final a in (raw['assets'] as List? ?? const [])) {
          final m = a is Map<String, dynamic> ? a : null;
          if (m == null) continue;
          final name = (m['name'] as String? ?? '').toLowerCase();
          if (!name.endsWith('.apk')) continue;
          // Prefer the named "Hangout-*.apk" release artifact over generic
          // build outputs, but accept any APK as a fallback.
          if (asset == null || name.startsWith('hangout')) asset = m;
          if (name.startsWith('hangout')) break;
        }
        if (asset == null) continue;

        final url = asset['browser_download_url'] as String?;
        if (url == null || url.isEmpty) continue;

        if (bestVersion == null || version.isNewerThan(bestVersion)) {
          bestVersion = version;
          best = UpdateInfo(
            version: version.toString(),
            notes: (raw['body'] as String?)?.trim() ?? '',
            apkUrl: url,
            apkName: asset['name'] as String? ?? 'Hangout-update.apk',
            apkSize: (asset['size'] as num?)?.toInt() ?? 0,
          );
        }
      }
      return best;
    } catch (_) {
      // Offline / rate-limited / malformed — never crash the app over an
      // update check.
      return null;
    } finally {
      client.close();
    }
  }

  /// Downloads the APK into the app's own external files dir, reporting
  /// 0.0 → 1.0 progress. Reuses a previous complete download.
  static Future<File> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final apkDir = Directory('${base.path}/apks');
    await apkDir.create(recursive: true);

    final file = File('${apkDir.path}/${info.apkName}');
    if (await file.exists() &&
        info.apkSize > 0 &&
        await file.length() == info.apkSize) {
      return file; // already downloaded
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(info.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'Hangout-Android');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }

      final total = response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      onProgress?.call(1);
      return file;
    } finally {
      client.close();
    }
  }

  /// Hands the APK to the system installer.
  ///
  /// Throws [UpdateNeedsInstallPermission] when the user has not allowed
  /// "install unknown apps" for Hangout (the settings screen is opened).
  static Future<void> installApk(File file) async {
    final outcome = await _installer.invokeMethod<String>(
      'installApk',
      {'path': file.path},
    );
    if (outcome == 'needs_permission') {
      throw UpdateNeedsInstallPermission();
    }
    if (outcome != 'installed') {
      throw Exception('Installer returned: $outcome');
    }
  }

  /// True when "install unknown apps" is already allowed.
  static Future<bool> canRequestInstalls() async =>
      await _installer.invokeMethod<bool>('canRequestInstalls') ?? true;

  /// Opens the system screen that grants install-from-this-app permission.
  static Future<void> openInstallSettings() async {
    await _installer.invokeMethod<void>('openInstallSettings');
  }

  /// Shows the "new version available" dialog, then the download/install
  /// flow when the user opts in.
  static Future<void> showUpdateDialog(
    BuildContext navigatorContext,
    UpdateInfo info,
  ) async {
    final go = await showDialog<bool>(
      context: navigatorContext,
      builder: (context) => AlertDialog(
        title: const Text('Update available 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hangout ${info.version} is ready to install.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                info.notes,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, height: 1.35),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Downloading from GitHub and installing is automatic — '
              'your chats and data stay untouched.',
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update now'),
          ),
        ],
      ),
    );
    if (go != true || !navigatorContext.mounted) return;

    await _downloadAndInstall(navigatorContext, info);
  }

  static Future<void> _downloadAndInstall(
    BuildContext navigatorContext,
    UpdateInfo info,
  ) async {
    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(
        info: info,
        progress: progress,
        onCancel: () {
          dialogOpen = false;
          Navigator.of(navigatorContext).pop();
        },
      ),
    ).then((_) => dialogOpen = false);

    try {
      final file = await UpdateService.downloadApk(
        info,
        onProgress: (p) => progress.value = p,
      );
      if (!dialogOpen) return;
      progress.value = 1;

      // Small pause so the user sees 100% before the installer opens.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!dialogOpen) return;
      Navigator.of(navigatorContext).pop(); // close progress dialog

      await _installWithPermissionFlow(navigatorContext, file);
    } catch (_) {
      if (dialogOpen) {
        Navigator.of(navigatorContext).pop();
      }
      if (navigatorContext.mounted) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          const SnackBar(
            content: Text('Download failed. Check your connection and retry.'),
          ),
        );
      }
    }
  }

  static Future<void> _installWithPermissionFlow(
    BuildContext navigatorContext,
    File file,
  ) async {
    try {
      await UpdateService.installApk(file);
    } on UpdateNeedsInstallPermission {
      final openSettings = await showDialog<bool>(
        context: navigatorContext,
        builder: (context) => AlertDialog(
          title: const Text('Allow app installs'),
          content: const Text(
            'Android needs permission for Hangout to install updates. '
            'Turn on "Allow from this source" in the next screen, then '
            'tap the downloaded file to finish.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      if (openSettings == true) {
        await UpdateService.openInstallSettings();
      }
    } catch (_) {
      if (navigatorContext.mounted) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          const SnackBar(
            content: Text('Could not open the installer. Please try again.'),
          ),
        );
      }
    }
  }
}

/// Small semantic-version helper (major.minor.patch, optional +build).
class _AppVersion {
  const _AppVersion(this.parts);

  final List<int> parts;

  bool get isValid => parts.isNotEmpty;

  static _AppVersion parse(String raw) {
    final core = raw.split('+').first.trim();
    final parts = <int>[];
    for (final piece in core.split('.')) {
      final n = int.tryParse(piece);
      if (n == null) break;
      parts.add(n);
    }
    return _AppVersion(parts);
  }

  /// Strict release-tag parser: only `v1.2.3` / `1.2.3` (optionally with a
  /// `-suffix` or `+build`) qualify. Rejects junk tags like `v-<sha>`, which
  /// the auto-release pipeline creates for every push.
  static _AppVersion? parseStrict(String tag) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',
    ).firstMatch(tag.trim());
    if (match == null) return null;
    return _AppVersion([
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ]);
  }

  bool isNewerThan(_AppVersion other) {
    final len = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < len; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  @override
  String toString() => parts.join('.');
}

/// Determinate progress dialog shown while the APK downloads.
class _DownloadDialog extends StatelessWidget {
  const _DownloadDialog({
    required this.info,
    required this.progress,
    required this.onCancel,
  });

  final UpdateInfo info;
  final ValueNotifier<double> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Downloading Hangout ${info.version}…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value <= 0 ? null : value,
                  minHeight: 7,
                  backgroundColor: palette.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => Text(
                value <= 0
                    ? 'Starting…'
                    : '${(value * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 13,
                  color: palette.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }
}
