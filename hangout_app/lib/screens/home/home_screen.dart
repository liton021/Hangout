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
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../chat/chat_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Messages', 'People', 'Settings'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStateProvider).value;
      if (me != null) ref.read(callControllerProvider.notifier).init(me.uid);
    });
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
          if (_tab != 2)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: me != null
                  ? UserAvatar(user: me, radius: 19)
                  : IconButton(
                      onPressed: null,
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
            ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [_ChatsTab(), _ContactsTab(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const [];
    final byId = {for (final u in users) u.uid: u};

    return chats.when(
      loading: () => const _LoadingList(),
      error: (e, _) => _ErrorState(message: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Your chats live here',
            subtitle: 'Choose someone from People and start a conversation.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(chatsProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final chat = list[i];
              final peer = _peerOf(chat, ref, byId);
              return _ChatTile(
                chat: chat,
                peer: peer,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(peer: peer, chatId: chat.chatId),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  AppUser _peerOf(ChatSummary chat, WidgetRef ref, Map<String, AppUser> byId) {
    final me = ref.watch(authStateProvider).value?.uid;
    final peerId = chat.participants.firstWhere(
      (p) => p != me,
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
    final time = chat.lastMessageAt != null
        ? _formatTime(chat.lastMessageAt!.toLocal())
        : '';
    final preview = chat.lastMessage ?? 'Start the conversation';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Stack(
                children: [
                  UserAvatar(user: peer, radius: 27),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
                        Text(time,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
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
    final sameDay = now.year == date.year && now.month == date.month && now.day == date.day;
    return sameDay ? DateFormat.jm().format(date) : DateFormat.MMMd().format(date);
  }
}

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    return users.when(
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
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final user = list[i];
            return Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _openChat(context, ref, user),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      UserAvatar(user: user, radius: 25),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 3),
                            Text(user.email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 13,
                                )),
                          ],
                        ),
                      ),
                      _CircleAction(
                        icon: Icons.videocam_rounded,
                        tooltip: 'Video call',
                        onPressed: () =>
                            _startCall(context, ref, user, CallType.video),
                      ),
                      const SizedBox(width: 5),
                      _CircleAction(
                        icon: Icons.call_rounded,
                        tooltip: 'Audio call',
                        onPressed: () =>
                            _startCall(context, ref, user, CallType.audio),
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
  const _CircleAction({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Icon(icon,
                    size: 42, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 22),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  )),
            ],
          ),
        ),
      );
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
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
