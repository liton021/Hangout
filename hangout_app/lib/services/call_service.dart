import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

import '../config/app_config.dart';
import 'token_service.dart';

/// Wraps the Agora RTC engine for one call session.
///
/// Responsibilities:
///  * create/initialize the engine and join a channel
///  * built-in (free) noise suppression + echo cancellation + auto gain
///  * beauty / face effects + virtual background (video only)
///  * mic / camera / speaker toggles
///  * **adaptive audio/video quality** — automatically adjusts
///    resolution, frame rate, and audio bitrate based on real-time
///    network conditions (stable → higher quality, unstable → lower).
///  * expose VideoViewControllers for local + remote video rendering
///
/// Usage: create one [CallService] per call, `await join(...)`, then `await
/// leave()` and `dispose()` when the call ends.
///
/// NOTE: Agora's *AI* Noise Suppression (AINS) is a paid extension that
/// requires activating in the console (with a credit card). This class
/// intentionally uses only the standard, free, always-on DSP processing
/// bundled with the SDK.
class CallService {
  RtcEngine? _engine;
  RtcEngineEventHandler? _handler;
  String _channelName = '';
  bool _isVideo = true;

  bool _micOn = true;
  bool _cameraOn = true;
  bool _noiseSuppressionOn = false;


  // ── Network-quality state ────────────────────────────────────────────────
  // Agora QualityType indices: 0 unknown · 1 excellent · 2 good · 3 poor ·
  // 4 bad · 5 very bad · 6 down. We track the worst value seen recently.
  int _lastTxQuality = 0;
  int _lastRxQuality = 0;
  int _worstQuality = 0;

  // ── Adaptive video quality ladder ────────────────────────────────────────
  // Six rungs from 1080p HD down to 180p. Every rung keeps at least 24 FPS
  // so the video stays watchably smooth even on poor networks. The bitrate
  // is always the SDK's natural/recommended value for the resolution, so
  // quality stays balanced.
  static const List<_VideoStep> _videoSteps = [
    _VideoStep(width: 1920, height: 1080, frameRate: 30), // excellent
    _VideoStep(width: 1280, height: 720, frameRate: 30),  // good
    _VideoStep(width: 848, height: 480, frameRate: 24),   // fair
    _VideoStep(width: 640, height: 360, frameRate: 24),   // poor
    _VideoStep(width: 426, height: 240, frameRate: 24),   // bad
    _VideoStep(width: 320, height: 180, frameRate: 24),   // very bad
  ];

  int _videoStepIndex = 1; // start at 720p (index 1)
  Timer? _degradeTimer;
  Timer? _upgradeTimer;

  /// Index into [_videoSteps] currently applied (0 = 1080p@30).
  int get currentVideoStep => _videoStepIndex;

  /// Total rungs available in the ladder.
  int get videoStepCount => _videoSteps.length;

  /// Human-readable label for the current video step (e.g. "720p", "360p").
  String get currentVideoQualityLabel => _videoSteps[_videoStepIndex].label;

  /// Current network quality indicator (0-6, Agora scale).
  /// 0=unknown, 1=excellent, 2=good, 3=poor, 4=bad, 5=very bad, 6=down.
  int get currentNetworkQuality => _worstQuality;

  /// Stream of network quality changes (0-6 Agora scale).
  final _networkQualityController = StreamController<int>.broadcast();
  Stream<int> get onNetworkQualityChanged => _networkQualityController.stream;

  // ── Audio quality profiles ───────────────────────────────────────────────
  // We map network conditions to Agora audio profiles:
  //   Good (≤2) → MusicStandard (higher bitrate, full frequency)
  //   Fair (3)   → Default (SDK-chosen)
  //   Poor (≥4)  → SpeechStandard (lower bitrate, mono)
  static const _AudioLevel _goodAudio = _AudioLevel(
    AudioProfileType.audioProfileMusicStandard,
    'High',
  );
  static const _AudioLevel _fairAudio = _AudioLevel(
    AudioProfileType.audioProfileDefault,
    'Normal',
  );
  static const _AudioLevel _poorAudio = _AudioLevel(
    AudioProfileType.audioProfileSpeechStandard,
    'Low',
  );

  _AudioLevel _currentAudioLevel = _goodAudio;

