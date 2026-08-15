import 'package:cloud_firestore/cloud_firestore.dart';

/// A single text message inside a 1-on-1 chat.
class ChatMessage {
  final String id;
  final String chatId;
  final String authorId;
  final String text;
  final DateTime sentAt;
  final bool read;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.authorId,
    required this.text,
    required this.sentAt,
    this.read = false,
  });

  factory ChatMessage.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      chatId: data['chatId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      sentAt: (data['sentAt'] as Timestamp).toDate(),
      read: data['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'chatId': chatId,
        'authorId': authorId,
        'text': text,
        'sentAt': Timestamp.fromDate(sentAt),
        'read': read,
      };
}
