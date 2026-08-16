import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hangout/models/app_user.dart';
import 'package:hangout/models/chat_message.dart';
import 'package:hangout/providers/providers.dart';
import 'package:hangout/screens/chat/chat_screen.dart';

void main() {
  final alice =
      const AppUser(uid: 'u1', name: 'Alice', email: 'alice@example.com');
  final message = ChatMessage(
    id: 'm1',
    chatId: 'c1',
    authorId: 'u1',
    text: 'Hey there!',
    sentAt: DateTime.now(),
  );

  testWidgets('ChatScreen renders messages and composer without errors',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(null)),
        messagesProvider.overrideWith((ref, chatId) => Stream.value([message])),
      ],
      child: const MaterialApp(
        home: ChatScreen(peer: alice, chatId: 'c1'),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'ChatScreen threw while building');

    // Message bubble + peer name visible.
    expect(find.text('Hey there!'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    // Focus the composer: pill should morph without exceptions.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'Composer threw while focused');

    // Type + send is not exercised here (needs Firestore), but the send
    // button state should update without exceptions.
    await tester.enterText(find.byType(TextField), 'Hello!');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
