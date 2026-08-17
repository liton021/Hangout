import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/app_config.dart';
import 'upload_client.dart';

/// Longest voice note we allow. Matches `VOICE_MAX_SECONDS` in the Worker.
const int kVoiceMaxSeconds = 120;

/// Recording stops itself this long before the hard cap so the upload never
/// races the limit.
const Duration kVoiceMaxDuration = Duration(seconds: kVoiceMaxSeconds);

/// Anything shorter than this was almost certainly an accidental tap.
const Duration kVoiceMinDuration = Duration(milliseconds: 800);

/// Hard ceiling enforced by the Worker (`VOICE_MAX_BYTES`).
const int kVoiceMaxBytes = 1024 * 1024;

/// Mono AAC at 32 kbps ≈ 4 KB/s — a 60-second note lands near 240 KB, which
/// keeps the card-free 1 GB KV tier viable. Speech at this bitrate is clear;
/// music would not be, but that is not what a voice note is for.
const int kVoiceBitRate = 32000;
const int kVoiceSampleRate = 44100;

/// Thrown when recording or upload fails; [message] is safe to show.
class VoiceNoteException implements Exception {
  const VoiceNoteException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A finished recording waiting to be sent.
class VoiceRecording {
  const VoiceRecording({
    required this.file,
    required this.duration,
  });

  final File file;
  final Duration duration;

  int get seconds => duration.inSeconds;

  /// Deletes the temp file. Safe to call more than once.
  Future<void> discard() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover file in the cache directory is harmless.
    }
  }
}

/// Records voice notes and uploads them to the Cloudflare Worker.
///
/// The Worker stores the audio (Workers KV by default, R2 when a bucket is
/// bound) and returns a public URL that expires after 30 days.
class VoiceNoteService {
  VoiceNoteService({required Future<String?> Function() idTokenProvider})
      : _idToken = idTokenProvider;

  final Future<String?> Function() _idToken;
  final AudioRecorder _recorder = AudioRecorder();

  String? _activePath;
  DateTime? _startedAt;

  /// Seconds of actual recording accumulated across pause/resume cycles —
  /// paused time never counts towards the note's duration.
  Duration _accumulated = Duration.zero;

  /// True while a recording session is open.
  Future<bool> get isRecording => _recorder.isRecording();

