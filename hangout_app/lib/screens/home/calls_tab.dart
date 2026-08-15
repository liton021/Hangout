import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../call/audio_call_screen.dart';
import '../call/video_call_screen.dart';

/// Calls tab — a read-only history of calls the current user took part in
/// (report §4: "Calls: call log & dialer").
///
/// Two Firestore queries (as caller / as callee) are merged client-side and
/// sorted by time, mirroring the chat-list approach (no composite indexes).
class CallsTab extends ConsumerStatefulWidget {
  const CallsTab({super.key});

  @override
  ConsumerState<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends ConsumerState<CallsTab> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _asCaller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _asCallee;

  final Map<String, CallData> _calls = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    if (!mounted) return;
    final uid = ref.read(authStateProvider).value?.uid;
    final db = ref.read(firestoreProvider);
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    _asCaller = db
        .collection('calls')
        .where('callerId', isEqualTo: uid)
        .limit(100)
        .snapshots()
        .listen(_merge, onError: _onError);
    _asCallee = db
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .limit(100)
        .snapshots()
        .listen(_merge, onError: _onError);
  }

  void _merge(QuerySnapshot<Map<String, dynamic>> snap) {
    final map = <String, CallData>{..._calls};
    for (final doc in snap.docs) {
      map[doc.id] = CallData.fromSnapshot(doc);
    }
    final list = map.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!mounted) return;
    setState(() {
      _calls
        ..clear()
        ..addAll({for (final c in list) c.id: c});
      _loading = false;
    });
  }

  void _onError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = '$e';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _asCaller?.cancel();
    _asCallee?.cancel();
    super.dispose();
  }

  Future<void> _callBack(AppUser peer, CallType type) async {
    final me = ref.read(currentAppUserProvider).value;
    if (me == null) return;
    final call = await ref.read(callControllerProvider.notifier).startCall(
          caller: me,
          callee: peer,
          type: type,
        );
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => type == CallType.video
          ? VideoCallScreen(call: call, isCaller: true)
          : AudioCallScreen(call: call, isCaller: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CallsEmpty(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn’t load call history',
        subtitle: _error!,
      );
    }
    if (_calls.isEmpty) {
      return const _CallsEmpty(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        subtitle: 'Your call history will appear here after your first call.',
      );
    }

    final users = ref.watch(usersProvider).value ?? const <AppUser>[];
    final byId = {for (final u in users) u.uid: u};
    final me = ref.read(authStateProvider).value?.uid;
    final calls = _calls.values.toList();

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemCount: calls.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final call = calls[i];
        final outgoing = call.callerId == me;
        final missed = call.status == CallStatus.missed ||
            (call.status == CallStatus.rejected && !outgoing);
        final peerId = outgoing ? call.calleeId : call.callerId;
        final peer = byId[peerId] ??
            AppUser(
              uid: peerId,
              name: outgoing ? call.calleeName : call.callerName,
              email: '',
            );

        return _CallTile(
          call: call,
          peer: peer,
          outgoing: outgoing,
          missed: missed,
          onTap: () => _callBack(peer, CallType.audio),
          onVideo: () => _callBack(peer, CallType.video),
        );
      },
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.call,
    required this.peer,
    required this.outgoing,
    required this.missed,
    required this.onTap,
    required this.onVideo,
  });

  final CallData call;
  final AppUser peer;
  final bool outgoing;
  final bool missed;
  final VoidCallback onTap;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = missed
        ? (Icons.call_missed_rounded, AppColors.danger)
        : outgoing
            ? (Icons.call_made_rounded, AppColors.teal)
            : (Icons.call_received_rounded, AppColors.success);

    final statusLabel = switch (call.status) {
      CallStatus.ringing => 'Ringing',
      CallStatus.ongoing => 'Ongoing',
      CallStatus.ended => 'Ended',
      CallStatus.rejected => outgoing ? 'Rejected' : 'Missed',
      CallStatus.missed => 'Missed',
      CallStatus.cancelled => 'Cancelled',
    };
    final kind = call.type == CallType.video ? 'Video' : 'Audio';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$kind · $statusLabel · ${_formatTime(call.createdAt.toLocal())}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: missed
                            ? AppColors.danger
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: missed ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Video call ${peer.name}',
                onPressed: onVideo,
                icon: const Icon(Icons.videocam_rounded, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.paleMint,
                  foregroundColor: AppColors.teal,
                ),
              ),
              const SizedBox(width: 2),
              IconButton.filledTonal(
                tooltip: 'Call ${peer.name}',
                onPressed: onTap,
                icon: const Icon(Icons.call_rounded, size: 19),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.paleMint,
                  foregroundColor: AppColors.teal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    if (sameDay) return DateFormat.jm().format(date);
    final sameYear = now.year == date.year;
    return sameYear ? DateFormat('MMM d').format(date) : DateFormat('MMM d, y').format(date);
  }
}

class _CallsEmpty extends StatelessWidget {
  const _CallsEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: dark ? AppColors.darkBubbleIn : AppColors.paleMint,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Icon(icon, size: 40, color: AppColors.teal),
            ),
            const SizedBox(height: 22),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: dark ? Colors.white60 : AppColors.sageGray,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
