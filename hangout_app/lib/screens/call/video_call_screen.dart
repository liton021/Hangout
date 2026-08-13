import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/call_service.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key, required this.channelName});

  /// Agora channel for this call (see [CallService.channelNameFor]).
  final String channelName;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  // Captured here so `dispose()` never has to look up an inherited widget
  // (which is illegal while the element tree is being torn down).
  late final CallService _callService;

  // Controllers are cached per remote user so toggling the mute/video
  // buttons (which rebuilds this widget) does not tear down and re-create
  // the video renderers.
  VideoViewController? _localController;
  VideoViewController? _remoteController;
  int? _remoteControllerUid;

  @override
  void initState() {
    super.initState();
    _callService = context.read<CallService>();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      await _callService.startCall(
        channelName: widget.channelName,
        videoCall: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start the call: $e')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // Idempotent — also covers the back button and system navigation.
    _callService.endCall();
    super.dispose();
  }

  VideoViewController _localViewController(RtcEngine engine) {
    // A local view always renders the camera (uid 0) with the default
    // controller — VideoViewController.remote() would reject uid 0.
    return _localController ??= VideoViewController(
      rtcEngine: engine,
      canvas: const VideoCanvas(uid: 0),
    );
  }

  VideoViewController _remoteViewController(RtcEngine engine, int uid) {
    if (_remoteController == null || _remoteControllerUid != uid) {
      _remoteController = VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: widget.channelName),
      );
      _remoteControllerUid = uid;
    }
    return _remoteController!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<CallService>(
        builder: (context, callService, child) {
          final engine = callService.engine;
          final remoteUid = callService.remoteUid;

          return Stack(
            children: [
              // Remote video.
              Center(
                child: remoteUid != null && engine != null
                    ? AgoraVideoView(
                        controller: _remoteViewController(engine, remoteUid),
                      )
                    : Text(
                        callService.isJoined
                            ? 'Connected — waiting for video...'
                            : 'Waiting for the other person to join...',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                        ),
                      ),
              ),
              // Local preview (picture-in-picture).
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 120,
                      height: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: engine != null
                            ? AgoraVideoView(
                                controller: _localViewController(engine),
                              )
                            : Container(
                                color: Colors.grey.shade800,
                                child: const Icon(
                                  Icons.videocam,
                                  size: 48,
                                  color: Colors.white70,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              // Call controls.
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          iconSize: 48,
                          icon: Icon(
                            callService.isMuted ? Icons.mic_off : Icons.mic,
                            color: Colors.white,
                          ),
                          onPressed: callService.toggleMute,
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          iconSize: 48,
                          icon: Icon(
                            callService.isVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            color: Colors.white,
                          ),
                          onPressed: callService.toggleVideo,
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          iconSize: 48,
                          icon: const Icon(Icons.call_end, color: Colors.red),
                          onPressed: () {
                            callService.endCall();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
