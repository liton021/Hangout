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
  bool _beautyOn = false;
  bool _backgroundBlurOn = false;

  // ── Adaptive video quality (silent, per design) ──────────────────────────
  // Starts at 720p@30. When the network degrades, drops one step at a time
  // to 480p@24 then 360p@24; when it recovers, climbs back up. The bitrate
  // is always the SDK's natural/recommended value for the resolution, so
  // the user is never notified and quality stays balanced.
  static const List<_VideoStep> _videoSteps = [
    _VideoStep(width: 1280, height: 720, frameRate: 30),
    _VideoStep(width: 848, height: 480, frameRate: 24),
    _VideoStep(width: 640, height: 360, frameRate: 24),
  ];

  int _videoStepIndex = 0;
  Timer? _degradeTimer;
  Timer? _upgradeTimer;

  /// Index into [_videoSteps] currently applied (0 = 720p@30).
  int get currentVideoStep => _videoStepIndex;

  final _joined = Completer<void>();
  final _remoteUid = StreamController<int>.broadcast();
  final _remoteLeft = StreamController<int>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _leftChannel = Completer<void>();

  bool get isVideo => _isVideo;
  bool get micOn => _micOn;
  bool get cameraOn => _cameraOn;
  bool get noiseSuppressionOn => _noiseSuppressionOn;
  bool get beautyOn => _beautyOn;
  bool get backgroundBlurOn => _backgroundBlurOn;

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
      // Adapts the encoding quality to the network, silently: 720p@30 →
      // 480p@24 → 360p@24, and back up when the network recovers.
      onNetworkQuality: (connection, remoteUid, txQuality, rxQuality) {
        if (!_isVideo || remoteUid == 0) return;
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

  Future<void> setBeauty(bool enabled) async {
    try {
      await _engine?.setBeautyEffectOptions(
        enabled: enabled,
        options: const BeautyOptions(
          lighteningContrastLevel: LighteningContrastLevel.lighteningContrastNormal,
          lighteningLevel: 0.5,
          smoothnessLevel: 0.6,
          rednessLevel: 0.1,
          sharpnessLevel: 0.3,
        ),
      );
      _beautyOn = enabled;
    } catch (_) {}
  }

  Future<void> setBackgroundBlur(bool enabled) async {
    try {
      await _engine?.enableVirtualBackground(
        enabled: enabled,
        backgroundSource: const VirtualBackgroundSource(
          backgroundSourceType: BackgroundSourceType.backgroundBlur,
          blurDegree: BackgroundBlurDegree.blurDegreeHigh,
        ),
        segproperty: const SegmentationProperty(
          modelType: SegModelType.segModelAi,
        ),
      );
      _backgroundBlurOn = enabled;
    } catch (_) {}
  }

  // ── Adaptive video quality ladder ────────────────────────────────────────
  // QualityType values (Agora): 0 unknown · 1 excellent · 2 good · 3 poor ·
  // 4 bad · 5 very bad · 6 down. We react to the worse of up/downlink and
  // only move one step at a time with delays, so it never visibly flaps.

  void _onNetworkQuality(int txQuality, int rxQuality) {
    final worst = txQuality >= rxQuality ? txQuality : rxQuality;
    if (worst == 0) return; // unknown — do nothing yet

    final poor = worst >= 3;
    if (poor) {
      // Network is struggling: drop one step after 4s of confirmation.
      _upgradeTimer?.cancel();
      _upgradeTimer = null;
      _degradeTimer ??= Timer(const Duration(seconds: 4), () {
        _degradeTimer = null;
        _stepDown();
      });
    } else if (_videoStepIndex > 0) {
      // Network recovered: climb back up after 12s of good quality.
      _degradeTimer?.cancel();
      _degradeTimer = null;
      _upgradeTimer ??= Timer(const Duration(seconds: 12), () {
        _upgradeTimer = null;
        _stepUp();
      });
    } else {
      _degradeTimer?.cancel();
      _upgradeTimer?.cancel();
      _degradeTimer = null;
      _upgradeTimer = null;
    }
  }

  void _stepDown() {
    if (_videoStepIndex >= _videoSteps.length - 1) return;
    _videoStepIndex++;
    _applyVideoStep();
  }

  void _stepUp() {
    if (_videoStepIndex <= 0) return;
    _videoStepIndex--;
    _applyVideoStep();
  }

  /// Applies the current ladder step. The bitrate is left at the SDK's
  /// recommended "standard" value for the resolution + frame rate (0 =
  /// standard/natural bitrate mode) — 720p@30 keeps full quality, while
  /// 480p/360p stay efficient on slow networks.
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
}
