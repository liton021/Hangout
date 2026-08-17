import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/channel.dart';
import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../services/chat_service.dart';
import '../services/image_message_service.dart';
import '../services/push_service.dart';
import '../services/user_service.dart';
import '../services/voice_note_service.dart';

// ---------------------------------------------------------------------------
// App appearance
// ---------------------------------------------------------------------------

/// Appearance is deliberately UI-only: changing it never touches user data or
/// messaging behaviour. The system setting remains the default.
final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
  return ThemeModeController();
});

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _restore();
  }

  static const _key = 'theme_mode';

  Future<void> _restore() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    state = ThemeMode.values.firstWhere(
      (mode) => mode.name == saved,
      orElse: () => ThemeMode.dark,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, mode.name);
  }
}

// ---------------------------------------------------------------------------
// Firebase singletons
// ---------------------------------------------------------------------------

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final userServiceProvider = Provider<UserService>((ref) {
  return UserService(
    ref.watch(firestoreProvider),
    ref.watch(firebaseAuthProvider),
  );
});

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(
    ref.watch(firestoreProvider),
    ref.watch(pushServiceProvider),
  );
});

/// Profile-picture uploads — same Cloudflare Worker as push/tokens.
final avatarServiceProvider = Provider<AvatarService>((ref) {
  return AvatarService(
    idTokenProvider: () async {
      final user = ref.read(authServiceProvider).currentUser;
      try {
        return await user?.getIdToken();
      } catch (_) {
        return null;
      }
    },
  );
});

/// Voice notes — recording plus upload to the same Cloudflare Worker.
final voiceNoteServiceProvider = Provider<VoiceNoteService>((ref) {
  final service = VoiceNoteService(
    idTokenProvider: () async {
      final user = ref.read(authServiceProvider).currentUser;
      try {
        return await user?.getIdToken();
      } catch (_) {
        return null;
      }
    },
  );
  // Release the native recorder when the provider is torn down.
  ref.onDispose(service.dispose);
  return service;
});

/// Chat photos — compression plus upload to the same Cloudflare Worker.
final imageMessageServiceProvider = Provider<ImageMessageService>((ref) {
  return ImageMessageService(
    idTokenProvider: () async {
      final user = ref.read(authServiceProvider).currentUser;
      try {
        return await user?.getIdToken();
      } catch (_) {
        return null;
      }
    },
  );
});

/// FCM-free push: WebSocket to the Cloudflare Worker + local notifications.
final pushServiceProvider = Provider<PushService>((ref) {
  return PushService(
    idTokenProvider: () async {
      final user = ref.read(authServiceProvider).currentUser;
      try {
        return await user?.getIdToken();
      } catch (_) {
        return null;
      }
    },
  );
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

/// Unread message count for a single chat — drives the blue badge on the
/// chat list.
final unreadCountProvider =
    StreamProvider.family<int, String>((ref, chatId) {
  final me = ref.watch(authStateProvider).value;
  if (me == null) return Stream<int>.value(0);
  return ref.watch(chatServiceProvider).unreadCountStream(chatId, me.uid);
});

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// Public channels shown in the Discovery tab. Missing/empty collection is a
/// normal state — the tab renders a placeholder card instead.
final channelsProvider = StreamProvider<List<Channel>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection('channels')
      .limit(20)
      .snapshots()
      .map((snap) => snap.docs.map(Channel.fromSnapshot).toList());
});

