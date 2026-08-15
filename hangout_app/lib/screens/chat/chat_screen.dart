import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_message.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/presence_dot.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';

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
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

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
      if (_scroll.hasClients) {
        final duration = _reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 220);
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _startCall(CallType type) async {
    final me = ref.read(currentAppUserProvider).value;
    if (me == null) return;
    final call = await ref.read(callControllerProvider.notifier).startCall(
          caller: me,
          callee: widget.peer,
          type: type,
        );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => type == CallType.video
          ? VideoCallScreen(call: call, isCaller: true)
          : AudioCallScreen(call: call, isCaller: true),
    ));
  }

  /// Profile sheet (report §4: profile view with Message / Call / Video).
  void _showProfileSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(user: widget.peer, radius: 44, showPresence: true),
            const SizedBox(height: 16),
            Text(widget.peer.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              widget.peer.email.isEmpty ? 'Hangout user' : widget.peer.email,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white60
                    : AppColors.sageGray,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 22),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.chatId));
    final me = ref.watch(authStateProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(user: widget.peer, radius: 21, showPresence: true),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const PresenceDot(radius: 3.5, borderWidth: 0),
                      const SizedBox(width: 5),
                      Text('Online',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.success,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton.filledTonal(
            icon: const Icon(Icons.videocam_rounded, size: 21),
            tooltip: 'Video call',
            onPressed: () => _startCall(CallType.video),
            style: IconButton.styleFrom(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: AppColors.teal,
            ),
          ),
          const SizedBox(width: 3),
          IconButton.filledTonal(
            icon: const Icon(Icons.call_rounded, size: 20),
            tooltip: 'Audio call',
            onPressed: () => _startCall(CallType.audio),
            style: IconButton.styleFrom(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: AppColors.teal,
            ),
          ),
          const SizedBox(width: 2),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: PopupMenuButton<String>(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: scheme.surface,
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
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.aquaTeal)),
              error: (_, __) => const _ChatNotice(
                icon: Icons.cloud_off_rounded,
                title: 'Messages unavailable',
                subtitle: 'Check your connection and try again.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return _ChatNotice(
                    icon: Icons.waving_hand_rounded,
                    title: 'Say hello to ${widget.peer.name.split(' ').first}',
                    subtitle: 'This is the beginning of your conversation.',
                  );
                }
                if (list.length > _previousMessageCount) {
                  _previousMessageCount = list.length;
                  _scrollToBottom();
                }
                return ListView.builder(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
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
// Floating composer (report §6.2)
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
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add to chat',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _AttachOption(
                icon: Icons.photo_library_outlined,
                color: AppColors.teal,
                label: 'Photos & videos',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _comingSoon('Photos & videos');
                },
              ),
              _AttachOption(
                icon: Icons.insert_drive_file_outlined,
                color: AppColors.aquaTeal,
                label: 'Document',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _comingSoon('Documents');
                },
              ),
              _AttachOption(
                icon: Icons.photo_camera_outlined,
                color: AppColors.brightTeal,
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
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Emoji strip (report §6.4: emoji panel).
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _emojiOpen
              ? Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: dark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      for (final e in _emojiList)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _insertEmoji(e),
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Text(e, style: const TextStyle(fontSize: 22)),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: dark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppColors.floatingShadow,
            border: Border.all(
              color: dark
                  ? Colors.white.withOpacity(.07)
                  : AppColors.teal.withOpacity(.14),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Attach',
                  onPressed: _showAttachSheet,
                  icon: const Icon(Icons.add_rounded, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        dark ? Colors.white.withOpacity(.08) : AppColors.glassMint,
                    foregroundColor: AppColors.teal,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      filled: false,
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: () => setState(() => _emojiOpen = !_emojiOpen),
                  icon: const Icon(Icons.emoji_emotions_rounded,
                      size: 24),
                  color: _emojiOpen ? AppColors.teal : AppColors.sageGray,
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.controller,
                  builder: (context, value, _) {
                    final active =
                        value.text.trim().isNotEmpty && !widget.sending;
                    return AnimatedScale(
                      scale: active ? 1 : .9,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: active ? AppColors.brandGradient : null,
                          color: active
                              ? null
                              : (dark
                                  ? Colors.white.withOpacity(.08)
                                  : AppColors.glassMint),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: active
                              ? widget.onSend
                              : () => _comingSoon('Voice messages'),
                          tooltip: active ? 'Send' : 'Voice message',
                          icon: widget.sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(
                                  active
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded,
                                  color: active
                                      ? Colors.white
                                      : AppColors.sageGray,
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
        ),
      ],
    );
  }
}

class _AttachOption extends StatelessWidget {
  const _AttachOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppColors.sageGray),
      onTap: onTap,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Message bubbles (report §6.1: white in / pale-mint out, teal ticks)
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
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final bubble = Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:
            EdgeInsets.only(top: startsGroup ? 8 : 2, bottom: endsGroup ? 3 : 0),
        padding: const EdgeInsets.fromLTRB(14, 9, 12, 8),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        decoration: BoxDecoration(
          color: mine
              ? (dark ? AppColors.darkBubbleOut : AppColors.paleMint)
              : (dark ? AppColors.darkBubbleIn : Colors.white),
          border: mine
              ? null
              : Border.all(color: scheme.outlineVariant.withOpacity(.55)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? topRadius : (startsGroup ? 4 : 8)),
            topRight: Radius.circular(mine ? (startsGroup ? 4 : 8) : topRadius),
            bottomLeft:
                Radius.circular(mine ? bottomRadius : (endsGroup ? 4 : 8)),
            bottomRight:
                Radius.circular(mine ? (endsGroup ? 4 : 8) : bottomRadius),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: dark ? const Color(0xFFEFFBF9) : AppColors.deepInk,
                fontSize: 15.5,
                height: 1.32,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.jm().format(message.sentAt.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: dark ? Colors.white38 : AppColors.sageGray,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    Icon(
                      message.read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      // Read ticks turn teal (report §6.1 / §9).
                      color: message.read
                          ? (dark ? AppColors.softAqua : AppColors.teal)
                          : (dark ? Colors.white38 : AppColors.sageGray),
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
    // Spring-in on send (report §9): ~200ms ease-out, no re-run on rebuilds.
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

  double get topRadius => startsGroup ? 18 : 6;
  double get bottomRadius => endsGroup ? 18 : 6;
}

// ───────────────────────────────────────────────────────────────────────────
// Day separator chip (report §8: "date separators as centered chips")
// ───────────────────────────────────────────────────────────────────────────
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
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBubbleIn
                : AppColors.paleMint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.softAqua
                  : AppColors.darkTeal,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatNotice extends StatelessWidget {
  const _ChatNotice({
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: dark ? AppColors.darkBubbleIn : AppColors.paleMint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.teal, size: 30),
            ),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? Colors.white60 : AppColors.sageGray,
              ),
            ),
          ],
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
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x3312A897),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.sageGray,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
