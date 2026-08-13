import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class CallService extends ChangeNotifier {
  static const String appId = '<YOUR_AGORA_APP_ID>';
  static const String tempToken = '<YOUR_AGORA_TEMP_TOKEN>';

  RtcEngine? _engine;
  int? _remoteUid;
  bool _isJoined = false;
  bool _isMuted = false;
  bool _isVideoEnabled = true;

  RtcEngine? get engine => _engine;
  bool get isJoined => _isJoined;
  bool get isMuted => _isMuted;
  bool get isVideoEnabled => _isVideoEnabled;

  Future<void> initializeEngine({required bool videoCall}) async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.enableAudio();
    if (videoCall) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          _isJoined = true;
          notifyListeners();
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _remoteUid = remoteUid;
          notifyListeners();
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          _remoteUid = null;
          notifyListeners();
        },
      ),
    );
  }

  Future<void> joinChannel(String channelName) async {
    await [Permission.microphone, Permission.camera].request();

    await _engine!.joinChannel(
      token: tempToken,
      channelId: channelName,
      options: const ChannelMediaOptions(
        autoSubscribeVideo: true,
        autoSubscribeAudio: true,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
      uid: 0,
    );
  }

  Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    _remoteUid = null;
    _isJoined = false;
    _isMuted = false;
    _isVideoEnabled = true;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    await _engine?.muteLocalAudioStream(!_isMuted);
    _isMuted = !_isMuted;
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    if (_isVideoEnabled) {
      await _engine?.disableVideo();
    } else {
      await _engine?.enableVideo();
      await _engine?.startPreview();
    }
    _isVideoEnabled = !_isVideoEnabled;
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }
}
