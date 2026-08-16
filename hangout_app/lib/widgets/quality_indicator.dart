import 'package:flutter/material.dart';

/// A subtle, non-intrusive indicator that shows the current call quality.
///
/// Displayed as a small translucent pill near the top of the call screen.
/// It shows the network quality (via signal bars), the video resolution
/// (if video call), and the audio quality tier. The indicator auto-fades
/// when network is excellent and becomes more visible when the network
/// degrades.
///
/// Agora quality scale:
///   0 = unknown
///   1 = excellent
///   2 = good
///   3 = poor
///   4 = bad
///   5 = very bad
///   6 = down
class CallQualityIndicator extends StatelessWidget {
  const CallQualityIndicator({
    super.key,
    required this.networkQuality,
    this.videoQuality,
    required this.audioQuality,
  });

  /// Current network quality from Agora (0–6).
  final int networkQuality;

  /// Video quality label like "720p", "480p", or null for audio-only calls.
  final String? videoQuality;

  /// Audio quality tier: "High", "Normal", or "Low".
  final String audioQuality;

  bool get _isStable => networkQuality <= 2;
  bool get _isPoor => networkQuality >= 3;

  /// Icon and color for the network quality bar.
  /// Uses signal_wifi_* icons (all bar variants exist in Flutter 3.24).
  IconData get _networkIcon {
    switch (networkQuality) {
      case 0:
        return Icons.signal_wifi_off;
      case 1:
        return Icons.signal_wifi_4_bar;
      case 2:
        return Icons.signal_wifi_3_bar;
      case 3:
        return Icons.signal_wifi_2_bar;
      case 4:
        return Icons.signal_wifi_1_bar;
      case 5:
      case 6:
        return Icons.signal_wifi_0_bar;
      default:
        return Icons.signal_wifi_off;
    }
  }

  Color get _networkColor {
    if (networkQuality == 0) return Colors.white38;
    if (networkQuality <= 2) return const Color(0xFF22C55E); // green
    if (networkQuality <= 3) return const Color(0xFFEAB308); // amber
    return const Color(0xFFEF4444); // red
  }

  String get _networkLabel {
    switch (networkQuality) {
      case 0:
        return '?';
      case 1:
        return 'Excellent';
      case 2:
        return 'Good';
      case 3:
        return 'Fair';
      case 4:
        return 'Poor';
      case 5:
        return 'Very poor';
      case 6:
        return 'Disconnected';
      default:
        return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything until we have a real quality reading.
    if (networkQuality == 0) return const SizedBox.shrink();

    final opacity = _isPoor ? 0.85 : 0.65;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 400),
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _networkColor.withOpacity(0.5),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Network quality icon
            Icon(_networkIcon, size: 16, color: _networkColor),
            const SizedBox(width: 6),
            // Network label
            Text(
              _networkLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _networkColor,
              ),
            ),
            // Video quality (if available)
            if (videoQuality != null) ...[
              const SizedBox(width: 10),
              _dot(),
              const SizedBox(width: 6),
              Icon(Icons.videocam, size: 13, color: Colors.white70),
              const SizedBox(width: 3),
              Text(
                videoQuality!,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
            // Audio quality
            const SizedBox(width: 10),
            _dot(),
            const SizedBox(width: 6),
            Icon(Icons.mic, size: 13, color: Colors.white70),
            const SizedBox(width: 3),
            Text(
              audioQuality,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot() {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: Colors.white38,
        shape: BoxShape.circle,
      ),
    );
  }
}