import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_summary.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/search_pill.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';
import 'calls_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  final _chatSearch = TextEditingController();
  final _contactSearch = TextEditingController();
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

  @override
  void dispose() {
    _chatSearch.dispose();
    _contactSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            _ChatsTab(search: _chatSearch, onNewChat: _showNewChatSheet),
            _ContactsTab(search: _contactSearch),
            const CallsTab(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
      ),
    );
  }

  // ── New chat sheet (report §4: "floating compose button") ────────────────
  void _showNewChatSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewChatSheet(onSelected: _openChatWith),
    );
  }

  Future<void> _openChatWith(AppUser user) async {
    final meUid = ref.read(authStateProvider).value?.uid;
    if (meUid == null) return;
    final chatId =
        await ref.read(chatServiceProvider).ensureChat(meUid, user.uid);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatScreen(peer: user, chatId: chatId),
    ));
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Bottom navigation — compact icon-only capsule, identical on every tab.
// Fully rounded; the selected tab shows a filled pale-mint circle behind
// the icon. Labels are removed (icons + tooltips carry the meaning).
// ───────────────────────────────────────────────────────────────────────────
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _labels = ['Chats', 'Contacts', 'Calls', 'Settings'];
  static const _icons = [
    Icons.chat_bubble_outline_rounded,
    Icons.people_outline_rounded,
    Icons.call_outlined,
    Icons.tune_rounded,
  ];
  static const _selectedIcons = [
    Icons.chat_bubble_rounded,
    Icons.people_rounded,
    Icons.call_rounded,
    Icons.tune_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: dark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppColors.floatingShadow,
          border: Border.all(
            color: dark ? Colors.white.withOpacity(.07) : Colors.white,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              _NavItem(
                icon: _icons[i],
                selectedIcon: _selectedIcons[i],
                label: _labels[i],
                selected: selectedIndex == i,
                onTap: () => onSelected(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final idleColor = dark ? Colors.white54 : AppColors.sageGray;

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: selected ? AppColors.paleMint : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            selected ? selectedIcon : icon,
            size: 24,
            color: selected ? AppColors.teal : idleColor,
          ),
        ),
      ),
    );
  }
}

class _NewChatFab extends StatelessWidget {
  const _NewChatFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          gradient: AppColors.brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x4012A897),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

class _NewChatSheet extends ConsumerWidget {
  const _NewChatSheet({required this.onSelected});

  final ValueChanged<AppUser> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .72,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New chat',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Pick someone to start chatting',
                    style: TextStyle(
                      color: dark ? Colors.white60 : AppColors.sageGray,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: users.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Couldn’t load contacts: $e',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.sageGray),
                  ),
                ),
                data: (list) {
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

    return Stack(
      children: [
        Positioned.fill(
          child: chats.when(
            loading: () => const _LoadingList(),
            error: (e, _) => _ErrorState(message: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return const _EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Your chats live here',
                  subtitle:
                      'Choose someone from People and start a conversation.',
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
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
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

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              UserAvatar(user: peer, radius: 27, showPresence: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(peer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium),
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
                  final filtered = query.isEmpty
                      ? list
                      : list
                          .where((u) =>
                              u.name.toLowerCase().contains(query) ||
                              u.email.toLowerCase().contains(query))
                          .toList();
                  if (filtered.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      subtitle: 'Try a different name or email.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final user = filtered[i];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () =>
                              _openChat(context, ref, user),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                            child: Row(
                              children: [
                                UserAvatar(
                                    user: user,
                                    radius: 25,
                                    showPresence: true),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(user.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 3),
                                      Text(user.email,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .brightness ==
                                                Brightness.dark
                                                ? Colors.white60
                                                : AppColors.sageGray,
                                            fontSize: 13,
                                          )),
                                    ],
                                  ),
                                ),
                                _CircleAction(
                                  icon: Icons.videocam_rounded,
                                  tooltip: 'Video call',
                                  onPressed: () => _startCall(
                                      context, ref, user, CallType.video),
                                ),
                                const SizedBox(width: 2),
                                _CircleAction(
                                  icon: Icons.call_rounded,
                                  tooltip: 'Audio call',
                                  onPressed: () => _startCall(
                                      context, ref, user, CallType.audio),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        // Search pill floating above the bottom nav (no FAB on Contacts).
        Positioned(
          left: 16,
          right: 16,
          bottom: 10,
          child: SearchPill(
            controller: search,
            hint: 'Search contacts',
            elevated: true,
          ),
        ),
      ],
    );
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref, AppUser user) async {
    final meUid = ref.read(authStateProvider).value?.uid;
    if (meUid == null) return;
    final chatId = await ref.read(chatServiceProvider).ensureChat(meUid, user.uid);
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(peer: user, chatId: chatId),
      ));
    }
  }

  Future<void> _startCall(
      BuildContext context, WidgetRef ref, AppUser peer, CallType type) async {
    // The user must grant mic/camera before we create the call.
    final ok =
        await PermissionService.ensureForCall(context, video: type == CallType.video);
    if (!ok) return;
    final me = ref.read(currentAppUserProvider).value;
    if (me == null) return;
    final call = await ref.read(callControllerProvider.notifier).startCall(
          caller: me,
          callee: peer,
          type: type,
        );
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => type == CallType.video
          ? VideoCallScreen(call: call, isCaller: true)
          : AudioCallScreen(call: call, isCaller: true),
    ));
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.paleMint,
          foregroundColor: AppColors.teal,
        ),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// Shared states
// ───────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

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
          ],
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(color: AppColors.aquaTeal));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => _EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load this page',
        subtitle: message,
      );
}
