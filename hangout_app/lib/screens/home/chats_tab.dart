import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/chat_summary.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/app_header.dart';
import '../../widgets/avatar.dart';
import '../../widgets/search_field.dart';
import '../../widgets/states.dart';
import '../chat/chat_screen.dart';

/// Chats tab — "Messenger": profile avatar, periwinkle title, search action,
/// then a flat list of conversations with unread badges.
class ChatsTab extends ConsumerStatefulWidget {
  const ChatsTab({
    super.key,
    required this.onProfileTap,
    required this.onNewChat,
  });

  final VoidCallback onProfileTap;
  final VoidCallback onNewChat;

  @override
  ConsumerState<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<ChatsTab> {
  final _search = TextEditingController();
  bool _searchOpen = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const <AppUser>[];
    final byId = {for (final u in users) u.uid: u};
    final me = ref.watch(currentAppUserProvider).value;
    final meUid = ref.watch(authStateProvider).value?.uid;

    return Column(
      children: [
        AppHeader(
          title: 'Messenger',
          leading: GestureDetector(
            onTap: widget.onProfileTap,
            child: me == null
                ? const IconAvatar(icon: Icons.person_rounded, radius: 18)
                : UserAvatar(user: me, radius: 18),
          ),
          actions: [
            HeaderIconButton(
              icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
              tooltip: _searchOpen ? 'Close search' : 'Search chats',
              onPressed: _toggleSearch,
            ),
          ],
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: SearchField(
              controller: _search,
              hint: 'Search chats',
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: chats.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Your chats live here',
                  subtitle:
                      'Start a conversation and it will show up in this list.',
                  actionLabel: 'Start a chat',
                  onAction: widget.onNewChat,
                );
              }

              final query = _search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? list
                  : list.where((chat) {
                      final peer = _peerOf(chat, meUid, byId);
                      final preview = chat.lastMessage ?? '';
                      return peer.name.toLowerCase().contains(query) ||
                          preview.toLowerCase().contains(query);
                    }).toList();

              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  subtitle: 'Try a different name or message.',
                );
              }

              return RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                onRefresh: () async => ref.invalidate(chatsProvider),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 6, bottom: 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Padding(
                    padding: EdgeInsets.only(left: 84, right: 20),
                    child: Divider(height: 1, color: AppColors.divider),
                  ),
                  itemBuilder: (context, i) {
                    final chat = filtered[i];
                    final peer = _peerOf(chat, meUid, byId);
                    return ChatRow(
                      chat: chat,
                      peer: peer,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatScreen(peer: peer, chatId: chat.chatId),
                        ),
                      ),
                      onLongPress: () =>
                          ContactActions.showQuickActions(context, ref, peer),
                    );
                  },
                ),
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
    return byId[peerId] ??
        AppUser(uid: peerId, name: 'Hangout user', email: '');
  }
}

/// One conversation row: avatar · name + time · preview + unread badge.
class ChatRow extends ConsumerWidget {
  const ChatRow({
    super.key,
    required this.chat,
    required this.peer,
    required this.onTap,
    this.onLongPress,
  });

  final ChatSummary chat;
  final AppUser peer;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider(chat.chatId)).value ?? 0;
    final hasUnread = unread > 0;
    final time = chat.lastMessageAt != null
        ? _formatTime(chat.lastMessageAt!.toLocal())
        : '';
    final preview = chat.lastMessage ?? 'Start the conversation';

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(user: peer, radius: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          peer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: hasUnread
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.2,
                            color: hasUnread
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight:
                                hasUnread ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 10),
                        UnreadBadge(count: unread),
                      ],
                    ],
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
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return DateFormat.Hm().format(date);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.E().format(date);
    if (now.year == date.year) return DateFormat('MMM d').format(date);
    return DateFormat('MMM d, y').format(date);
  }
}

/// Blue circular unread counter.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
