import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import 'push_sender.dart';

/// Firestore-backed 1-on-1 messaging.
///
/// Schema:
///   chats/{chatId}                 -> { participants: [a,b], lastMessage, lastMessageAt, lastSenderId }
///   chats/{chatId}/messages/{id}   -> ChatMessage
class ChatService {
  ChatService(this._db);

  final FirebaseFirestore _db;

  /// Deterministic chat id for a pair of users (order-independent).
  static String chatIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }

  /// Opens (or returns) the chat between [myUid] and [peerUid].
  Future<String> ensureChat(String myUid, String peerUid) async {
    final id = chatIdFor(myUid, peerUid);
    final ref = _db.collection('chats').doc(id);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'participants': [myUid, peerUid],
        'createdAt': DateTime.now(),
      });
    }
    return id;
  }

  /// Sends a message and bumps the chat's last-message summary.
  Future<void> sendMessage({
    required String chatId,
    required String authorId,
    required String text,
  }) async {
    final msgRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc();
    final now = DateTime.now();
    await msgRef.set(ChatMessage(
      id: msgRef.id,
      chatId: chatId,
      authorId: authorId,
      text: text,
      sentAt: now,
    ).toMap());

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': text,
      'lastMessageAt': now,
      'lastSenderId': authorId,
    }, SetOptions(merge: true));

    _sendMessagePush(chatId, authorId, text);
  }

  /// Fires the FCM push to the other participant via the free Cloudflare
  /// Worker so they get a notification even if their app is killed. Runs
  /// fire-and-forget — the message itself is already in Firestore.
  Future<void> _sendMessagePush(
      String chatId, String authorId, String text) async {
    try {
      // Find the recipient (the participant who is NOT the sender).
      final chatDoc = await _db.collection('chats').doc(chatId).get();
      if (!chatDoc.exists) return;
      final participants =
          (chatDoc.data()?['participants'] as List?)?.cast<String>() ?? [];
      final recipientId =
          participants.where((id) => id != authorId).firstOrNull;
      if (recipientId == null) return;

      // Fetch the recipient's FCM token.
      final userDoc = await _db.collection('users').doc(recipientId).get();
      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;

      final senderName =
          (await _db.collection('users').doc(authorId).get()).data()?['name']
              as String? ?? 'Someone';

      await PushSender.sendMessagePush(
        recipientFcmToken: token,
        chatId: chatId,
        senderId: authorId,
        senderName: senderName,
        text: text,
      );
    } catch (_) {
      // Ignore — the message is already saved; push is best-effort.
    }
  }

  /// Live count of messages in [chatId] that [myUid] hasn't read yet.
  ///
  /// Powers the blue unread badge on the chat list. Capped at 50 so a very
  /// busy conversation can't inflate the listener payload.
  Stream<int> unreadCountStream(String chatId, String myUid) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs
            .where((doc) => (doc.data()['authorId'] as String?) != myUid)
            .length);
  }

  /// Flags every incoming message in [chatId] as read (called when the user
  /// opens the conversation) so the badge clears and the sender's ticks flip.
  Future<void> markMessagesRead(String chatId, String myUid) async {
    final snap = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('read', isEqualTo: false)
        .limit(300)
        .get();

    final batch = _db.batch();
    var pending = 0;
    for (final doc in snap.docs) {
      if ((doc.data()['authorId'] as String?) == myUid) continue;
      batch.update(doc.reference, {'read': true});
      pending++;
    }
    if (pending > 0) await batch.commit();
  }

  /// Real-time stream of messages for a chat (newest last).
  Stream<List<ChatMessage>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromSnapshot).toList());
  }

  /// Real-time stream of chat summaries the user participates in.
  ///
  /// Sorted client-side so no Firestore composite index is required.
  Stream<List<ChatSummary>> chatsStream(String myUid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(ChatSummary.fromSnapshot).toList();
      list.sort((a, b) {
        final ta = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final tb = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return tb.compareTo(ta);
      });
      return list;
    });
  }
}
