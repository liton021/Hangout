import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_summary.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/brand_logo.dart';
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

  static const _titles = ['Chats', 'Contacts', 'Calls', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStateProvider).value;
      if (me != null) ref.read(callControllerProvider.notifier).init(me.uid);
    });
  }

  @override
  void dispose() {
    _chatSearch.dispose();
    _contactSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentAppUserProvider).value;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        titleSpacing: 20,
        title: Row(
          children: [
            const BrandLogo(size: 38),
            const SizedBox(width: 12),
            Text(_titles[_tab]),
          ],
        ),
        actions: [
          if (_tab != 3)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: me != null
                  ? UserAvatar(user: me, radius: 19, showPresence: true)
                  : IconButton(
                      onPressed: null,
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _ChatsTab(search: _chatSearch),
          _ContactsTab(search: _contactSearch),
          const CallsTab(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _FloatingNavBar(
        selectedIndex: _tab,
        onSelected: (i) => setState(() => _tab = i),
      ),
      floatingActionButton: _tab == 0
          ? _NewChatFab(onPressed: () => _showNewChatSheet())
          : null,
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
// Bottom navigation — white rounded bar, identical on every tab (report §6.3)
// ───────────────────────────────────────────────────────────────────────────
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppColors.floatingShadow,
        border: Border.all(
          color: dark ? Colors.white.withOpacity(.07) : Colors.white,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Contacts',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              selectedIcon: Icon(Icons.call_rounded),
              label: 'Calls',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Settings',
            ),
          ],
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
// Chats tab
// ───────────────────────────────────────────────────────────────────────────
class _ChatsTab extends ConsumerWidget {
  const _ChatsTab({required this.search});

  final TextEditingController search;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const [];
    final byId = {for (final u in users) u.uid: u};
    final meUid = ref.watch(authStateProvider).value?.uid;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SearchPill(
            controller: search,
            hint: 'Search chats',
          ),
        ),
        Expanded(
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SearchPill(
            controller: search,
            hint: 'Search contacts',
          ),
        ),
        Expanded(
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
