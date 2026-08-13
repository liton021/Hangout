import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A user-friendly exception raised by [AuthService] for auth failures.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _user;
  StreamSubscription<User?>? _authSubscription;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  /// Display name used for chat messages (falls back to the email prefix).
  String get displayName => _user?.email?.split('@').first ?? 'User';

  AuthService() {
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(friendlyAuthMessage(e));
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _createUserDocument(credential.user!);
    } on FirebaseAuthException catch (e) {
      throw AuthException(friendlyAuthMessage(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// Publishes the new user to the `users` collection so other accounts can
  /// see them in the contact list.
  Future<void> _createUserDocument(User user) {
    return _firestore.collection('users').doc(user.uid).set({
      'email': user.email ?? '',
      'displayName': user.email?.split('@').first ?? 'User',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Converts a [FirebaseAuthException] into a message worth showing to the
  /// user, instead of leaking raw error strings.
  static String friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account was found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'The password is too weak — use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'Authentication failed (${e.code}).';
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
