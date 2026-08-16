import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/app_header.dart';
import '../../widgets/avatar.dart';
import '../../widgets/search_field.dart';
import '../../widgets/states.dart';

/// Contacts tab — frequent contacts strip on top, then an A–Z directory with
/// periwinkle letter headers.
class ContactsTab extends ConsumerStatefulWidget {
  const ContactsTab({
    super.key,
    required this.onProfileTap,
    required this.onNewChat,
  });

  final VoidCallback onProfileTap;
  final VoidCallback onNewChat;

  @override
  ConsumerState<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends ConsumerState<ContactsTab> {
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

  /// The people you message most — taken from your most recent conversations.
  List<AppUser> _frequent(Map<String, AppUser> byId) {
    final chats = ref.watch(chatsProvider).value ?? const [];
    final meUid = ref.watch(authStateProvider).value?.uid;
    final result = <AppUser>[];
    for (final chat in chats) {
      if (chat.lastMessageAt == null) continue;
      final peerId = chat.participants.firstWhere(
        (p) => p != meUid,
        orElse: () => '',
      );
      final peer = byId[peerId];
      if (peer != null && !result.any((u) => u.uid == peer.uid)) {
        result.add(peer);
      }
      if (result.length == 4) break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final me = ref.watch(currentAppUserProvider).value;

    return Column(
      children: [
        AppHeader(
          title: 'Contacts',
          leading: GestureDetector(
            onTap: widget.onProfileTap,
            child: me == null
                ? const IconAvatar(icon: Icons.person_rounded, radius: 18)
                : UserAvatar(user: me, radius: 18),
          ),
          actions: [
            CircleAccentButton(
              icon: Icons.add_rounded,
              tooltip: 'New chat',
              onPressed: widget.onNewChat,
            ),
            const SizedBox(width: 4),
            HeaderIconButton(
              icon: _searchOpen ? Icons.close_rounded : Icons.search_rounded,
              tooltip: _searchOpen ? 'Close search' : 'Search contacts',
              onPressed: _toggleSearch,
            ),
          ],
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: SearchField(
              controller: _search,
              hint: 'Search contacts',
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
          ),
        Expanded(
          child: usersAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (all) {
              if (all.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'No one here yet',
                  subtitle:
                      'People with a Hangout account will appear in this list.',
                );
              }

              final byId = {for (final u in all) u.uid: u};
              final query = _search.text.trim().toLowerCase();
              final filtered = query.isEmpty
                  ? all
                  : all
                      .where((u) =>
                          u.name.toLowerCase().contains(query) ||
                          u.email.toLowerCase().contains(query))
                      .toList();

              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matches',
                  subtitle: 'Try a different name or email.',
                );
              }

              final sorted = [...filtered]
                ..sort((a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()));

              final frequent = query.isEmpty ? _frequent(byId) : const <AppUser>[];

              // Flatten into rows so a single ListView keeps scrolling smooth.
              final items = <Widget>[];
              if (frequent.isNotEmpty) {
                items.add(const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: OverlineLabel('Frequent'),
                ));
                items.add(_FrequentStrip(people: frequent));
                items.add(const SizedBox(height: 18));
              }

              String? currentLetter;
              for (final user in sorted) {
                final letter = _letterFor(user.name);
                if (letter != currentLetter) {
                  currentLetter = letter;
                  items.add(Padding(
                    padding: EdgeInsets.fromLTRB(
                        20, items.isEmpty ? 6 : 18, 20, 10),
                    child: Text(
                      letter,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentSoft,
                      ),
                    ),
                  ));
                }
                items.add(_ContactRow(user: user));
              }

              return RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                onRefresh: () async => ref.invalidate(usersProvider),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 28),
                  itemCount: items.length,
                  itemBuilder: (context, i) => items[i],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _letterFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '#';
    final first = trimmed[0].toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }
}

/// Horizontal strip of the four people you talk to most.
class _FrequentStrip extends ConsumerWidget {
  const _FrequentStrip({required this.people});

  final List<AppUser> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: people.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final user = people[i];
          return SizedBox(
            width: 96,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => ContactActions.openChat(context, ref, user),
                onLongPress: () =>
                    ContactActions.showQuickActions(context, ref, user),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(user: user, radius: 26),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          user.name.split(' ').first,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContactRow extends ConsumerWidget {
  const _ContactRow({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => ContactActions.openChat(context, ref, user),
      onLongPress: () => ContactActions.showQuickActions(context, ref, user),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Row(
          children: [
            UserAvatar(user: user, radius: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email.isEmpty ? 'On Hangout' : user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: AppColors.divider),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
