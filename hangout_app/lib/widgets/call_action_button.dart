import 'package:flutter/material.dart';

/// A circular call-control button (mic, camera, end, effects…).
class CallActionButton extends StatelessWidget {
  const CallActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = true,
    this.danger = false,
    this.label,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: danger
              ? const Color(0xFFFF4757)
              : (active ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.07)),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 60,
              height: 60,
              child: Icon(
                icon,
                color: danger ? Colors.white : (active ? Colors.white : Colors.white54),
                size: 26,
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
