import 'dart:async';
import 'dart:ui' show FontFeature;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart' show Amplitude;

import '../../config/app_config.dart';
import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../models/chat_message.dart';
import '../../providers/providers.dart';
import '../../services/image_message_service.dart';
import '../../services/voice_note_service.dart';
import '../../widgets/chat_backdrop.dart';
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
            // Explicit recipient uid — never derived from the chat id, see
            // ChatService.sendMessage.
            otherUid: widget.peer.uid,
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
            otherUid: widget.peer.uid,
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

  /// Picks a photo from the gallery, compresses it, uploads it and posts it
  /// as an image message. Mirrors the voice flow (upload → Firestore doc →
  /// push), so the recipient gets a "🖼️ Photo" notification.
  ///
  /// [onProgress] drives the composer's upload indicator.
  Future<void> _sendImage({
    required void Function(double) onProgress,
  }) async {
    final me = ref.read(authStateProvider).value;
    if (me == null) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your photos. Check the app permissions.'),
          ),
        );
      }
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That photo could not be read.')),
        );
      }
      return;
    }
    if (bytes.lengthInBytes > kChatImageMaxSourceBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That photo is too large.')),
        );
      }
      return;
    }

    try {
      final url = await ref
          .read(imageMessageServiceProvider)
          .upload(bytes, onProgress: onProgress);

      await ref.read(chatServiceProvider).sendMessage(
            chatId: widget.chatId,
            authorId: me.uid,
            authorName: me.displayName?.trim().isNotEmpty == true
                ? me.displayName!.trim()
                : 'Hangout user',
            otherUid: widget.peer.uid,
            // Fallback label for the chat list and notifications.
            text: '🖼️ Photo',
            imageUrl: url,
          );
      _scrollToBottom();
    } on ImageMessageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo wasn’t sent.')),
        );
      }
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
            // Telegram's chat backdrop: flat surface color + the faint
            // repeating paper-tear pattern behind the messages.
            child: Container(
              decoration:
                  BoxDecoration(gradient: palette.chatBackground),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ChatBackdrop(),
                  messages.when(
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
                          title:
                              'Say hello to ${widget.peer.name.split(' ').first}',
                          subtitle:
                              'This is the beginning of your conversation.',
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
                          final next =
                              i < list.length - 1 ? list[i + 1] : null;
                          final mine = message.authorId == me?.uid;
                          final startsDay = previous == null ||
                              !_sameDay(previous.sentAt, message.sentAt);
                          final startsGroup = previous == null ||
                              previous.authorId != message.authorId ||
                              message.sentAt
                                      .difference(previous.sentAt)
                                      .inMinutes >
                                  3;
                          final endsGroup = next == null ||
                              next.authorId != message.authorId ||
                              next.sentAt.difference(message.sentAt).inMinutes >
                                  3;

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
                ],
              ),
            ),
          ),
