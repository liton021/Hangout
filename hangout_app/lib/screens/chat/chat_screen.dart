import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_message.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/avatar.dart';
import '../../widgets/states.dart';

/// A 1-on-1 conversation: blue outgoing bubbles, charcoal incoming bubbles,
/// day separators and a rounded composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.peer, required this.chatId});

  final AppUser peer;
  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  /// Clears the unread badge for this conversation.
  Future<void> _markRead() async {
    final me = ref.read(authStateProvider).value;
    if (me == null) return;
    try {
      await ref
          .read(chatServiceProvider)
          .markMessagesRead(widget.chatId, me.uid);
    } catch (_) {
      // Read receipts are best-effort — never block the conversation.
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final me = ref.read(authStateProvider).value;
    if (me == null) return;

    setState(() => _sending = true);
    _input.clear();
    if (!_reduceMotion) HapticFeedback.lightImpact();
    try {
      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            authorId: me.uid,
            text: text,
          );
      _scrollToBottom();
    } catch (_) {
      _input.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message wasn’t sent. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration:
            _reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _startCall(CallType type) =>
      ContactActions.startCall(context, ref, widget.peer, type);

  void _showProfileSheet() {
    final palette = context.colors;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(
                user: widget.peer,
                radius: 44,
                ringColor: AppColors.accent,
                presenceBorderColor: palette.surface,
                showPresence: true,
              ),
              const SizedBox(height: 16),
              Text(
                widget.peer.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.peer.email.isEmpty ? 'Hangout user' : widget.peer.email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ProfileAction(
                    icon: Icons.chat_bubble_rounded,
                    label: 'Message',
                    onTap: () => Navigator.of(sheetContext).pop(),
                  ),
                  _ProfileAction(
                    icon: Icons.call_rounded,
                    label: 'Call',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _startCall(CallType.audio);
                    },
                  ),
                  _ProfileAction(
                    icon: Icons.videocam_rounded,
                    label: 'Video',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _startCall(CallType.video);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final messages = ref.watch(messagesProvider(widget.chatId));
    final me = ref.watch(authStateProvider).value;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 0,
        leadingWidth: 40,
        leading: IconButton(
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: InkWell(
          onTap: _showProfileSheet,
          child: Row(
            children: [
              UserAvatar(
                user: widget.peer,
                radius: 20,
                showPresence: true,
                presenceBorderColor: palette.canvas,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_rounded,
                size: 24, color: AppColors.accent),
            tooltip: 'Video call',
            onPressed: () => _startCall(CallType.video),
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded,
                size: 22, color: AppColors.accent),
            tooltip: 'Voice call',
            onPressed: () => _startCall(CallType.audio),
          ),
          PopupMenuButton<String>(
            tooltip: 'More options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'profile') _showProfileSheet();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('View profile'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const LoadingState(),
              error: (_, __) => const EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Messages unavailable',
                subtitle: 'Check your connection and try again.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.waving_hand_rounded,
                    title: 'Say hello to ${widget.peer.name.split(' ').first}',
                    subtitle: 'This is the beginning of your conversation.',
                  );
                }
                if (list.length > _previousMessageCount) {
                  _previousMessageCount = list.length;
                  _scrollToBottom();
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _markRead());
                }
                return ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final message = list[i];
                    final previous = i > 0 ? list[i - 1] : null;
                    final next = i < list.length - 1 ? list[i + 1] : null;
                    final mine = message.authorId == me?.uid;
                    final startsDay = previous == null ||
                        !_sameDay(previous.sentAt, message.sentAt);
                    final startsGroup = previous == null ||
                        previous.authorId != message.authorId ||
                        message.sentAt.difference(previous.sentAt).inMinutes > 3;
                    final endsGroup = next == null ||
                        next.authorId != message.authorId ||
                        next.sentAt.difference(message.sentAt).inMinutes > 3;

                    return Column(
                      children: [
                        if (startsDay) _DayLabel(date: message.sentAt),
                        _MessageBubble(
                          message: message,
                          mine: mine,
                          startsGroup: startsGroup,
                          endsGroup: endsGroup,
                          animate: !_reduceMotion,
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Composer
// ───────────────────────────────────────────────────────────────────────────
class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _emojiOpen = false;

  static const _emojiList = [
    '😀', '😂', '😍', '🥰', '😎', '🤔', '🤗',
    '👍', '🙏', '👏', '🎉', '❤️', '🔥', '💯',
    '🌊', '☕', '🎧', '🎵', '⚽', '🌙',
  ];

  void _insertEmoji(String emoji) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _showAttachSheet() {
    final palette = context.colors;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to chat',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _AttachOption(
                icon: Icons.photo_library_outlined,
                label: 'Photos & videos',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _comingSoon('Photos & videos');
                },
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_outlined,
                label: 'Document',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _comingSoon('Documents');
                },
              ),
              _AttachOption(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _comingSoon('Camera');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature are coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: palette.canvasElevated,
        border: Border(top: BorderSide(color: palette.divider, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_emojiOpen)
              SizedBox(
                height: 108,
                child: GridView.count(
                  crossAxisCount: 7,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    for (final emoji in _emojiList)
                      InkWell(
                        onTap: () => _insertEmoji(emoji),
                        child: Center(
                          child: Text(emoji, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach',
                    icon: Icon(Icons.add_circle_outline_rounded,
                        color: palette.textSecondary),
                    onPressed: _showAttachSheet,
                  ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: palette.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: widget.controller,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              style: TextStyle(
                                fontSize: 16,
                                color: palette.textPrimary,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(18, 12, 8, 12),
                              ),
                              onSubmitted: (_) => widget.onSend(),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Emoji',
                            icon: Icon(
                              _emojiOpen
                                  ? Icons.keyboard_rounded
                                  : Icons.emoji_emotions_outlined,
                              color: palette.textSecondary,
                              size: 22,
                            ),
                            onPressed: () =>
                                setState(() => _emojiOpen = !_emojiOpen),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (context, value, _) {
                      final active = value.text.trim().isNotEmpty;
                      return Material(
                        color: active
                            ? AppColors.accent
                            : palette.surfaceMuted,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: active && !widget.sending
                              ? widget.onSend
                              : null,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: widget.sending
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    active
                                        ? Icons.send_rounded
                                        : Icons.mic_rounded,
                                    color: active
                                        ? Colors.white
                                        : palette.textSecondary,
                                    size: active ? 21 : 22,
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: palette.accentSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(icon, color: palette.accentSoft, size: 21),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
      onTap: onTap,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Bubbles
// ───────────────────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.startsGroup,
    required this.endsGroup,
    required this.animate,
  });

  final ChatMessage message;
  final bool mine;
  final bool startsGroup;
  final bool endsGroup;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    const big = Radius.circular(20);
    const small = Radius.circular(7);

    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: startsGroup ? 8 : 2,
          bottom: endsGroup ? 4 : 0,
        ),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        decoration: BoxDecoration(
          color: mine ? AppColors.accent : palette.surface,
          borderRadius: BorderRadius.only(
            topLeft: mine ? big : (startsGroup ? big : small),
            topRight: mine ? (startsGroup ? big : small) : big,
            bottomLeft: mine ? big : (endsGroup ? big : small),
            bottomRight: mine ? (endsGroup ? big : small) : big,
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          runSpacing: 2,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: mine ? Colors.white : palette.textPrimary,
                fontSize: 15.5,
                height: 1.35,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.Hm().format(message.sentAt.toLocal()),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: mine ? Colors.white70 : palette.textSecondary,
                      ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: message.read ? Colors.white : Colors.white70,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - value)),
          child: child,
        ),
      ),
      child: bubble,
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final label = day.isAtSameMomentAs(today)
        ? 'Today'
        : day.isAtSameMomentAs(today.subtract(const Duration(days: 1)))
            ? 'Yesterday'
            : DateFormat('MMM d, y').format(local);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 23),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
