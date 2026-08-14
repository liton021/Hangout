import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

class FirebaseService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<ChatMessage>> getChatMessages(String userId1, String userId2) {
    String chatId = _getChatId(userId1, userId2);
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ChatMessage.fromMap(doc.data()))
            .toList());
  }

  Future<void> sendMessage({
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    String chatId = _getChatId(senderId, receiverId);
    ChatMessage message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      timestamp: DateTime.now(),
    );

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(message.id)
        .set(message.toMap());
  }

  Future<void> createCallOffer({
    required String callerId,
    required String receiverId,
    required String callType,
    required Map<String, dynamic> offerSdp,
  }) async {
    String callId = DateTime.now().millisecondsSinceEpoch.toString();
    await _firestore.collection('calls').doc(callId).set({
      'id': callId,
      'callerId': callerId,
      'receiverId': receiverId,
      'callType': callType,
      'status': 'ringing',
      'startedAt': DateTime.now().toIso8601String(),
      'offerSdp': offerSdp,
    });
  }

  Future<void> updateCallStatus(String callId, String status) async {
    await _firestore.collection('calls').doc(callId).update({'status': status});
  }

  Future<void> addIceCandidate(String callId, Map<String, dynamic> candidate) async {
    await _firestore
        .collection('calls')
        .doc(callId)
        .collection('iceCandidates')
        .add(candidate);
  }

  Future<void> endCall(String callId) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': 'ended',
      'endedAt': DateTime.now().toIso8601String(),
    });
  }

  String _getChatId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return ids.join('_');
  }
}
