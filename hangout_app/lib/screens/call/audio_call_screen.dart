import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/call_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/call_action_button.dart';

class AudioCallScreen extends ConsumerStatefulWidget {
  const AudioCallScreen({
    super.key,
    required this.call,
    required this.isCaller,
  });

  final CallData call;
  final bool isCaller;

  @override
  ConsumerState<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends ConsumerState<AudioCallScreen> {
  final CallService _service = CallService();

  bool _joined = false;
  bool _ringing = true;
  bool _noiseSuppression = true;
  bool _speakerOn = true;
  String? _error;

  int _seconds = 0;
  Timer? _timer;
  StreamSubscription<DocumentSnapshot>? _statusSub;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _listenCallStatus();
    _start();
  }

  void _setupListeners() {
    _service.onRemoteJoined.listen((_) {
      if (!mounted) return;
      setState(() {
        _ringing = false;
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _seconds++);
        });
      });
    });
    _service.onRemoteLeft.listen((_) {
      if (!mounted) return;
      // The other person hung up — end the call on this side too, instead of
      // going back to "Ringing…" / waiting forever.
      _finishCall(markEnded: true);
    });
    _service.onError.listen((msg) {
      if (!mounted) return;
      setState(() => _error = msg);
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
        isVideo: false,
      );
      if (!mounted) return;
      setState(() => _joined = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to join call: $e');
    }
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _peerName =>
      widget.isCaller ? widget.call.calleeName : widget.call.callerName;

  String get _peerInitial =>
      _peerName.isNotEmpty ? _peerName[0].toUpperCase() : '?';

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
    _statusSub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.callGradient),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 14),
              // Free built-in noise-filter status pill.
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _noiseSuppression
                      ? Colors.white.withOpacity(.14)
                      : Colors.white.withOpacity(.07),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _noiseSuppression
                        ? AppColors.softAqua.withOpacity(.45)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.hearing_rounded,
                      size: 16,
                      color: _noiseSuppression
                          ? AppColors.softAqua
                          : Colors.white38,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _noiseSuppression
                          ? 'Noise filtering on'
                          : 'Noise filtering off',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _noiseSuppression
                            ? AppColors.softAqua
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Teal→aqua gradient avatar (report §6.4).
              Container(
                width: 116,
                height: 116,
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4018BFAC),
                      blurRadius: 34,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  _peerInitial,
                  style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _peerName,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 8),
              Text(
                _ringing ? 'Ringing…' : _elapsed,
                style: const TextStyle(color: Colors.white60, fontSize: 15.5),
              ),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CallActionButton(
                    icon: Icons.hearing,
                    active: _noiseSuppression,
                    label: 'Noise',
                    onPressed: () async {
                      setState(() => _noiseSuppression = !_noiseSuppression);
                      await _service.enableNoiseSuppression(_noiseSuppression);
                    },
                  ),
                  CallActionButton(
                    icon: _service.micOn ? Icons.mic : Icons.mic_off,
                    active: _service.micOn,
                    label: 'Mute',
                    onPressed: () async {
                      await _service.toggleMic();
                      setState(() {});
                    },
                  ),
                  CallActionButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_mute,
                    active: _speakerOn,
                    label: 'Speaker',
                    onPressed: () async {
                      setState(() => _speakerOn = !_speakerOn);
                      await _service.setSpeakerphone(_speakerOn);
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
