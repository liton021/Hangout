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
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFE84D5B)
                : (active
                    ? Colors.white.withOpacity(.18)
                    : Colors.black.withOpacity(.25)),
            shape: BoxShape.circle,
            border: Border.all(
              color: danger ? Colors.transparent : Colors.white.withOpacity(.10),
            ),
            boxShadow: danger
                ? const [
                    BoxShadow(
                      color: Color(0x55E84D5B),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: 58,
                height: 58,
                child: Icon(
                  icon,
                  color: danger
                      ? Colors.white
                      : (active ? Colors.white : Colors.white54),
                  size: 25,
                ),
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
