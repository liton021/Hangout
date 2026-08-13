import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/call_service.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    context.read<CallService>().leaveChannel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<CallService>(
        builder: (context, callService, child) {
          return Stack(
            children: [
              Center(
                child: callService.remoteUid != null
                    ? AgoraVideoView(
                        controller: VideoViewController(
                           rtcEngine: callService.engine!,
                           canvas: VideoCanvas(uid: callService.remoteUid!),
                        ),
                      )
                    : const Text(
                        'Waiting for remote user...',
                        style: TextStyle(color: Colors.white70, fontSize: 18),
                      ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: 120,
                  height: 160,
                  child: callService.isJoined
                      ? AgoraVideoView(
                          controller: VideoViewController.remote(
                             rtcEngine: callService.engine!,
                             canvas: VideoCanvas(uid: 0),
                          ),
                        )
                      : Container(
                          color: Colors.grey,
                          child: const Icon(Icons.person, size: 60, color: Colors.white),
                        ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 40),
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
                          callService.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                          color: Colors.white,
                        ),
                        onPressed: callService.toggleVideo,
                      ),
                      const SizedBox(width: 24),
                      IconButton(
                        iconSize: 48,
                        icon: const Icon(Icons.call_end, color: Colors.red),
                        onPressed: () {
                          callService.leaveChannel();
                          Navigator.pop(context);
                        },
                      ),
                    ],
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