  /// Live microphone level, for the animated waveform.
  Stream<Amplitude> amplitudeStream() =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 120));

  /// Asks for the microphone permission, prompting if it hasn't been granted.
  Future<bool> ensurePermission() => _recorder.hasPermission();

  /// Begins recording into a temp file.
  ///
  /// Throws [VoiceNoteException] when the microphone is unavailable — the
  /// caller should surface that rather than silently doing nothing.
  Future<void> start() async {
    if (await _recorder.isRecording()) return;

    if (!await _recorder.hasPermission()) {
      throw const VoiceNoteException(
        'Microphone access is needed to record a voice message.',
      );
    }

    // AAC-LC in an MP4 container: supported on every Android the app targets
    // (minSdk 24). Opus would be smaller but needs SDK 29+.
    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: kVoiceBitRate,
      sampleRate: kVoiceSampleRate,
      numChannels: 1,
      // The device's own DSP does the cleanup for free.
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    );

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    try {
      await _recorder.start(config, path: path);
    } catch (e) {
      throw VoiceNoteException('Could not start recording: $e');
    }

    _activePath = path;
    _startedAt = DateTime.now();
    _accumulated = Duration.zero;
  }

  /// Pauses the current recording. The note's duration keeps accumulating
  /// only while actually recording — paused time is never counted.
  Future<void> pause() async {
    if (_startedAt == null) return; // not recording, or already paused
    try {
      await _recorder.pause();
    } catch (_) {
      // Some devices reject pause mid-take; treat it as a no-op rather than
      // losing the recording.
    }
    _accumulated += DateTime.now().difference(_startedAt!);
    _startedAt = null;
  }

  /// Resumes a paused recording.
  Future<void> resume() async {
    if (_startedAt != null) return; // already recording
    try {
      await _recorder.resume();
    } catch (_) {
      // Best effort — the take stays paused if the device refuses.
    }
    _startedAt = DateTime.now();
  }

  /// Stops recording and returns the finished file.
  ///
  /// Returns null when the take was too short to be intentional (the file is
  /// cleaned up in that case).
  Future<VoiceRecording?> stop() async {
    if (!await _recorder.isRecording()) return null;

    // Fold the final (possibly mid-recording) segment in before stopping,
    // then clear state.
    if (_startedAt != null) {
      _accumulated += DateTime.now().difference(_startedAt!);
      _startedAt = null;
    }
    final duration = _accumulated;

    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      throw VoiceNoteException('Recording failed: $e');
    } finally {
      _activePath = null;
      _accumulated = Duration.zero;
    }

    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    if (duration < kVoiceMinDuration) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }

    final size = await file.length();
    if (size > kVoiceMaxBytes) {
      try {
        await file.delete();
      } catch (_) {}
      throw const VoiceNoteException(
        'That recording is too long to send. Try a shorter one.',
      );
    }

    return VoiceRecording(file: file, duration: duration);
  }

  /// Aborts the current recording and deletes the partial file.
  Future<void> cancel() async {
    try {
      if (await _recorder.isRecording()) await _recorder.cancel();
    } catch (_) {
      // Cancelling is best-effort.
    }
    final path = _activePath;
    _activePath = null;
    _startedAt = null;
    _accumulated = Duration.zero;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Uploads [recording] and returns its public URL.
  ///
  /// [onProgress] reports 0.0 → 1.0 so the composer can show a determinate
  /// indicator.
  Future<String> upload(
    VoiceRecording recording, {
    void Function(double progress)? onProgress,
  }) async {
    if (!AppConfig.useVoiceServer) {
      throw const VoiceNoteException(
        'Voice messages are not configured for this build.',
      );
    }

    onProgress?.call(0);

    final Uint8List bytes = await recording.file.readAsBytes();
    if (bytes.isEmpty) {
      throw const VoiceNoteException('The recording was empty.');
    }
    if (bytes.length > kVoiceMaxBytes) {
      throw const VoiceNoteException(
        'That recording is too large to send. Try a shorter one.',
      );
    }

    onProgress?.call(0.05);

    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const VoiceNoteException('You need to be signed in to do that.');
    }

    try {
      final response = await postBytes(
        uri: _endpoint(),
        bytes: bytes,
        // The recorder writes AAC-LC in an MP4 container (.m4a); the Worker
        // sniffs the magic bytes and only accepts a matching declared type.
        contentType: 'audio/mp4',
        bearerToken: token,
        onProgress: onProgress,
        // Upload occupies the 5%–90% band.
        progressStart: 0.05,
        progressEnd: 0.90,
      );
      onProgress?.call(0.95);

      if (!response.ok) {
        throw VoiceNoteException(
          _errorFrom(response.body, response.statusCode),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const VoiceNoteException(
          'The server did not return an audio URL.',
        );
      }
      onProgress?.call(1);
      return url;
    } on VoiceNoteException {
      rethrow;
    } on SocketException {
      throw const VoiceNoteException(
        'No internet connection. Check your network and try again.',
      );
    } on HttpException {
      throw const VoiceNoteException(
        'Could not reach the server. Please try again.',
      );
    } on TimeoutException {
      throw const VoiceNoteException(
        'The upload timed out. Please try again.',
      );
    } on FormatException {
      throw const VoiceNoteException(
        'The server sent an unexpected response. Please try again.',
      );
    }
  }

  /// Builds the `/voice` endpoint URL, preserving any path on the base URL.
  Uri _endpoint() {
    final base = Uri.parse(AppConfig.voiceServerUrl);
    final prefix = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefix/voice', query: '');
  }

  /// Turns a Worker error body into something worth showing a user.
  ///
  /// A 401 here is almost never an expired session: the app only sends a
  /// freshly minted Firebase ID token, so a rejection means the *server*
  /// couldn't verify it (most commonly the deployed Worker is missing its
  /// `FIREBASE_PROJECT_ID` variable). The Worker tags that case with
  /// `errorCode: "server_missing_firebase_project_id"` so we can say so
  /// instead of leaking raw server text or scaring the user into
  /// signing out.
  String _errorFrom(String body, int status) {
    String? message;
    String? errorCode;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is String) message = decoded['error'] as String;
        if (decoded['errorCode'] is String) {
          errorCode = decoded['errorCode'] as String;
        }
      }
    } catch (_) {
      // Fall through to the generic message.
    }

    if (status == 501) {
      return 'Voice messages are not set up on the server yet.';
    }
    if (status == 413) return 'That recording is too large to send.';
    if (status == 429) return 'Too many voice messages — wait a moment.';
    if (status == 401) {
      if (errorCode == 'server_missing_firebase_project_id' ||
          (message ?? '').contains('FIREBASE_PROJECT_ID')) {
        return 'Voice messages are blocked by a missing server setting '
            '(the Hangout server has no Firebase project ID). '
            'Please try again later.';
      }
      return 'The voice server could not verify your login. Please try again.';
    }
    if (message != null && message.isNotEmpty) return message;
    return 'Upload failed (error $status).';
  }

  /// Releases the native recorder.
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
