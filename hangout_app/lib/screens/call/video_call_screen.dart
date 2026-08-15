import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
import '../../services/call_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/call_action_button.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.call,
    required this.isCaller,
  });

  final CallData call;
  final bool isCaller;

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  final CallService _service = CallService();
  VideoViewController? _localController;
  final Map<int, VideoViewController> _remoteControllers = {};

  int? _remoteUid;
  bool _joined = false;
  bool _ringing = true;
  bool _beauty = false;
  bool _backgroundBlur = false;
  String? _error;

  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _start();
  }

  void _setupListeners() {
    _service.onRemoteJoined.listen((uid) {
      if (!mounted) return;
      setState(() {
        _remoteControllers[uid] = _service.remoteVideoController(uid);
        _remoteUid = uid;
        _ringing = false;
        _startTimer();
      });
    });
    _service.onRemoteLeft.listen((uid) {
      if (!mounted) return;
      setState(() {
        _remoteControllers.remove(uid)?.dispose();
        _remoteUid = null;
        _ringing = true;
        _timer?.cancel();
      });
    });
    _service.onError.listen((msg) {
      if (!mounted) return;
      setState(() => _error = msg);
    });
  }

  Future<void> _start() async {
    try {
      await _service.join(
        channelName: widget.call.channelName,
        isVideo: true,
      );
      if (!mounted) return;
      setState(() {
        _joined = true;
        _localController = _service.localVideoController();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to join call: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _peerName =>
      widget.isCaller ? widget.call.calleeName : widget.call.callerName;

  Future<void> _endCall() async {
    await ref.read(callControllerProvider.notifier).end(widget.call);
    await _service.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _remoteControllers.values) {
      try {
        c.dispose();
      } catch (_) {}
    }
    try {
      _localController?.dispose();
    } catch (_) {}
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote (full screen)
          Positioned.fill(
            child: _buildRemote(),
          ),
          // Local (picture-in-picture)
          if (_localController != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 14,
              right: 14,
              child: _localTile(),
            ),
          // Status overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 18,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _peerName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2),
                ),
                const SizedBox(height: 4),
                Text(
                  _ringing ? 'Ringing…' : _elapsed,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
          if (_error != null)
            Positioned(
              bottom: 140,
              left: 0,
              right: 0,
              child: Center(
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          // Controls
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallActionButton(
                  icon: Icons.face_retouching_natural,
                  active: _beauty,
                  label: 'Beauty',
                  onPressed: () async {
                    setState(() => _beauty = !_beauty);
                    await _service.setBeauty(_beauty);
                  },
                ),
                CallActionButton(
                  icon: Icons.blur_on,
                  active: _backgroundBlur,
                  label: 'Blur',
                  onPressed: () async {
                    setState(() => _backgroundBlur = !_backgroundBlur);
                    await _service.setBackgroundBlur(_backgroundBlur);
                  },
                ),
                CallActionButton(
                  icon: Icons.switch_camera,
                  label: 'Flip',
                  onPressed: () => _service.switchCamera(),
                ),
                CallActionButton(
                  icon: _service.cameraOn
                      ? Icons.videocam
                      : Icons.videocam_off,
                  active: _service.cameraOn,
                  label: 'Camera',
                  onPressed: () async {
                    await _service.toggleCamera();
                    setState(() {});
                  },
                ),
                CallActionButton(
                  icon: Icons.call_end,
                  danger: true,
                  label: 'End',
                  onPressed: _endCall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemote() {
    final uid = _remoteUid;
    if (uid != null && _remoteControllers.containsKey(uid)) {
      return AgoraVideoView(controller: _remoteControllers[uid]!);
    }
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.35),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white70, strokeWidth: 2.4),
            ),
            SizedBox(width: 12),
            Text('Waiting for the other person…',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _localTile() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.35), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 110,
          height: 160,
          child: AgoraVideoView(controller: _localController!),
        ),
      ),
    );
  }
}
