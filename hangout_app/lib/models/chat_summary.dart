import 'package:cloud_firestore/cloud_firestore.dart';

/// A chat-list row: the conversation + its latest message metadata.
class ChatSummary {
  final String chatId;
  final List<String> participants;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderId;

  const ChatSummary({
    required this.chatId,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderId,
  });

  factory ChatSummary.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return ChatSummary(
      chatId: doc.id,
      participants: (data['participants'] as List?)?.cast<String>() ?? [],
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: (data['lastMessageAt'] as dynamic)?.toDate(),
      lastSenderId: data['lastSenderId'] as String?,
    );
  }
}
