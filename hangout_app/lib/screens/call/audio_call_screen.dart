import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/call_service.dart';

class AudioCallScreen extends StatefulWidget {
  const AudioCallScreen({super.key, required this.channelName});

  /// Agora channel for this call (see [CallService.channelNameFor]).
  final String channelName;

  @override
  State<AudioCallScreen> createState() => _AudioCallScreenState();
}

class _AudioCallScreenState extends State<AudioCallScreen> {
  // Captured here so `dispose()` never has to look up an inherited widget
  // (which is illegal while the element tree is being torn down).
  late final CallService _callService;

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
        videoCall: false,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: Consumer<CallService>(
          builder: (context, callService, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, size: 60, color: Colors.blue),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Audio Call',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  callService.isJoined ? 'Connected' : 'Connecting...',
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 64),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        callService.isMuted ? Icons.mic_off : Icons.mic,
                        color: Colors.white,
                      ),
                      onPressed: callService.toggleMute,
                    ),
                    const SizedBox(width: 48),
                    IconButton(
                      iconSize: 64,
                      icon: const Icon(Icons.call_end, color: Colors.red),
                      onPressed: () {
                        callService.endCall();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
