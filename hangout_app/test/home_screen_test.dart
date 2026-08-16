import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hangout/models/app_user.dart';
import 'package:hangout/models/chat_summary.dart';
import 'package:hangout/providers/providers.dart';
import 'package:hangout/screens/home/home_screen.dart';

// ---------------------------------------------------------------------------
// Minimal Firestore fake: returns empty query streams so the real widget
// tree (HomeScreen → CallsTab / _ChatsTab / _ContactsTab / SettingsScreen)
// can be pumped without any platform channels.
// ---------------------------------------------------------------------------

class _FakeQuerySnapshot extends Fake
    implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => const [];
}

class _FakeQuery extends Fake implements Query<Map<String, dynamic>> {
  @override
  Query<Map<String, dynamic>> limit(int n) => this;

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
  }) =>
      const Stream.empty();

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async =>
      _FakeQuerySnapshot();
}

class _FakeCollectionReference extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) =>
      _FakeQuery();
}

class _FakeFirestore extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCollectionReference();
}

void main() {
  final alice =
      const AppUser(uid: 'u1', name: 'Alice', email: 'alice@example.com');
  final chat = ChatSummary(
    chatId: 'c1',
    participants: const ['me', 'u1'],
    lastMessage: 'Hey!',
    lastMessageAt: DateTime.now(),
  );

  ProviderScope buildApp() {
    return ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(_FakeFirestore()),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        usersProvider.overrideWith((ref) => Future.value([alice])),
        currentAppUserProvider.overrideWith((ref) => Stream.value(alice)),
        chatsProvider.overrideWith((ref) => Stream.value([chat])),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('HomeScreen renders chats and all four tabs without errors',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(buildApp());
    await tester.pump(); // first frame
    await tester.pump(); // post-frame callbacks (calls tab subscription)

    // No layout/render exception on first build.
    expect(tester.takeException(), isNull,
        reason: 'HomeScreen threw while building');

    // Chats tab shows the chat row (peer name + preview).
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Hey!'), findsOneWidget);

    // Regression: the nav capsule must hug the bottom of the screen. A bare
    // Center inside Scaffold.bottomNavigationBar expands to the full screen
    // height, centering the capsule vertically and crushing the body to zero
    // height (so tabs render nothing).
    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    final capsuleCenter =
        tester.getCenter(find.byIcon(Icons.chat_bubble_outline_rounded));
    expect(capsuleCenter.dy, greaterThan(screenHeight * 0.7),
        reason: 'nav capsule must sit at the bottom, not mid-screen');
    expect(capsuleCenter.dy, lessThan(screenHeight * 0.95),
        reason: 'nav capsule must stay clear of the very edge');

    // Floating capsule nav bar is present with all 4 destinations.
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.people_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    // Switch to Contacts.
    await tester.tap(find.byIcon(Icons.people_outline_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Contacts tab threw while building');
    expect(find.text('Alice'), findsWidgets);

    // Switch to Calls.
    await tester.tap(find.byIcon(Icons.call_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Calls tab threw while building');

    // Switch to Settings.
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Settings tab threw while building');

    // Flush the permission-denied SnackBar timer before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('empty chats state with "Start a chat" renders and opens sheet',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(_FakeFirestore()),
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        usersProvider.overrideWith((ref) => Future.value([alice])),
        currentAppUserProvider.overrideWith((ref) => Stream.value(alice)),
        chatsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Your chats live here'), findsOneWidget);
    expect(find.text('Start a chat'), findsOneWidget);

    await tester.tap(find.text('Start a chat'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'New-chat sheet threw while building');
    expect(find.text('New chat'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });
}
