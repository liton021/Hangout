import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Slim capsule bottom navigation: a rounded pill with **icons only** (no
/// labels). The active tab sits inside a fully-rounded accent disc with a
/// gentle icon bounce — modern messenger style.
class HangoutNavBar extends StatelessWidget {
  const HangoutNavBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const List<_NavSpec> items = [
    _NavSpec('Chats', Icons.chat_rounded, Icons.chat_bubble_outline_rounded),
    _NavSpec('Contacts', Icons.contact_page_rounded,
        Icons.contact_page_outlined),
    _NavSpec('Discovery', Icons.explore_rounded, Icons.explore_outlined),
    _NavSpec('Settings', Icons.settings_rounded, Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      // Slim capsule: modest side margins, tight vertical padding.
      margin: const EdgeInsets.fromLTRB(60, 0, 60, 12),
      decoration: BoxDecoration(
        color: palette.canvasElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.divider, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? .45 : .10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavItem(
                    spec: items[i],
                    selected: currentIndex == i,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavSpec {
  const _NavSpec(this.label, this.selectedIcon, this.icon);

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final foreground = selected ? Colors.white : palette.textSecondary;

    return Semantics(
      selected: selected,
      button: true,
      label: spec.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            // Fully rounded disc for the selection indicator.
            shape: BoxShape.circle,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x4D3390EC),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Icon(
                selected ? spec.selectedIcon : spec.icon,
                size: 24,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
