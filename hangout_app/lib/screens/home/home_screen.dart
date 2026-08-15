import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_summary.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../widgets/avatar.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';
import '../chat/chat_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Start listening for incoming calls once signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(authStateProvider).value;
      if (me != null) {
        ref.read(callControllerProvider.notifier).init(me.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Hangout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [_ChatsTab(), _ContactsTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chats tab
// ---------------------------------------------------------------------------

class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const [];

    final byId = {for (final u in users) u.uid: u};

    return chats.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.chat_bubble_outline,
            title: 'No conversations yet',
            subtitle: 'Start a chat from the Contacts tab.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) {
            final chat = list[i];
            final peer = _peerOf(chat, ref, byId);
            return _ChatTile(
              chat: chat,
              peer: peer,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(peer: peer, chatId: chat.chatId),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  AppUser _peerOf(
      ChatSummary chat, WidgetRef ref, Map<String, AppUser> byId) {
    final me = ref.watch(authStateProvider).value?.uid;
    final peerId = chat.participants.firstWhere((p) => p != me,
        orElse: () => chat.participants.isNotEmpty ? chat.participants.first : '');
    return byId[peerId] ??
        AppUser(uid: peerId, name: 'User', email: '');
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
        ? DateFormat.Hm().format(chat.lastMessageAt!.toLocal())
        : '';
    final preview = chat.lastMessage ?? 'Say hi 👋';

    return ListTile(
      onTap: onTap,
      leading: UserAvatar(user: peer),
      title: Text(
        peer.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.grey),
      ),
      trailing: Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
    );
  }
}

// ---------------------------------------------------------------------------
// Contacts tab
// ---------------------------------------------------------------------------

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);

    return users.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const _EmptyState(
            icon: Icons.people_outline,
            title: 'No contacts yet',
            subtitle: 'Invite friends to create an account and they will appear here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
          itemBuilder: (context, i) {
            final user = list[i];
            return ListTile(
              leading: UserAvatar(user: user),
              title: Text(user.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.videocam_outlined),
                    color: Theme.of(context).colorScheme.primary,
                    tooltip: 'Video call',
                    onPressed: () async {
                      await _startCall(context, ref, user, CallType.video);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.call_outlined),
                    color: Theme.of(context).colorScheme.primary,
                    tooltip: 'Audio call',
                    onPressed: () async {
                      await _startCall(context, ref, user, CallType.audio);
                    },
                  ),
                ],
              ),
              onTap: () async {
                final meUid = ref.read(authStateProvider).value?.uid;
                if (meUid == null) return;
                final chatId = await ref
                    .read(chatServiceProvider)
                    .ensureChat(meUid, user.uid);
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(peer: user, chatId: chatId),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => type == CallType.video
            ? VideoCallScreen(call: call, isCaller: true)
            : AudioCallScreen(call: call, isCaller: true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared empty state
// ---------------------------------------------------------------------------

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
