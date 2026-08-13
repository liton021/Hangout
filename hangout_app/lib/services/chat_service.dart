import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChatService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// All registered users, newest first — used for the contact list.
  Stream<QuerySnapshot> usersStream() {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Deterministic chat document id for the pair ([uid1], [uid2]).
  ///
  /// Must be used both when writing messages and when reading them —
  /// using the raw peer id for one and this id for the other is a bug.
  static String chatIdFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Stream<QuerySnapshot> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> sendMessage(
    String chatId,
    String senderId,
    String senderName,
    String content,
  ) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Returns the chat id for the pair, creating the chat document on first
  /// use.
  Future<String> createOrGetChat(String user1Id, String user2Id) async {
    final chatId = chatIdFor(user1Id, user2Id);
    final chatRef = _firestore.collection('chats').doc(chatId);

    final doc = await chatRef.get();
    if (!doc.exists) {
      await chatRef.set({
        'participants': [user1Id, user2Id],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    return chatId;
  }
}
