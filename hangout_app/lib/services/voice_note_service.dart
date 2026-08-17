import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/app_config.dart';

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
  }

  /// Stops recording and returns the finished file.
  ///
  /// Returns null when the take was too short to be intentional (the file is
  /// cleaned up in that case).
  Future<VoiceRecording?> stop() async {
    if (!await _recorder.isRecording()) return null;

    final startedAt = _startedAt;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      throw VoiceNoteException('Recording failed: $e');
    } finally {
      _activePath = null;
      _startedAt = null;
    }

    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);

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

    final uri = Uri.parse(AppConfig.voiceServerUrl).replace(path: '/voice');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
      request.headers.set(HttpHeaders.contentLengthHeader, bytes.length);

      // Chunked writes so the progress indicator moves on slow links.
      const chunkSize = 32 * 1024;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        final end = offset + chunkSize < bytes.length
            ? offset + chunkSize
            : bytes.length;
        request.add(bytes.sublist(offset, end));
        await request.flush();
        // Upload occupies the 5%–90% band.
        onProgress?.call(0.05 + 0.85 * (end / bytes.length));
      }

      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await response.transform(utf8.decoder).join();
      onProgress?.call(0.95);

      if (response.statusCode != 200) {
        throw VoiceNoteException(_errorFrom(body, response.statusCode));
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw const VoiceNoteException(
          'The server did not return an audio URL.',
        );
      }
      onProgress?.call(1);
      return url;
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
    } finally {
      client.close();
    }
  }

  /// Turns a Worker error body into something worth showing a user.
  String _errorFrom(String body, int status) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final message = data['error'] as String?;
      if (message != null && message.isNotEmpty) {
        if (status == 501) {
          return 'Voice messages are not set up on the server yet.';
        }
        return message;
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    if (status == 401) return 'Your session expired. Sign in again.';
    if (status == 413) return 'That recording is too large to send.';
    if (status == 429) return 'Too many voice messages — wait a moment.';
    return 'Upload failed (error $status).';
  }

  /// Releases the native recorder.
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }
}