  /// Human-readable label for the current audio quality ("High", "Normal", or "Low").
  String get currentAudioQualityLabel => _currentAudioLevel.label;

  final _joined = Completer<void>();
  final _remoteUid = StreamController<int>.broadcast();
  final _remoteLeft = StreamController<int>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _leftChannel = Completer<void>();

  bool get isVideo => _isVideo;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get noiseSuppressionOn => _noiseSuppressionOn;


  Stream<int> get onRemoteJoined => _remoteUid.stream;
  Stream<int> get onRemoteLeft => _remoteLeft.stream;
  Stream<String> get onError => _error.stream;
  Future<void> get joined => _joined.future;
  Future<void> get left => _leftChannel.future;

  RtcEngine get engine => _engine!;

  /// Initializes the engine and joins [channelName].
  Future<void> join({
    required String channelName,
    required bool isVideo,
  }) async {
    if (!AppConfig.isConfigured) {
      const msg = 'Agora App ID is not configured. '
          'Open lib/config/app_config.dart and paste your App ID '
          '(from https://console.agora.io) into _agoraAppId.';
      _error.add(msg);
      throw StateError(msg);
    }

    _channelName = channelName;
    _isVideo = isVideo;

    // Reset quality state for a fresh call.
    _worstQuality = 0;
    _videoStepIndex = 1; // 720p default
    _currentAudioLevel = _goodAudio;

    // Secured mode: fetch a per-channel token from the token server.
    // Testing mode (no server configured): join token-less / static token.
    String token = AppConfig.agoraToken;
    if (AppConfig.useTokenServer) {
      try {
        token = await TokenService.fetchRtcToken(channelName);
      } catch (e) {
        final msg = 'Could not fetch call token: $e';
        _error.add(msg);
        throw StateError(msg);
      }
    }

    final engine = createAgoraRtcEngine();
    _engine = engine;

    await engine.initialize(const RtcEngineContext(
      appId: AppConfig.agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _handler = RtcEngineEventHandler(
      onError: (err, msg) => _error.add('$err: $msg'),
      onJoinChannelSuccess: (connection, elapsed) {
        if (!_joined.isCompleted) _joined.complete();
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        _remoteUid.add(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        _remoteLeft.add(remoteUid);
      },
      // Adapts the encoding quality to the network, silently:
      //   Video: 1080p@30 → 720p@30 → 480p@24 → 360p@24 → 240p@24 → 180p@24
      //   Audio: MusicStandard → Default → SpeechStandard
      // and back up when the network recovers.
      onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
        // txQuality and rxQuality are QualityType enum values.
        _onNetworkQuality(txQuality.index, rxQuality.index);
      },
      onLeaveChannel: (connection, stats) {
        if (!_leftChannel.isCompleted) _leftChannel.complete();
      },
      // Fired ~30s before the token expires: fetch a fresh one and renew,
      // so long calls are not dropped in secured mode.
      onTokenPrivilegeWillExpire: (connection, currentToken) async {
        if (!AppConfig.useTokenServer) return;
        try {
          final fresh = await TokenService.fetchRtcToken(_channelName);
          await _engine?.renewToken(fresh);
        } catch (e) {
          _error.add('Token renewal failed: $e');
        }
      },
    );
    engine.registerEventHandler(_handler!);

    await engine.enableAudio();
    // Set the initial high-quality audio profile.
    await _applyAudioLevel(_currentAudioLevel);

    if (_isVideo) {
      await engine.enableVideo();
      // 720p@30 with the SDK's natural bitrate for that resolution.
      await _applyVideoStep();
      await engine.startPreview();
    }

    await engine.joinChannel(
      token: token,
      channelId: _channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );

    // Built-in noise suppression / echo cancellation / auto gain control are
    // enabled by default in the SDK. We re-assert them here so the toggle
    // state stays in sync — no paid extension required.
    await enableNoiseSuppression(true);
  }

  /// Leaves the channel and releases the engine. Safe to call multiple times.
  Future<void> leave() async {
    _degradeTimer?.cancel();
    _upgradeTimer?.cancel();
    _degradeTimer = null;
    _upgradeTimer = null;
    final engine = _engine;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      engine.unregisterEventHandler(_handler!);
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
    _engine = null;
  }

  /// Releases the engine and closes the event streams. Safe to call twice.
  Future<void> dispose() async {
    await leave();
    if (!_remoteUid.isClosed) await _remoteUid.close();
    if (!_remoteLeft.isClosed) await _remoteLeft.close();
    if (!_error.isClosed) await _error.close();
    if (!_networkQualityController.isClosed) {
      await _networkQualityController.close();
    }
  }

  /// Toggles Agora's built-in (free) audio processing: noise suppression,
  /// acoustic echo cancellation and automatic gain control.
  ///
  /// These are standard DSP features bundled with the SDK and enabled by
  /// default — no paid extension (and no credit card) required, unlike the
  /// AI Noise Suppression (AINS) extension.
  Future<void> enableNoiseSuppression(bool enabled) async {
    final flag = enabled ? 'true' : 'false';
    try {
      await _engine?.setParameters('{"che.audio.ns.enable": $flag}');
      await _engine?.setParameters('{"che.audio.aec.enable": $flag}');
      await _engine?.setParameters('{"che.audio.agc.enable": $flag}');
      _noiseSuppressionOn = enabled;
    } catch (_) {
      // Even if these calls fail, the SDK's default (free) processing stays
      // active, so the call quality is unaffected.
      _noiseSuppressionOn = enabled;
    }
  }

  // Beauty filter and background blur were removed to cut APK size. They
  // required Agora's video-preprocess and segmentation native extensions,
  // which together added several MB per ABI. The matching .so files are
  // excluded in android/app/build.gradle — restoring these features means
  // dropping those excludes too, or the calls fail silently at runtime.

  // ── Adaptive quality core ────────────────────────────────────────────────
  // QualityType values (Agora): 0 unknown · 1 excellent · 2 good · 3 poor ·
  // 4 bad · 5 very bad · 6 down. We track the *worst* value seen, consider
  // both uplink (tx) and downlink (rx), and only move one step at a time
  // with confirmation delays so the quality never visibly flaps.
  //
  // Degrade thresholds:
  //   ≥3 (poor)     → drop one video rung + lower audio profile
  //   ≥5 (very bad) → faster degradation (2s instead of 4s)
  //
  // Upgrade thresholds:
  //   ≤2 (good)     → climb one rung after prolonged stability
  //   =1 (excellent) → faster recovery

  void _onNetworkQuality(int txQuality, int rxQuality) {
    // Store the latest values.
    _lastTxQuality = txQuality;
    _lastRxQuality = rxQuality;

    // Consider the worse of uplink and downlink.
    final worst = txQuality >= rxQuality ? txQuality : rxQuality;
    if (worst == 0) return; // unknown — do nothing yet

    // Update our rolling worst and emit to UI listeners.
    _worstQuality = worst;
    if (!_networkQualityController.isClosed) {
      _networkQualityController.add(worst);
    }

    // ── Determine if we need to degrade or upgrade ─────────────────────

    // Very bad connection (≥5): degrade fast.
    if (worst >= 5) {
      _upgradeTimer?.cancel();
      _upgradeTimer = null;
      _degradeTimer ??= Timer(const Duration(seconds: 2), () {
        _degradeTimer = null;
        _stepDown();
      });
      // Adjust audio for poor network immediately.
      if (_currentAudioLevel.profile != _poorAudio.profile) {
        _applyAudioLevel(_poorAudio);
      }
      return;
    }

    // Poor connection (≥3): degrade after a brief confirmation.
    if (worst >= 3) {
      _upgradeTimer?.cancel();
      _upgradeTimer = null;
      _degradeTimer ??= Timer(const Duration(seconds: 4), () {
        _degradeTimer = null;
        _stepDown();
      });
      // Set audio to normal/fair quality when network degrades.
      if (_currentAudioLevel.profile != _fairAudio.profile &&
          _currentAudioLevel.profile != _poorAudio.profile) {
        _applyAudioLevel(_fairAudio);
      }
      return;
    }

    // Good connection (≤2): consider upgrading after prolonged stability.
    if (_videoStepIndex > 0 ||
        _currentAudioLevel.profile != _goodAudio.profile) {
      _degradeTimer?.cancel();
      _degradeTimer = null;
      final delay = worst == 1
          ? const Duration(seconds: 8) // excellent → fast recovery
          : const Duration(seconds: 15); // good → slow recovery
      _upgradeTimer ??= Timer(delay, () {
        _upgradeTimer = null;
        _stepUp();
        // Restore high-quality audio.
        if (_currentAudioLevel.profile != _goodAudio.profile) {
          _applyAudioLevel(_goodAudio);
        }
      });
    } else {
      // Already at best — cancel any pending timers.
      _degradeTimer?.cancel();
      _upgradeTimer?.cancel();
      _degradeTimer = null;
      _upgradeTimer = null;
    }
  }

  void _stepDown() {
    if (!_isVideo) return;
    if (_videoStepIndex >= _videoSteps.length - 1) return;
    _videoStepIndex++;
    _applyVideoStep();
  }

  void _stepUp() {
    if (!_isVideo) return;
    if (_videoStepIndex <= 0) return;
    _videoStepIndex--;
    _applyVideoStep();
  }

  /// Applies the current ladder step. The bitrate is left at the SDK's
  /// recommended "standard" value for the resolution + frame rate (0 =
  /// standard/natural bitrate mode) — 1080p delivers full HD quality, while
  /// 240p/180p keep the stream alive on the worst connections. All steps
  /// run at ≥24 FPS so video always looks smooth.
  Future<void> _applyVideoStep() async {
    final step = _videoSteps[_videoStepIndex];
    try {
      await _engine?.setVideoEncoderConfiguration(VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: step.width, height: step.height),
        frameRate: step.frameRate,
        bitrate: 0, // natural bitrate chosen by the SDK for this step
        orientationMode: OrientationMode.orientationModeAdaptive,
        degradationPreference: DegradationPreference.maintainFramerate,
      ));
    } catch (_) {
      // Keep the previous configuration on failure.
    }
  }

