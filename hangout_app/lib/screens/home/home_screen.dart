import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/avatar.dart';
<<<<<<< ours
import '../../widgets/bottom_nav.dart';
import '../../widgets/search_field.dart';
=======
import '../../widgets/gradient_button.dart';
import '../../widgets/search_pill.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../chat/chat_screen.dart';
>>>>>>> theirs
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
<<<<<<< ours
                  final query = _search.text.trim().toLowerCase();
=======
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                      child: Text(
                        'No Hangout friends yet — share the app and they’ll show up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: dark ? Colors.white60 : AppColors.sageGray,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final user = list[i];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: UserAvatar(
                            user: user, radius: 22, showPresence: true),
                        title: Text(user.name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(user.email,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.sageGray,
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          onSelected(user);
                        },
                      );
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

// ───────────────────────────────────────────────────────────────────────────
// Chats tab — no top bar. Search floats at the bottom, right next to the
// new-chat FAB, above the bottom nav (per user preference).
// ───────────────────────────────────────────────────────────────────────────
class _ChatsTab extends ConsumerWidget {
  const _ChatsTab({required this.search, required this.onNewChat});

  final TextEditingController search;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const [];
    final byId = {for (final u in users) u.uid: u};
    final meUid = ref.watch(authStateProvider).value?.uid;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          child: chats.when(
            loading: () => const _LoadingList(),
            error: (e, _) => _ErrorState(message: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return _EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Your chats live here',
                  subtitle:
                      'Start a conversation with any Hangout friend — they’ll show up here.',
                  actionLabel: 'Start a chat',
                  onAction: onNewChat,
                );
              }
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: search,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? list
                      : list.where((chat) {
                          final peer = _peerOf(chat, meUid, byId);
                          final preview = chat.lastMessage ?? '';
                          return peer.name.toLowerCase().contains(query) ||
                              preview.toLowerCase().contains(query);
                        }).toList();
                  if (filtered.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      subtitle: 'Try a different name or message.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => ref.invalidate(chatsProvider),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 76,
                        endIndent: 16,
                        color: dark
                            ? Colors.white.withOpacity(.06)
                            : const Color(0xFFE8F4F1),
                      ),
                      itemBuilder: (context, i) {
                        final chat = filtered[i];
                        final peer = _peerOf(chat, meUid, byId);
                        return _ChatTile(
                          chat: chat,
                          peer: peer,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ChatScreen(peer: peer, chatId: chat.chatId),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Search pill + new-chat FAB floating above the bottom nav.
        Positioned(
          left: 16,
          right: 16,
          bottom: 10,
          child: Row(
            children: [
              Expanded(
                child: SearchPill(
                  controller: search,
                  hint: 'Search chats',
                  elevated: true,
                ),
              ),
              const SizedBox(width: 12),
              _NewChatFab(onPressed: onNewChat),
            ],
          ),
        ),
      ],
    );
  }

  AppUser _peerOf(ChatSummary chat, String? meUid, Map<String, AppUser> byId) {
    final peerId = chat.participants.firstWhere(
      (p) => p != meUid,
      orElse: () => chat.participants.isNotEmpty ? chat.participants.first : '',
    );
    return byId[peerId] ?? AppUser(uid: peerId, name: 'Hangout user', email: '');
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({required this.chat, required this.peer, required this.onTap});

  final ChatSummary chat;
  final AppUser peer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final time =
        chat.lastMessageAt != null ? _formatTime(chat.lastMessageAt!.toLocal()) : '';
    final preview = chat.lastMessage ?? 'Start the conversation';

    // WhatsApp-style clean row: no card box, avatar + name on top /
    // preview below, hairline divider between rows.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            UserAvatar(user: peer, radius: 26, showPresence: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          peer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: dark ? Colors.white : AppColors.deepInk,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: TextStyle(
                          color: dark ? Colors.white38 : AppColors.sageGray,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dark ? Colors.white60 : AppColors.sageGray,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    return sameDay ? DateFormat.jm().format(date) : DateFormat.MMMd().format(date);
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Contacts tab
// ───────────────────────────────────────────────────────────────────────────
class _ContactsTab extends ConsumerWidget {
  const _ContactsTab({required this.search});

  final TextEditingController search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: users.when(
            loading: () => const _LoadingList(),
            error: (e, _) => _ErrorState(message: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return const _EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No one here yet',
                  subtitle: 'Friends with a Hangout account will appear here.',
                );
              }
              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: search,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
>>>>>>> theirs
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

<<<<<<< ours
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
=======
// ───────────────────────────────────────────────────────────────────────────
// Shared states
// ───────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: dark ? AppColors.darkBubbleIn : AppColors.paleMint,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(icon, size: 42, color: AppColors.teal),
            ),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? Colors.white60 : AppColors.sageGray,
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              GradientButton(
                label: actionLabel,
                icon: Icons.add_rounded,
                height: 52,
                onPressed: onAction,
              ),
            ],
          ],
>>>>>>> theirs
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
