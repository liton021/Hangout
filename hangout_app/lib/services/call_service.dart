import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps the Agora RTC engine for 1-to-1 audio/video calls.
class CallService extends ChangeNotifier {
  /// Agora App ID — replace with your own from https://console.agora.io.
  static const String appId = '8b387fb54fce41519043edc4e9aa0ce4';

  /// Agora token.
  ///
  /// This project keeps the Agora **App Certificate disabled**, so an empty
  /// token is accepted for testing. If you enable the App Certificate you
  /// MUST generate tokens on your own server (temporary tokens from the
  /// console expire within 24h) — never hardcode a token here.
  static const String token = '';

  /// Deterministic channel name for a call between [uid1] and [uid2].
  ///
  /// Sorting the ids means both peers always join the same channel no matter
  /// who initiates the call.
  static String channelNameFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return 'call_${ids[0]}_${ids[1]}';
  }

  RtcEngine? _engine;
  bool _isVideoCall = false;
  int? _remoteUid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isVideoEnabled = false;
  bool _isStarting = false;

  RtcEngine? get engine => _engine;
  int? get remoteUid => _remoteUid;
  bool get isJoined => _isJoined;
  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;

  /// Starts a new call: initializes the engine, requests permissions and
  /// joins [channelName]. Throws if anything goes wrong (permissions denied,
  /// network failure, invalid Agora credentials, ...).
  Future<void> startCall({
    required String channelName,
    required bool videoCall,
  }) async {
    if (_isStarting || _engine != null) return;

    _isStarting = true;
    try {
      await _initializeEngine(videoCall: videoCall);
      await _joinChannel(channelName);
    } catch (_) {
      // Never leave a half-initialized engine behind.
      await endCall();
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  /// Leaves the channel (if joined) and releases the engine.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> endCall() async {
    final engine = _engine;
    if (engine == null) return;

    // Clear state first so any widgets watching this service stop rendering
    // the released engine immediately, and so re-entrant calls no-op.
    _engine = null;
    _remoteUid = null;
    _isJoined = false;
    _isMuted = false;
    _isVideoEnabled = false;
    notifyListeners();

    await engine.leaveChannel();
    await engine.release();
  }

  Future<void> _initializeEngine({required bool videoCall}) async {
    _isVideoCall = videoCall;

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.enableAudio();
    if (videoCall) {
      await engine.enableVideo();
      await engine.startPreview();
    }

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          _isJoined = true;
          notifyListeners();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _remoteUid = remoteUid;
          notifyListeners();
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          _remoteUid = null;
          notifyListeners();
        },
      ),
    );

    _engine = engine;
    _remoteUid = null;
    _isJoined = false;
    _isMuted = false;
    _isVideoEnabled = videoCall;
    notifyListeners();
  }

  Future<void> _joinChannel(String channelName) async {
    final engine = _engine;
    if (engine == null) return;

    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      throw StateError('Microphone permission is required for calls.');
    }

    // The camera is only needed for video calls — an audio call must not
    // demand a permission it does not use.
    if (_isVideoCall) {
      final cameraPermission = await Permission.camera.request();
      if (!cameraPermission.isGranted) {
        throw StateError('Camera permission is required for video calls.');
      }
    }

    await engine.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: ChannelMediaOptions(
        autoSubscribeVideo: true,
        autoSubscribeAudio: true,
        publishCameraTrack: _isVideoCall,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> toggleMute() async {
    final engine = _engine;
    if (engine == null) return;

    _isMuted = !_isMuted;
    await engine.muteLocalAudioStream(_isMuted);
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    final engine = _engine;
    if (engine == null) return;

    if (_isVideoEnabled) {
      await engine.disableVideo();
    } else {
      await engine.enableVideo();
      await engine.startPreview();
    }
    _isVideoEnabled = !_isVideoEnabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }
}
