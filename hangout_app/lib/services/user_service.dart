import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

/// Reads/writes user profiles in Firestore (`users/{uid}`).
class UserService {
  UserService(this._db, this._auth);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Creates or updates the profile for [user].
  ///
  /// No device/push token needed: push is addressed by user id (each device
  /// connects its own WebSocket to the push server — see [PushService]).
  Future<void> upsert(User user) async {
    final ref = _users.doc(user.uid);
    final existing = await ref.get();
    final data = {
      'name': user.displayName ?? 'User',
      'email': user.email ?? '',
      if (!existing.exists) 'createdAt': DateTime.now(),
    };
    data.removeWhere((_, v) => v == null);
    await ref.set(data, SetOptions(merge: true));
  }

  /// Sets (or clears, when [url] is null) the signed-in user's profile
  /// picture. The image itself lives on the Cloudflare Worker — Firestore
  /// only stores the URL.
  Future<void> setAvatarUrl(String? url) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _users.doc(uid).set(
      {'avatarUrl': url ?? FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Future<AppUser?> getById(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(uid, doc.data()!);
  }

  /// All users (used for the contacts list). Replace with pagination at scale.
  Future<List<AppUser>> getAll({String? excludeUid}) async {
    final snap = await _users.orderBy('name').get();
    return snap.docs
        .map((d) => AppUser.fromMap(d.id, d.data()))
        .where((u) => u.uid != excludeUid)
        .toList();
  }
}
