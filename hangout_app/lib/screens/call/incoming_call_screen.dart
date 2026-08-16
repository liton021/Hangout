import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';

/// Full-screen incoming-call UI shown when a ringing call is directed at us.
///
/// Also listens to the call doc so it dismisses itself if the caller
/// cancels while it is still ringing.
class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.call});

  final CallData call;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  StreamSubscription<DocumentSnapshot>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref
        .read(firestoreProvider)
        .collection('calls')
        .doc(widget.call.id)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final status = doc.data()?['status'] as String?;
      // If the caller cancelled/ended, close this screen automatically.
      if (status != null && status != CallStatus.ringing.name) {
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    // Ask for mic (+ camera for video) before joining, so the call doesn't
    // start silently without them (Android 13+ runtime prompt).
    final ok = await PermissionService.ensureForCall(
      context,
      video: widget.call.type == CallType.video,
    );
    if (!ok || !mounted) return;
    final accepted = await ref.read(callControllerProvider.notifier).accept();
    if (accepted == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => accepted.type == CallType.video
            ? VideoCallScreen(call: accepted, isCaller: false)
            : AudioCallScreen(call: accepted, isCaller: false),
      ),
    );
  }

  Future<void> _reject() async {
    await ref.read(callControllerProvider.notifier).reject();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.call.type == CallType.video;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // White avatar disc with the call glyph (report §4: call screen).
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(.35),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                widget.call.callerName,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3),
              ),
              const SizedBox(height: 8),
              Text(
                'Incoming ${isVideo ? 'video' : 'audio'} call…',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: AppColors.danger,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _reject,
                          child: const SizedBox(
                            width: 72,
                            height: 72,
                            child:
                                Icon(Icons.call_end, color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text('Decline',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Accept = white disc + teal icon (flat & colorful).
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _accept,
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: Icon(
                              isVideo ? Icons.videocam : Icons.call,
                              color: AppColors.accent,
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text('Accept',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
