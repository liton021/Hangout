import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/push_service.dart';
import '../services/user_service.dart';

// ---------------------------------------------------------------------------
// Firebase singletons
// ---------------------------------------------------------------------------

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final messagingProvider = Provider<FirebaseMessaging>((ref) {
  return FirebaseMessaging.instance;
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final userServiceProvider = Provider<UserService>((ref) {
  return UserService(ref.watch(firestoreProvider));
});

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(ref.watch(firestoreProvider));
});

final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(ref.watch(messagingProvider));
});

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

/// Stream of the signed-in Firebase user (or null).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

/// The signed-in user's profile document (stream).
final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream<AppUser?>.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((doc) =>
          doc.exists ? AppUser.fromMap(doc.id, doc.data()!) : null);
});

/// All users, for the contacts tab (excludes the current user).
final usersProvider = FutureProvider<List<AppUser>>((ref) async {
  final me = ref.watch(authStateProvider).value;
  return ref.watch(userServiceProvider).getAll(excludeUid: me?.uid);
});

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

/// Chat-list summaries for the current user.
final chatsProvider = StreamProvider<List<ChatSummary>>((ref) {
  final me = ref.watch(authStateProvider).value;
  if (me == null) return Stream<List<ChatSummary>>.value(const []);
  return ref.watch(chatServiceProvider).chatsStream(me.uid);
});

/// Messages of a single chat.
final messagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, chatId) {
  return ref.watch(chatServiceProvider).messagesStream(chatId);
});
