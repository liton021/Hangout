import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart' show Amplitude;

import '../../config/app_config.dart';
import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_message.dart';
import '../../providers/providers.dart';
import '../../services/voice_note_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/avatar.dart';
import '../../widgets/states.dart';
import '../../widgets/voice_note_player.dart';

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
            authorName: me.displayName?.trim().isNotEmpty == true
                ? me.displayName!.trim()
                : 'Hangout user',
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

  /// Uploads a finished recording, then posts it as a voice message.
  ///
  /// [onProgress] drives the composer's upload indicator.
  Future<void> _sendVoice(
    VoiceRecording recording, {
    required void Function(double) onProgress,
  }) async {
    final me = ref.read(authStateProvider).value;
    if (me == null) return;

    try {
      final url = await ref
          .read(voiceNoteServiceProvider)
          .upload(recording, onProgress: onProgress);

      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            authorId: me.uid,
            authorName: me.displayName?.trim().isNotEmpty == true
                ? me.displayName!.trim()
                : 'Hangout user',
            // Fallback label for the chat list and notifications.
            text: '🎤 Voice message',
            audioUrl: url,
            audioSeconds: recording.seconds,
          );
      _scrollToBottom();
    } on VoiceNoteException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice message wasn’t sent.')),
        );
      }
    } finally {
      // The temp file has served its purpose either way.
      await recording.discard();
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
            onSendVoice: _sendVoice,
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
class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onSendVoice,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function(
    VoiceRecording recording, {
    required void Function(double) onProgress,
  }) onSendVoice;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  bool _emojiOpen = false;

  // ── voice recording state ────────────────────────────────────────────
  bool _recording = false;
  bool _cancelArmed = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSub;
  double _dragDx = 0;

  /// How far left the user must slide to abort the recording.
  static const double _cancelThreshold = 90;

  /// Captured once so [dispose] never has to touch `ref` — reading a
  /// provider while the container is being torn down can throw.
  VoiceNoteService? _voiceService;

  @override
  void initState() {
    super.initState();
    _voiceService = ref.read(voiceNoteServiceProvider);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitudeSub?.cancel();
    // If the widget goes away mid-take, drop the partial file.
    if (_recording) {
      _voiceService?.cancel();
    }
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording || _uploading) return;
    final service = ref.read(voiceNoteServiceProvider);

    try {
      await service.start();
    } on VoiceNoteException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _cancelArmed = false;
      _elapsed = Duration.zero;
      _dragDx = 0;
      _level = 0;
    });

    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording) return;
      setState(() => _elapsed += const Duration(milliseconds: 200));
      // Stop exactly at the cap rather than letting the server reject it.
      if (_elapsed >= kVoiceMaxDuration) _finishRecording();
    });

    _amplitudeSub = service.amplitudeStream().listen((amp) {
      if (!mounted) return;
      // dBFS is roughly -60 (silence) → 0 (clipping).
      final normalised = ((amp.current + 45) / 45).clamp(0.0, 1.0).toDouble();
      setState(() => _level = normalised);
    });
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _stopTimers();
    setState(() {
      _recording = false;
      _cancelArmed = false;
      _dragDx = 0;
    });
    HapticFeedback.lightImpact();
    await ref.read(voiceNoteServiceProvider).cancel();
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _stopTimers();
    setState(() {
      _recording = false;
      _dragDx = 0;
    });

    final service = ref.read(voiceNoteServiceProvider);
    VoiceRecording? recording;
    try {
      recording = await service.stop();
    } on VoiceNoteException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    if (recording == null) {
      // Too short to be deliberate — say so instead of failing silently.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hold the mic to record.')),
        );
      }
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
    });

    await widget.onSendVoice(
      recording,
      onProgress: (p) {
        if (mounted) setState(() => _uploadProgress = p);
      },
    );

    if (mounted) {
      setState(() {
        _uploading = false;
        _uploadProgress = 0;
      });
    }
  }

  String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

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
            if (_emojiOpen && !_recording)
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
            if (_uploading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Row(
                  children: [
                    Icon(Icons.upload_rounded,
                        size: 15, color: palette.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Sending voice message…',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          minHeight: 3,
                          backgroundColor: palette.surfaceMuted,
                          color: AppColors.accent,
                        ),
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
                  // Only the left-hand side swaps while recording. The mic
                  // button below must stay mounted for the whole press —
                  // rebuilding it mid-gesture would kill the long-press and
                  // the recording could never be stopped.
                  if (_recording)
                    Expanded(
                      child: _RecordingBar(
                        elapsed: _formatElapsed(_elapsed),
                        level: _level,
                        cancelArmed: _cancelArmed,
                        dragDx: _dragDx,
                      ),
                    )
                  else
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
                      final hasText = value.text.trim().isNotEmpty;
                      // With text -> send. Empty -> hold to record, but only
                      // when voice is actually configured; otherwise the
                      // button stays a disabled send button rather than a
                      // mic that does nothing.
                      final voiceMode = !hasText && AppConfig.useVoiceServer;
                      final active = hasText || voiceMode;

                      final button = Material(
                        color: active
                            ? AppColors.accent
                            : palette.surfaceMuted,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: hasText && !widget.sending
                              ? widget.onSend
                              : voiceMode
                                  // A plain tap is a common mistake — tell
                                  // the user what to do instead.
                                  ? () => ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                      content: Text('Hold to record a voice message.'),
                                      duration: Duration(seconds: 2),
                                    ))
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
                                    // Only ever show a mic when it does
                                    // something; otherwise this stays an
                                    // inert send button.
                                    voiceMode
                                        ? Icons.mic_rounded
                                        : Icons.send_rounded,
                                    color: active
                                        ? Colors.white
                                        : palette.textSecondary,
                                    size: voiceMode ? 22 : 21,
                                  ),
                          ),
                        ),
                      );

                      if (!voiceMode || _uploading) return button;

                      // Press-and-hold to record; slide left to abort.
                      return GestureDetector(
                        onLongPressStart: (_) => _startRecording(),
                        onLongPressEnd: (_) {
                          if (_cancelArmed) {
                            _cancelRecording();
                          } else {
                            _finishRecording();
                          }
                        },
                        onLongPressMoveUpdate: (details) {
                          if (!_recording) return;
                          final dx = details.localOffsetFromOrigin.dx;
                          final armed = dx < -_cancelThreshold;
                          if (armed != _cancelArmed) {
                            HapticFeedback.selectionClick();
                          }
                          setState(() {
                            _dragDx = dx.clamp(-160.0, 0.0).toDouble();
                            _cancelArmed = armed;
                          });
                        },
                        child: button,
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

/// Replaces the text field while a voice note is being recorded: a pulsing
/// red dot, the elapsed time, a live level meter and a slide-to-cancel hint.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.level,
    required this.cancelArmed,
    required this.dragDx,
  });

  final String elapsed;
  final double level;
  final bool cancelArmed;
  final double dragDx;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    // Fade the bar out as the finger slides towards the cancel threshold.
    final slideProgress = (dragDx.abs() / 90).clamp(0.0, 1.0).toDouble();

    return Opacity(
              opacity: cancelArmed ? 0.45 : 1.0,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: cancelArmed
                      ? Colors.red.withOpacity(.12)
                      : palette.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Row(
                  children: [
                    _PulsingDot(active: !cancelArmed),
                    const SizedBox(width: 10),
                    Text(
                      elapsed,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LevelMeter(
                        level: level,
                        color: cancelArmed
                            ? Colors.red.withOpacity(.5)
                            : AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // The hint slides with the finger, then flips to a
                    // "release to cancel" affordance.
                    Transform.translate(
                      offset: Offset(dragDx * .35, 0),
                      child: cancelArmed
                          ? const Text(
                              'Release to cancel',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.red,
                              ),
                            )
                          : Opacity(
                              opacity: 1 - slideProgress * .6,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chevron_left_rounded,
                                      size: 17, color: palette.textSecondary),
                                  Text(
                                    'Slide to cancel',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: palette.textSecondary,
                                    ),
                                  ),
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

/// The recording indicator — a red dot that breathes.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.active});
  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect the accessibility setting rather than animating regardless.
    if (MediaQuery.of(context).disableAnimations || !widget.active) {
      return const Icon(Icons.fiber_manual_record, size: 11, color: Colors.red);
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: const Icon(Icons.fiber_manual_record, size: 11, color: Colors.red),
    );
  }
}

/// Live microphone level, drawn as a row of bars that react to loudness.
class _LevelMeter extends StatelessWidget {
  const _LevelMeter({required this.level, required this.color});

  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const bars = 14;
    return SizedBox(
      height: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < bars; i++) ...[
            Expanded(
              child: _MeterBar(
                // Bars near the middle react most, which reads as a voice
                // rather than a flat equaliser.
                height: 3 +
                    17 *
                        level *
                        (1 - ((i - bars / 2).abs() / (bars / 2)) * .65),
                color: color,
              ),
            ),
            if (i != bars - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      height: height.clamp(3.0, 20.0).toDouble(),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
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
            if (message.isVoice)
              VoiceNotePlayer(
                url: message.audioUrl!,
                seconds: message.audioSeconds,
                mine: mine,
              )
            else
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
