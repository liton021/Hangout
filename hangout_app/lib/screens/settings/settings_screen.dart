import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/avatar.dart';
import '../home/calls_screen.dart';
import 'avatar_picker.dart';

/// Settings tab — profile card on top, then grouped preference rows.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.showHeader = true});

  /// The tab version shows the "Messenger" header; when pushed as its own
  /// route the parent supplies an app bar instead.
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentAppUserProvider).value;
    final authUser = ref.watch(authStateProvider).value;
    final fallback = AppUser(
      uid: authUser?.uid ?? '',
      name: authUser?.displayName ?? 'Your profile',
      email: authUser?.email ?? '',
    );
    final user = profile ?? fallback;

    return Column(
      children: [
        if (showHeader)
          AppHeader(
            title: 'Messenger',
            leading: UserAvatar(user: user, radius: 18),
            actions: [
              HeaderIconButton(
                icon: Icons.search_rounded,
                tooltip: 'Search settings',
                onPressed: () => _comingSoon(context, 'Settings search'),
              ),
            ],
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _ProfileCard(user: user, parentRef: ref),
              const SizedBox(height: 22),
              GroupCard(
                dividerIndent: 74,
                children: [
                  SettingsRow(
                    icon: Icons.person_rounded,
                    title: 'Account',
                    subtitle: 'Privacy, security, change number',
                    onTap: () => _showAccountSheet(context, ref, user),
                  ),
                  SettingsRow(
                    icon: Icons.lock_rounded,
                    title: 'Privacy',
                    subtitle: 'Block contacts, disappearing messages',
                    onTap: () => _comingSoon(context, 'Privacy controls'),
                  ),
                  SettingsRow(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                    subtitle: 'Message, group & call tones',
                    onTap: () => _comingSoon(context, 'Notification settings'),
                  ),
                  SettingsRow(
                    icon: Icons.donut_large_rounded,
                    title: 'Data & Storage',
                    subtitle: 'Network usage, auto-download',
                    onTap: () => _comingSoon(context, 'Data & storage'),
                  ),
                  SettingsRow(
                    icon: Icons.help_outline_rounded,
                    title: 'Help',
                    subtitle: 'Help center, contact us, privacy policy',
                    onTap: () => _showHelp(context),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              GroupCard(
                dividerIndent: 74,
                children: [
                  SettingsRow(
                    icon: Icons.call_rounded,
                    title: 'Call history',
                    subtitle: 'Your recent voice & video calls',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CallsScreen()),
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.palette_rounded,
                    title: 'Appearance',
                    subtitle: _themeLabel(ref.watch(themeModeProvider)),
                    onTap: () => _showAppearanceSheet(context, ref),
                  ),
                  SettingsRow(
                    icon: Icons.logout_rounded,
                    title: 'Sign out',
                    subtitle: 'Sign out of Hangout on this device',
                    danger: true,
                    onTap: () => _confirmSignOut(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  'Hangout 1.0.0',
                  style: TextStyle(
                    color: context.colors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => 'Dark theme',
        ThemeMode.light => 'Light theme',
        ThemeMode.system => 'Match device setting',
      };

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon')),
    );
  }

  void _showAccountSheet(BuildContext context, WidgetRef ref, AppUser user) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: sheetContext.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _AccountLine(label: 'Name', value: user.name),
              _AccountLine(
                label: 'Email',
                value: user.email.isEmpty ? 'Not set' : user.email,
              ),
              _AccountLine(
                label: 'User ID',
                value: user.uid.isEmpty ? 'Unknown' : user.uid,
              ),
              if (user.createdAt != null)
                _AccountLine(
                  label: 'Joined',
                  value: '${user.createdAt!.toLocal()}'.split(' ').first,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Hangout',
      applicationVersion: '1.0.0',
      applicationLegalese:
          'Messaging and voice/video calling with AI noise suppression.',
      children: [
        const SizedBox(height: 12),
        Text(
          'Need a hand? Reach out from the Help center and we’ll get back to you.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ],
    );
  }

  void _showAppearanceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final current = ref.read(themeModeProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Appearance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: sheetContext.colors.textPrimary,
                    ),
                  ),
                ),
                for (final mode in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: mode,
                    groupValue: current,
                    onChanged: (choice) {
                      if (choice == null) return;
                      ref.read(themeModeProvider.notifier).setMode(choice);
                      Navigator.of(sheetContext).pop();
                    },
                    activeColor: AppColors.accent,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _themeLabel(mode),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: sheetContext.colors.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You’ll need to sign in again to use Hangout.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              ref.read(authServiceProvider).signOut();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// Big rounded profile card: ringed avatar, name, contact line, online chip.
///
/// Tapping the avatar opens the change-photo flow (camera / gallery /
/// remove) — see [AvatarPicker].
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.parentRef});

  final AppUser user;
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          _EditableAvatar(user: user, parentRef: parentRef),
          const SizedBox(height: 18),
          Text(
            user.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user.email.isEmpty ? 'Hangout user' : user.email,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16.5,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 9,
                  height: 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The profile photo with a camera badge — the entry point for changing it.
///
/// The whole circle is the tap target (plus a semantics label), so the badge
/// is a visual affordance rather than a small hit area.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({required this.user, required this.parentRef});

  final AppUser user;
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final hasPhoto = (user.avatarUrl ?? '').isNotEmpty;

    return Semantics(
      button: true,
      label: hasPhoto ? 'Change profile picture' : 'Add a profile picture',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The card behind this is a plain decorated Container, so without
          // its own transparent Material the ink ripple would be painted
          // underneath the card's surface colour and never be seen.
          // Not clipped: the green presence dot deliberately sits on the
          // ring's edge, and a circular clip would shave it off.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () =>
                  AvatarPicker.show(context, parentRef, hasPhoto: hasPhoto),
              customBorder: const CircleBorder(),
              child: UserAvatar(
                user: user,
                radius: 56,
                showPresence: true,
                ringColor: AppColors.accent,
                presenceBorderColor: palette.surface,
              ),
            ),
          ),
          Positioned(
            right: -2,
            top: 2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surface, width: 3),
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row: leading glyph, title, subtitle, chevron.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = danger ? AppColors.danger : AppColors.accent;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
        child: Row(
          children: [
            SizedBox(width: 36, child: Icon(icon, size: 26, color: tint)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: danger ? AppColors.danger : palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textSecondary,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
