import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_message.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar.dart';
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final me = ref.read(authStateProvider).value;
    if (me == null) return;

    setState(() => _sending = true);
    _input.clear();
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
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
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
            Stack(
              children: [
                UserAvatar(user: widget.peer, radius: 21),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text('Online',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600)),
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
          ),
          const SizedBox(width: 3),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton.filledTonal(
              icon: const Icon(Icons.call_rounded, size: 20),
              tooltip: 'Audio call',
              onPressed: () => _startCall(CallType.audio),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Write a message',
                    fillColor: scheme.surfaceContainerLow,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final active = value.text.trim().isNotEmpty && !sending;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: active ? AppColors.brandGradient : null,
                      color: active ? null : scheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: active ? onSend : null,
                      icon: sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.arrow_upward_rounded,
                              color: active
                                  ? Colors.white
                                  : scheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.startsGroup,
    required this.endsGroup,
  });

  final ChatMessage message;
  final bool mine;
  final bool startsGroup;
  final bool endsGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topRadius = startsGroup ? 20.0 : 7.0;
    final bottomRadius = endsGroup ? 20.0 : 7.0;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: startsGroup ? 8 : 2, bottom: endsGroup ? 3 : 0),
        padding: const EdgeInsets.fromLTRB(14, 9, 11, 7),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.brandGradient : null,
          color: mine ? null : scheme.surface,
          border: mine ? null : Border.all(color: scheme.outlineVariant.withOpacity(.45)),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(mine ? topRadius : (startsGroup ? 5 : 7)),
            topRight: Radius.circular(mine ? (startsGroup ? 5 : 7) : topRadius),
            bottomLeft: Radius.circular(mine ? bottomRadius : (endsGroup ? 5 : 7)),
            bottomRight: Radius.circular(mine ? (endsGroup ? 5 : 7) : bottomRadius),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          runSpacing: 2,
          children: [
            Text(message.text,
                style: TextStyle(
                  color: mine ? Colors.white : scheme.onSurface,
                  fontSize: 15.5,
                  height: 1.32,
                )),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat.jm().format(message.sentAt.toLocal()),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                      )),
                  if (mine) ...[
                    const SizedBox(width: 3),
                    Icon(message.read ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 14, color: Colors.white70),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
      ),
    );
  }
}

class _ChatNotice extends StatelessWidget {
  const _ChatNotice({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}
