import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../models/channel.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/app_header.dart';
import '../../widgets/avatar.dart';
import '../../widgets/search_field.dart';
import '../../widgets/states.dart';

/// Discovery tab — search, a grid of suggested people and trending channels.
class DiscoveryTab extends ConsumerStatefulWidget {
  const DiscoveryTab({super.key, required this.onProfileTap});

  final VoidCallback onProfileTap;

  @override
  ConsumerState<DiscoveryTab> createState() => _DiscoveryTabState();
}

class _DiscoveryTabState extends ConsumerState<DiscoveryTab> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _showAllSuggestions = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);
    final chats = ref.watch(chatsProvider).value ?? const [];
    final me = ref.watch(currentAppUserProvider).value;
    final channels = ref.watch(channelsProvider);

    // People you already have a conversation with — used to pick suggestions
    // and to switch the card's button between "Connect" and "Message".
    final meUid = ref.watch(authStateProvider).value?.uid;
    final connected = <String>{
      for (final chat in chats)
        ...chat.participants.where((p) => p != meUid),
    };

    return Column(
      children: [
        AppHeader(
          title: 'Discovery',
          centerTitle: true,
          leading: GestureDetector(
            onTap: widget.onProfileTap,
            child: me == null
                ? const IconAvatar(icon: Icons.person_rounded, radius: 18)
                : UserAvatar(user: me, radius: 18),
          ),
          actions: [
            HeaderIconButton(
              icon: Icons.search_rounded,
              tooltip: 'Search',
              onPressed: _searchFocus.requestFocus,
            ),
          ],
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const LoadingState(),
            error: (e, _) => ErrorStateView(message: '$e'),
            data: (all) {
              final query = _search.text.trim().toLowerCase();
              final matching = query.isEmpty
                  ? all
                  : all
                      .where((u) =>
                          u.name.toLowerCase().contains(query) ||
                          u.email.toLowerCase().contains(query))
                      .toList();

              // Suggest new people first, then everyone else.
              final suggestions = [
                ...matching.where((u) => !connected.contains(u.uid)),
                ...matching.where((u) => connected.contains(u.uid)),
              ];
              final visible = _showAllSuggestions || query.isNotEmpty
                  ? suggestions
                  : suggestions.take(4).toList();

              return ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                    child: SearchField(
                      controller: _search,
                      focusNode: _searchFocus,
                      hint: 'Search people, groups, and channels...',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 12, 14),
                    child: SectionHeader(
                      title: query.isEmpty ? 'Suggested for You' : 'Results',
                      actionLabel: suggestions.length > 4 && query.isEmpty
                          ? (_showAllSuggestions ? 'Show Less' : 'See All')
                          : null,
                      onAction: () => setState(
                          () => _showAllSuggestions = !_showAllSuggestions),
                    ),
                  ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: _PlaceholderCard(
                        icon: Icons.person_search_rounded,
                        title: 'No people to show',
                        subtitle:
                            'Invite a friend to Hangout and they’ll appear here.',
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 218,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) => _SuggestionCard(
                        user: visible[i],
                        connected: connected.contains(visible[i].uid),
                      ),
                    ),
                  const SizedBox(height: 30),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: SectionHeader(title: 'Trending Channels'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: channels.when(
                      loading: () => const _PlaceholderCard(
                        icon: Icons.hourglass_empty_rounded,
                        title: 'Loading channels',
                        subtitle: 'Hang tight…',
                      ),
                      error: (_, __) => const _PlaceholderCard(
                        icon: Icons.tag_rounded,
                        title: 'Channels unavailable',
                        subtitle: 'Check your connection and try again.',
                      ),
                      data: (list) {
                        if (list.isEmpty) {
                          return const _PlaceholderCard(
                            icon: Icons.tag_rounded,
                            title: 'No channels yet',
                            subtitle:
                                'Public channels will be listed here once they’re available.',
                          );
                        }
                        return Column(
                          children: [
                            for (var i = 0; i < list.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _ChannelRow(channel: list[i], index: i),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Person card: avatar, name, subtitle and a Connect / Message button.
class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({required this.user, required this.connected});

  final AppUser user;
  final bool connected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        children: [
          UserAvatar(user: user, radius: 40),
          const SizedBox(height: 12),
          Text(
            user.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            connected ? 'In your chats' : 'New on Hangout',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              color: palette.textSecondary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: Material(
              color: connected
                  ? palette.surfaceMuted
                  : palette.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => ContactActions.openChat(context, ref, user),
                child: Center(
                  child: Text(
                    connected ? 'Message' : 'Connect',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: connected
                          ? palette.textSecondary
                          : palette.onAccentSoft,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.index});

  final Channel channel;
  final int index;

  static const _tints = [
    AppColors.accent,
    Color(0xFF64748B),
    Color(0xFF7C6CF6),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final tint = _tints[index % _tints.length];
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              _iconFor(channel.icon),
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  channel.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Joining ${channel.name} is coming soon')),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Text(
                  'Join',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String? name) {
    switch (name) {
      case 'design':
        return Icons.design_services_rounded;
      case 'code':
        return Icons.code_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'news':
        return Icons.newspaper_rounded;
      default:
        return Icons.tag_rounded;
    }
  }
}

/// Muted card used when a section has nothing to show.
class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: palette.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: palette.textSecondary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: palette.textSecondary,
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
