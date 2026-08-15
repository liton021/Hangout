import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
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

  @override
  void initState() {
    super.initState();
    _setupListeners();
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
      setState(() {
        _ringing = true;
        _timer?.cancel();
        _timer = null;
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
    await ref.read(callControllerProvider.notifier).end(widget.call);
    await _service.leave();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              CircleAvatar(
                radius: 52,
                backgroundColor: Colors.white24,
                child: Text(
                  _peerInitial,
                  style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _peerName,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                _ringing ? 'Ringing…' : _elapsed,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                    label: 'Noise AI',
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
                    icon: _speakerOn
                        ? Icons.volume_up
                        : Icons.volume_mute,
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
