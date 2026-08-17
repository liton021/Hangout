import 'package:cloud_firestore/cloud_firestore.dart';

/// What a message carries. Stored as a string so older documents (which have
/// no `kind` field at all) keep decoding as plain text.
enum MessageKind { text, voice }

/// A single message inside a 1-on-1 chat.
///
/// Voice notes reuse the same document shape: [text] holds a short fallback
/// label (shown in the chat list and in notifications), while [audioUrl] and
/// [audioSeconds] describe the recording.
class ChatMessage {
  final String id;
  final String chatId;
  final String authorId;
  final String text;
  final DateTime sentAt;
  final bool read;

  /// `text` for normal messages, `voice` for voice notes.
  final MessageKind kind;

  /// Public URL of the recording on the Cloudflare Worker.
  /// Only set when [kind] is [MessageKind.voice].
  final String? audioUrl;

  /// Duration of the recording, used to size the waveform and show a
  /// countdown before the audio has loaded.
  final int audioSeconds;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.authorId,
    required this.text,
    required this.sentAt,
    this.read = false,
    this.kind = MessageKind.text,
    this.audioUrl,
    this.audioSeconds = 0,
  });

  bool get isVoice => kind == MessageKind.voice && (audioUrl ?? '').isNotEmpty;

  factory ChatMessage.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;

    // Unknown/missing kinds fall back to text so a future message type can
    // never crash an older build.
    final rawKind = data['kind'] as String?;
    final kind = rawKind == 'voice' ? MessageKind.voice : MessageKind.text;

    // `sentAt` can briefly be null on a locally-echoed write before the
    // server timestamp resolves.
    final rawSentAt = data['sentAt'];
    final sentAt =
        rawSentAt is Timestamp ? rawSentAt.toDate() : DateTime.now();

    return ChatMessage(
      id: doc.id,
      chatId: data['chatId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: sentAt,
      read: data['read'] as bool? ?? false,
      kind: kind,
      audioUrl: data['audioUrl'] as String?,
      audioSeconds: (data['audioSeconds'] as num?)?.round() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'chatId': chatId,
        'authorId': authorId,
        'text': text,
        'sentAt': Timestamp.fromDate(sentAt),
        'read': read,
        // Only written for voice notes, so text messages keep exactly the
        // shape they had before this feature existed.
        if (kind == MessageKind.voice) ...{
          'kind': 'voice',
          'audioUrl': audioUrl,
          'audioSeconds': audioSeconds,
        },
      };
}
