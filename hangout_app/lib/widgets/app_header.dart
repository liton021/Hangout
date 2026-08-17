import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The header used on every home tab: a small profile avatar on the left, the
/// screen title in Telegram's accent blue, and icon actions on the right.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.centerTitle = false,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centerTitle ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: context.colors.accentSoft,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: centerTitle
                  ? Center(child: titleText)
                  : Align(alignment: Alignment.centerLeft, child: titleText),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Bare icon action for [AppHeader].
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  /// Defaults to [HangoutPalette.textPrimary] of the active theme.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 26, color: color ?? context.colors.textPrimary),
      splashRadius: 24,
    );
  }
}

/// Solid blue circular action (the "+" on Contacts).
class CircleAccentButton extends StatelessWidget {
  const CircleAccentButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D3390EC),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    );
  }
}

/// Uppercase, letter-spaced label ("FREQUENT").
class OverlineLabel extends StatelessWidget {
  const OverlineLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.6,
      ),
    );
  }
}

/// Big section title with an optional trailing link ("Suggested for You" /
/// "See All").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel!,
              style: TextStyle(
                color: context.colors.accentSoft,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

/// Rounded charcoal group that holds rows separated by inset hairlines.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.dividerIndent = 74,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final double dividerIndent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: dividerIndent, right: 16),
          child: Divider(height: 1, color: context.colors.divider),
        ));
      }
      rows.add(children[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: Column(children: rows),
    );
  }
}
