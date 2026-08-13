import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUser = authService.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hangout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _demoUsers.length,
        itemBuilder: (context, index) {
          final user = _demoUsers[index];
          if (user['id'] == currentUser?.uid) return const SizedBox.shrink();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(user['name'][0]),
            ),
            title: Text(user['name']),
            subtitle: Text(user['email']),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.green),
                  onPressed: () {
                    _startCall(context, user['id'], user['name'], isVideo: false);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.blue),
                  onPressed: () {
                    _startCall(context, user['id'], user['name'], isVideo: true);
                  },
                ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otherUserId: user['id'],
                    otherUserName: user['name'],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add contact feature coming soon')),
          );
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }

  void _startCall(BuildContext context, String userId, String userName, {required bool isVideo}) async {
    final callService = context.read<CallService>();
    await callService.initializeEngine(videoCall: isVideo);
    await callService.joinChannel('call_$userId');

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isVideo ? const VideoCallScreen() : const AudioCallScreen(),
      ),
    );
  }

  static const List<Map<String, String>> _demoUsers = [
    {'id': 'user1', 'name': 'Alice Johnson', 'email': 'alice@example.com'},
    {'id': 'user2', 'name': 'Bob Smith', 'email': 'bob@example.com'},
    {'id': 'user3', 'name': 'Charlie Brown', 'email': 'charlie@example.com'},
    {'id': 'user4', 'name': 'Diana Prince', 'email': 'diana@example.com'},
  ];
}
