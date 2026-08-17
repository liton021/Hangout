import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/call_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/call_action_button.dart';
import '../../widgets/quality_indicator.dart';

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

  String? _error;

  int _seconds = 0;
  Timer? _timer;
  StreamSubscription<DocumentSnapshot>? _statusSub;
  StreamSubscription<int>? _networkSub;
  bool _ending = false;

  // Quality tracking for display.
  int _networkQuality = 0;

  // ── Auto-hiding overlay ──────────────────────────────────────────────────
  // Like every other calling app: the video owns the screen, and the name /
  // timer / quality / controls only appear when the user taps, then fade out
  // again. While the call is still ringing the overlay stays pinned up, since
  // there is nothing to look at yet and hiding the End button would strand
  // the caller.
  static const Duration _overlayTimeout = Duration(seconds: 3);

  bool _overlayVisible = true;
  Timer? _overlayTimer;

  /// The overlay is forced on until the other side's video is actually up.
  bool get _overlayPinned => _ringing || _remoteUid == null;

  bool get _showOverlay => _overlayPinned || _overlayVisible;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _listenCallStatus();
    _start();
  }

  /// Shows the overlay and restarts the 3-second countdown to hide it.
  void _revealOverlay() {
    _overlayTimer?.cancel();
    if (!_overlayVisible) setState(() => _overlayVisible = true);
    _overlayTimer = Timer(_overlayTimeout, () {
      if (!mounted) return;
      setState(() => _overlayVisible = false);
    });
  }

  /// Tap anywhere on the video: reveal if hidden, dismiss early if shown.
  void _toggleOverlay() {
    if (_overlayPinned) return;
    if (_overlayVisible) {
      _overlayTimer?.cancel();
      setState(() => _overlayVisible = false);
    } else {
      _revealOverlay();
    }
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
      // The call just went live: show the chrome once so the user sees who
      // they are talking to, then let it fade on the usual timer.
      _revealOverlay();
    });
    _service.onRemoteLeft.listen((uid) {
      if (!mounted) return;
      // The other person hung up — end this side too, instead of leaving the
      // callee staring at "Waiting for the other person…".
      _finishCall(markEnded: true);
    });
    _service.onError.listen((msg) {
      if (!mounted) return;
      setState(() => _error = msg);
    });
    // Listen for network quality changes for the indicator.
    _networkSub = _service.onNetworkQualityChanged.listen((quality) {
      if (!mounted) return;
      setState(() => _networkQuality = quality);
    });
  }

  /// Watches the Firestore call doc so the screen ends itself when the
  /// caller cancels, the callee rejects, or either side ends the call.
  void _listenCallStatus() {
    _statusSub = ref
        .read(firestoreProvider)
        .collection('calls')
        .doc(widget.call.id)
        .snapshots()
        .listen((doc) {
      if (!mounted || _ending) return;
      if (!doc.exists) {
        // Call record was removed — nothing left to wait for.
        _finishCall(markEnded: false);
        return;
      }
      final status = CallStatus.fromName(doc.data()?['status'] as String?);
      if (status != CallStatus.ringing && status != CallStatus.ongoing) {
        _finishCall(markEnded: false);
      }
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
    if (_ending) return;
    _ending = true;
    await ref.read(callControllerProvider.notifier).end(widget.call);
    await _service.leave();
    if (mounted) Navigator.of(context).pop();
  }

  /// Ends this side of the call (leaves the channel and closes the screen).
  ///
  /// [markEnded] additionally records `ended` in Firestore — used when the
  /// remote vanished from the channel without updating the doc (e.g. the app
  /// was killed), so the call history stays accurate.
  Future<void> _finishCall({bool markEnded = false}) async {
    if (_ending) return;
    _ending = true;
    _timer?.cancel();
    _timer = null;
    if (markEnded) {
      try {
        await ref
            .read(firestoreProvider)
            .collection('calls')
            .doc(widget.call.id)
            .set({'status': CallStatus.ended.name}, SetOptions(merge: true));
      } catch (_) {}
    }
    await _service.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _overlayTimer?.cancel();
    _statusSub?.cancel();
    _networkSub?.cancel();
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
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final visible = _showOverlay;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video fills the screen.
          Positioned.fill(child: _buildRemote()),

          // Dedicated transparent tap-catcher stacked ON TOP of the video.
          //
          // AgoraVideoView renders through an Android platform view, and
          // those consume touch events themselves — a GestureDetector
          // *wrapping* it would never fire. Sitting above it in the Stack
          // (but below the chrome) means taps on the picture toggle the
          // overlay, while taps on the buttons still hit the buttons.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleOverlay,
              child: const SizedBox.expand(),
            ),
          ),

          // Everything below is chrome: one AnimatedOpacity so the whole
          // overlay fades in/out together, and IgnorePointer so hidden
          // controls cannot be pressed by accident.
          IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: Stack(
                children: [
                  // Scrims: without them white text over a bright camera
                  // frame is unreadable.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: topInset + 140,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x99000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: bottomInset + 190,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0xA6000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Name + elapsed time.
                  Positioned(
                    top: topInset + 18,
                    left: 16,
                    // Keep clear of the PiP tile and the quality bar.
                    right: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _peerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _ringing ? 'Ringing…' : _elapsed,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                  // Slim, icons-only quality bar, tucked under the PiP tile.
                  if (_joined && !_ringing)
                    Positioned(
                      top: topInset + 14 + 160 + 10,
                      right: 14,
                      child: CallQualityIndicator(
                        compact: true,
                        networkQuality: _networkQuality,
                        videoQuality: _service.currentVideoQualityLabel,
                        audioQuality: _service.currentAudioQualityLabel,
                      ),
                    ),

                  if (_error != null)
                    Positioned(
                      bottom: bottomInset + 150,
                      left: 24,
                      right: 24,
                      child: Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ),

                  // Controls
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomInset + 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        CallActionButton(
                          icon: Icons.switch_camera,
                          label: 'Flip',
                          onPressed: () {
                            _revealOverlay();
                            _service.switchCamera();
                          },
                        ),
                        CallActionButton(
                          icon: _service.cameraOn
                              ? Icons.videocam
                              : Icons.videocam_off,
                          active: _service.cameraOn,
                          label: 'Camera',
                          onPressed: () async {
                            _revealOverlay();
                            await _service.toggleCamera();
                            if (mounted) setState(() {});
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
            ),
          ),

          // The picture-in-picture tile stays above the fading chrome so the
          // user can always see themselves, exactly like other calling apps.
          // It sits above the tap-catcher, so it needs its own tap handler or
          // that corner of the screen would feel dead.
          if (_localController != null)
            Positioned(
              top: topInset + 14,
              right: 14,
              child: GestureDetector(
                onTap: _toggleOverlay,
                child: _localTile(),
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