import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentAppUserProvider).value;
    final mode = ref.watch(themeModeProvider);
    final authUser = ref.watch(authStateProvider).value;
    final fallbackName = authUser?.displayName ?? 'Your profile';

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      if (profile != null)
                        UserAvatar(user: profile, radius: 32, showPresence: true)
                      else
                        Container(
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                            gradient: AppColors.brandGradient,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            fallbackName.isEmpty
                                ? '?'
                                : fallbackName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(profile?.name ?? fallbackName,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 3),
                            Text(
                              profile?.email ?? authUser?.email ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white60
                                    : AppColors.sageGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.sageGray),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('APPEARANCE', style: _sectionStyle(context)),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      _ThemeChoice(
                        icon: Icons.brightness_auto_rounded,
                        title: 'Use device setting',
                        subtitle: 'Match your phone automatically',
                        value: ThemeMode.system,
                        groupValue: mode,
                        onChanged: (value) =>
                            ref.read(themeModeProvider.notifier).setMode(value),
                      ),
                      _divider(context),
                      _ThemeChoice(
                        icon: Icons.light_mode_rounded,
                        title: 'Light',
                        subtitle: 'Bright and clean',
                        value: ThemeMode.light,
                        groupValue: mode,
                        onChanged: (value) =>
                            ref.read(themeModeProvider.notifier).setMode(value),
                      ),
                      _divider(context),
                      _ThemeChoice(
                        icon: Icons.dark_mode_rounded,
                        title: 'Dark',
                        subtitle: 'Easy on your eyes',
                        value: ThemeMode.dark,
                        groupValue: mode,
                        onChanged: (value) =>
                            ref.read(themeModeProvider.notifier).setMode(value),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text('ACCOUNT', style: _sectionStyle(context)),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.logout_rounded,
                        color: Theme.of(context).colorScheme.error),
                  ),
                  title: const Text('Sign out',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Sign out of Hangout on this device'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => ref.read(authServiceProvider).signOut(),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Hangout 1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  TextStyle _sectionStyle(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      );

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 58),
        child: Divider(height: 1, color: Theme.of(context).dividerColor),
      );
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ThemeMode value;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon,
            size: 21,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: Radio<ThemeMode>(
        value: value,
        groupValue: groupValue,
        onChanged: (choice) {
          if (choice != null) onChanged(choice);
        },
      ),
      onTap: () => onChanged(value),
    );
  }
}