_Composer(
            controller: _input,
            sending: _sending,
            onSend: _send,
            onSendVoice: _sendVoice,
            onSendImage: _sendImage,
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
    required this.onSendImage,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final Future<void> Function(
    VoiceRecording recording, {
    required void Function(double) onProgress,
  }) onSendVoice;
  final Future<void> Function({
    required void Function(double) onProgress,
  }) onSendImage;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  bool _emojiOpen = false;

  // ── voice recording state ────────────────────────────────────────────
  bool _recording = false;

  /// True while the take is paused (recording continues on resume).
  bool _paused = false;
  bool _uploading = false;
  double _uploadProgress = 0;
  String _uploadLabel = 'Sending voice message…';
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitudeSub;

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

  /// Starts a recording with a plain tap on the mic button.
  ///
  /// Recording continues until the user pauses (button becomes a pause
  /// control), and the take can then be resumed, sent or discarded.
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
      _paused = false;
      _elapsed = Duration.zero;
      _level = 0;
    });

    _startTicker();
    _amplitudeSub = service.amplitudeStream().listen((amp) {
      if (!mounted || _paused) return;
      // dBFS is roughly -60 (silence) → 0 (clipping).
      final normalised = ((amp.current + 45) / 45).clamp(0.0, 1.0).toDouble();
      setState(() => _level = normalised);
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_recording || _paused) return;
      setState(() => _elapsed += const Duration(milliseconds: 200));
      // Stop exactly at the cap rather than letting the server reject it.
      if (_elapsed >= kVoiceMaxDuration) _sendRecording();
    });
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
  }

  /// Pauses the take: the elapsed clock freezes and the bar switches to the
  /// paused controls (continue / send / cancel).
  Future<void> _pauseRecording() async {
    if (!_recording || _paused) return;
    _ticker?.cancel();
    _ticker = null;
    await ref.read(voiceNoteServiceProvider).pause();
    if (mounted) {
      HapticFeedback.selectionClick();
      setState(() => _paused = true);
    }
  }

  /// Resumes a paused take.
  Future<void> _resumeRecording() async {
    if (!_recording || !_paused) return;
    await ref.read(voiceNoteServiceProvider).resume();
    if (mounted) {
      HapticFeedback.selectionClick();
      setState(() => _paused = false);
    }
    _startTicker();
  }

  /// Discards the take and deletes the partial file.
  Future<void> _cancelRecording() async {
    if (!_recording) return;
    _stopTimers();
    setState(() {
      _recording = false;
      _paused = false;
      _elapsed = Duration.zero;
    });
    HapticFeedback.lightImpact();
    await ref.read(voiceNoteServiceProvider).cancel();
  }

  /// Stops the take (from either state) and sends it as a voice message.
  Future<void> _sendRecording() async {
    if (!_recording) return;
    _stopTimers();
    setState(() {
      _recording = false;
      _paused = false;
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
          const SnackBar(content: Text('Recording too short.')),
        );
      }
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadLabel = 'Sending voice message…';
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
        _elapsed = Duration.zero;
      });
    }
  }

  /// Picks and uploads a photo through the parent's [onSendImage] callback,
  /// driving the same determinate progress bar as voice uploads.
  Future<void> _pickAndSendImage() async {
    if (_recording || _uploading) return;
    setState(() {
      _uploading = true;
      _uploadProgress = 0;
      _uploadLabel = 'Sending photo…';
    });

    await widget.onSendImage(
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
                      _uploadLabel,
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Only the left-hand side swaps while recording. While the
                  // take is live it shows the pulsing recording bar; once
                  // paused it shows the continue / send / cancel controls.
                  if (_recording && !_paused)
                    Expanded(
                      child: _RecordingBar(
                        elapsed: _formatElapsed(_elapsed),
                        level: _level,
                      ),
                    )
                  else if (_recording && _paused)
                    Expanded(
                      child: _PausedBar(
                        elapsed: _formatElapsed(_elapsed),
                        onSend: _sendRecording,
                        onCancel: _cancelRecording,
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
                        // Photo & emoji buttons sit vertically centred
                        // against the text field, like every modern
                        // messenger.
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Gallery button — hidden entirely when photos are
                          // not configured, so there is no dead control.
                          if (AppConfig.useImageServer)
                            IconButton(
                              tooltip: 'Photo',
                              icon: Icon(
                                Icons.photo_library_outlined,
                                color: palette.textSecondary,
                                size: 24,
                              ),
                              onPressed: _pickAndSendImage,
                            ),
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

                      // The round button's action changes with state:
                      //   idle + text   → send
                      //   idle + empty  → mic (tap to START recording)
                      //   recording     → pause (tap to pause the take)
                      //   paused        → play (resume; bar holds send/cancel)
                      final busy = _uploading || widget.sending;
                      IconData icon;
                      String? tooltip;
                      VoidCallback? onTap;
                      final active = !busy && (hasText || AppConfig.useVoiceServer || _recording);

                      if (busy) {
                        icon = _recording ? Icons.pause_rounded : Icons.send_rounded;
                      } else if (_recording && !_paused) {
                        icon = Icons.pause_rounded;
                        tooltip = 'Pause recording';
                        onTap = _pauseRecording;
                      } else if (_recording && _paused) {
                        icon = Icons.play_arrow_rounded;
                        tooltip = 'Continue recording';
                        onTap = _resumeRecording;
                      } else if (hasText) {
                        icon = Icons.send_rounded;
                        tooltip = 'Send';
                        onTap = widget.onSend;
                      } else if (AppConfig.useVoiceServer) {
                        icon = Icons.mic_rounded;
                        tooltip = 'Record a voice message';
                        onTap = _startRecording;
                      } else {
                        icon = Icons.send_rounded;
                      }

                      return Tooltip(
                        message: tooltip ?? '',
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color:
                                active ? AppColors.accent : palette.surfaceMuted,
                            shape: BoxShape.circle,
                            boxShadow: active
                                ? const [
                                    BoxShadow(
                                      color: Color(0x4D3390EC),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: onTap,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: busy
                                    ? const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        icon,
                                        color: active
                                            ? Colors.white
                                            : palette.textSecondary,
                                        size: 22,
                                      ),
                              ),
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

/// Replaces the text field while a voice note is being recorded: a pulsing
/// red dot, the elapsed time and a live level meter. Tap the round pause
/// button (right) to pause the take.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.level,
  });

  final String elapsed;
  final double level;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          const _PulsingDot(active: true),
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
            child: _LevelMeter(level: level, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

/// Shown while a take is paused: frozen elapsed time plus the choice to send
/// the note as-is or discard it. Continue lives on the round button (play).
class _PausedBar extends StatelessWidget {
  const _PausedBar({
    required this.elapsed,
    required this.onSend,
    required this.onCancel,
  });

  final String elapsed;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        children: [
          Icon(Icons.pause_circle_filled_rounded,
              size: 18, color: palette.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Paused',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            elapsed,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          _PillAction(
            icon: Icons.send_rounded,
            label: 'Send',
            onTap: onSend,
            emphasized: true,
          ),
          const SizedBox(width: 6),
          _PillAction(
            icon: Icons.delete_outline_rounded,
            label: 'Cancel',
            onTap: onCancel,
            danger: true,
          ),
        ],
      ),
    );
  }
}

/// A small pill button inside the paused bar.
class _PillAction extends StatelessWidget {
  const _PillAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool emphasized;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    final foreground = danger
        ? AppColors.danger
        : emphasized
            ? Colors.white
            : palette.textPrimary;
    return Material(
      color: danger
          ? Colors.transparent
          : emphasized
              ? AppColors.accent
              : palette.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
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
          // Telegram-style: outgoing is a SOLID bubble (blue in dark,
          // green in light), incoming is the surface with a thin border.
          color: mine
              ? (context.isDark
                  ? AppColors.chatOutBubble
                  : AppColors.lightChatOutBubble)
              : palette.surface,
          border: Border.all(
            color: mine ? Colors.transparent : palette.divider,
            width: .8,
          ),
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
            else if (message.isImage)
              _PhotoBubble(url: message.imageUrl!, mine: mine)
            else
              Text(
                message.text,
                style: TextStyle(
                  // Dark theme: white on the blue outgoing bubble. Light
                  // theme: Telegram uses near-black on its green bubble.
                  color: mine
                      ? (context.isDark ? Colors.white : const Color(0xFF000000))
                      : palette.textPrimary,
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
                        color: mine
                            ? (context.isDark
                                ? Colors.white70
                                : const Color(0xFF4A4A4A))
                            : palette.textSecondary,
                      ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: mine
                          ? (context.isDark
                              ? (message.read
                                  ? Colors.white
                                  : Colors.white70)
                              : (message.read
                                  ? AppColors.accent
                                  : const Color(0xFF4A4A4A)))
                          : palette.textSecondary,
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

/// A chat photo inside a message bubble. Tapping it opens the full-screen
/// viewer (pinch-zoomable).
class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({required this.url, required this.mine});

  final String url;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    const size = 230.0;

    return GestureDetector(
      onTap: () => _openViewer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: size,
              height: size,
              color: palette.surfaceMuted,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          },
          errorBuilder: (context, error, stack) => Container(
            width: size,
            height: size,
            color: palette.surfaceMuted,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  size: 34,
                  color: palette.textSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  'Photo expired',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(.92),
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white70,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stack) => const Center(
                      child: Text(
                        'This photo has expired.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
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
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.accentSurface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: context.colors.accentSurface,
              width: .8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.accentSoft,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
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
