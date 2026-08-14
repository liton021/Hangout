import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/webrtc_service.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';

class CallScreen extends StatefulWidget {
  final String receiverId;
  final String callType;

  const CallScreen({
    super.key,
    required this.receiverId,
    this.callType = 'video',
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isLoading = true;
  String? _callId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeCall();
  }

  Future<void> _initializeCall() async {
    try {
      final authService = context.read<AuthService>();
      final callerId = authService.user?.uid;

      if (callerId == null) {
        setState(() => _error = 'User not authenticated');
        return;
      }

      final webrtcService = context.read<WebRTCService>();
      await webrtcService.initializeRenderers();
      await webrtcService.createLocalStream(widget.callType == 'video');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _startCall() async {
    try {
      final authService = context.read<AuthService>();
      final callerId = authService.user?.uid;

      if (callerId == null) return;

      final webrtcService = context.read<WebRTCService>();
      final firebaseService = context.read<FirebaseService>();

      String callId = DateTime.now().millisecondsSinceEpoch.toString();

      await webrtcService.createPeerConnection(callId);
      await webrtcService.addLocalStreamTracks();

      RTCSessionDescription offer = await webrtcService.createOffer();

      await firebaseService.createCallOffer(
        callerId: callerId,
        receiverId: widget.receiverId,
        callType: widget.callType,
        offerSdp: {
          'sdp': offer.sdp,
          'type': offer.type,
        },
      );

      setState(() => _callId = callId);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final webrtcService = context.watch<WebRTCService>();

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Stack(
                  children: [
                    if (widget.callType == 'video')
                      Positioned.fill(
                        child: RTCVideoView(webrtcService.remoteRenderer),
                      )
                    else
                      Positioned.fill(
                        child: Container(color: Colors.black),
                        child: const Center(
                          child: Icon(Icons.person, size: 120, color: Colors.white54),
                        ),
                      ),
                    if (widget.callType == 'video')
                      Positioned(
                        top: 40,
                        right: 16,
                        child: SizedBox(
                          width: 120,
                          height: 160,
                          child: RTCVideoView(webrtcService.localRenderer, mirror: true),
                        ),
                      ),
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CallControlButton(
                            icon: webrtcService.isMuted
                                ? Icons.mic_off
                                : Icons.mic,
                            color: webrtcService.isMuted
                                ? Colors.red
                                : Colors.white,
                            onPressed: webrtcService.toggleMute,
                          ),
                          const SizedBox(width: 24),
                          _CallControlButton(
                            icon: webrtcService.isVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            color: webrtcService.isVideoEnabled
                                ? Colors.white
                                : Colors.red,
                            onPressed: webrtcService.toggleVideo,
                          ),
                          const SizedBox(width: 24),
                          _CallControlButton(
                            icon: webrtcService.isSpeakerOn
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: webrtcService.isSpeakerOn
                                ? Colors.white
                                : Colors.orange,
                            onPressed: webrtcService.toggleSpeaker,
                          ),
                          const SizedBox(width: 24),
                          _CallControlButton(
                            icon: Icons.call_end,
                            color: Colors.red,
                            onPressed: () async {
                              await webrtcService.endCall();
                              if (mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 40,
                      left: 16,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () async {
                          await webrtcService.endCall();
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CallControlButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 28,
      backgroundColor: color.withOpacity(0.2),
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}
