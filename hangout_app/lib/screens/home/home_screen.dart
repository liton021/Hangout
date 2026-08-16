import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/avatar.dart';
import '../../widgets/bottom_nav.dart';
import '../../widgets/search_field.dart';
import '../settings/settings_screen.dart';
import 'chats_tab.dart';
import 'contacts_tab.dart';
import 'discovery_tab.dart';

/// App shell: Chats · Contacts · Discovery · Settings behind the blue-pill
/// bottom navigation from the design.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  bool _askedPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStateProvider).value;
      if (me != null) ref.read(callControllerProvider.notifier).init(me.uid);
      _requestCallPermissionsOnLaunch();
    });
  }

  /// Asks for camera + microphone once, on first launch, so the system
  /// permission prompt appears before the first call instead of mid-call.
  Future<void> _requestCallPermissionsOnLaunch() async {
    if (_askedPermissions) return;
    _askedPermissions = true;
    await PermissionService.ensureForCall(context, video: true);
  }

  void _goToTab(int index) => setState(() => _tab = index);

  void _showNewChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewChatSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            ChatsTab(
              onProfileTap: () => _goToTab(3),
              onNewChat: _showNewChatSheet,
            ),
            ContactsTab(
              onProfileTap: () => _goToTab(3),
              onNewChat: _showNewChatSheet,
            ),
            DiscoveryTab(onProfileTap: () => _goToTab(3)),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: HangoutNavBar(
        currentIndex: _tab,
        onSelected: _goToTab,
      ),
    );
  }
}

/// Bottom sheet listing everyone you can start a conversation with.
class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 12),
              child: Text(
                'New chat',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SearchField(
                controller: _search,
                hint: 'Search people',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: users.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'Couldn’t load people: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                data: (list) {
                  final query = _search.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? list
                      : list
                          .where((u) =>
                              u.name.toLowerCase().contains(query) ||
                              u.email.toLowerCase().contains(query))
                          .toList();

                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(24, 16, 24, 40),
                      child: Text(
                        'No one to show yet — invite a friend to Hangout and '
                        'they’ll appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final user = filtered[i];
                      return _NewChatRow(user: user);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChatRow extends ConsumerWidget {
  const _NewChatRow({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: UserAvatar(user: user, radius: 24),
      title: Text(
        user.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        user.email.isEmpty ? 'On Hangout' : user.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.textSecondary),
      onTap: () {
        Navigator.of(context).pop();
        ContactActions.openChat(context, ref, user);
      },
    );
  }
}