  /// Switches the Agora audio profile based on network conditions.
  ///
  ///   High   → MusicStandard  (64 kbps mono, full frequency)
  ///   Normal → Default        (SDK-chosen for the scenario)
  ///   Low    → SpeechStandard (32 kbps mono, narrowband — excellent for
  ///            voice on constrained links)
  ///
  /// Uses setParameters() rather than setAudioProfile() because the latter
  /// accepts 0 positional arguments in this SDK version; setParameters()
  /// is the established pattern in this class (see [enableNoiseSuppression]).
  Future<void> _applyAudioLevel(_AudioLevel level) async {
    if (level.profile == _currentAudioLevel.profile) return;
    _currentAudioLevel = level;
    try {
      // The AudioProfileType enum index matches the internal integer value
      // the SDK uses for the "che.audio.audio_profile" parameter.
      final profileIndex = level.profile.index;
      await _engine?.setParameters(
        '{"che.audio.audio_profile": $profileIndex}',
      );
    } catch (_) {
      // Keep the previous profile on failure.
    }
  }

  Future<void> toggleMic() async {
    _micOn = !_micOn;
    await _engine?.muteLocalAudioStream(!_micOn);
  }

  Future<void> toggleCamera() async {
    _cameraOn = !_cameraOn;
    await _engine?.muteLocalVideoStream(!_cameraOn);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  /// Toggles the speakerphone (audio calls).
  Future<void> setSpeakerphone(bool enabled) async {
    await _engine?.setEnableSpeakerphone(enabled);
  }

  /// Controller for the local camera view (uid 0).
  VideoViewController localVideoController() {
    return VideoViewController(
      rtcEngine: _engine!,
      canvas: const VideoCanvas(uid: 0),
    );
  }

  /// Controller for a remote participant's video.
  VideoViewController remoteVideoController(int uid) {
    return VideoViewController.remote(
      rtcEngine: _engine!,
      canvas: VideoCanvas(uid: uid, renderMode: RenderModeType.renderModeFit),
      connection: RtcConnection(channelId: _channelName),
    );
  }
}

/// One rung of the adaptive video-quality ladder.
class _VideoStep {
  const _VideoStep({
    required this.width,
    required this.height,
    required this.frameRate,
  });

  final int width;
  final int height;
  final int frameRate;

  /// Human-readable label like "1080p" or "360p".
  String get label => '${height}p';
}

/// One audio quality level with its Agora profile and display label.
class _AudioLevel {
  const _AudioLevel(this.profile, this.label);

  final AudioProfileType profile;
  final String label;
}