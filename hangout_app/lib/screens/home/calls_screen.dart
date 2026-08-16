import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/app_user.dart';
import '../../models/call_data.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/contact_actions.dart';
import '../../widgets/avatar.dart';
import '../../widgets/states.dart';

/// Call history — every voice/video call the signed-in user took part in.
///
/// Two Firestore queries (as caller / as callee) are merged client-side and
/// sorted by time, mirroring the chat-list approach (no composite indexes).
class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingState();
    if (_error != null) {
      return ErrorStateView(message: _error!);
    }
    if (_calls.isEmpty) {
      return const EmptyState(
        icon: Icons.call_outlined,
        title: 'No calls yet',
        subtitle: 'Your call history appears here after your first call.',
      );
    }

    final users = ref.watch(usersProvider).value ?? const <AppUser>[];
    final byId = {for (final u in users) u.uid: u};
    final me = ref.read(authStateProvider).value?.uid;
    final calls = _calls.values.toList();

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 28),
      itemCount: calls.length,
      separatorBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(left: 84, right: 20),
        child: Divider(height: 1, color: context.colors.divider),
      ),
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

        return _CallRow(
          call: call,
          peer: peer,
          outgoing: outgoing,
          missed: missed,
        );
      },
    );
  }
}

class _CallRow extends ConsumerWidget {
  const _CallRow({
    required this.call,
    required this.peer,
    required this.outgoing,
    required this.missed,
  });

  final CallData call;
  final AppUser peer;
  final bool outgoing;
  final bool missed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.colors;
    final (icon, color) = missed
        ? (Icons.call_missed_rounded, AppColors.danger)
        : outgoing
            ? (Icons.call_made_rounded, AppColors.accent)
            : (Icons.call_received_rounded, AppColors.success);

    final statusLabel = switch (call.status) {
      CallStatus.ringing => 'Ringing',
      CallStatus.ongoing => 'Ongoing',
      CallStatus.ended => 'Ended',
      CallStatus.rejected => outgoing ? 'Rejected' : 'Missed',
      CallStatus.missed => 'Missed',
      CallStatus.cancelled => 'Cancelled',
    };
    final kind = call.type == CallType.video ? 'Video' : 'Voice';

    return InkWell(
      onTap: () =>
          ContactActions.startCall(context, ref, peer, CallType.audio),
      onLongPress: () => ContactActions.showQuickActions(context, ref, peer),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        child: Row(
          children: [
            UserAvatar(user: peer, radius: 26),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: missed ? AppColors.danger : palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(icon, size: 15, color: color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '$kind · $statusLabel · '
                          '${_formatTime(call.createdAt.toLocal())}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Video call ${peer.name}',
              onPressed: () =>
                  ContactActions.startCall(context, ref, peer, CallType.video),
              icon: const Icon(Icons.videocam_rounded,
                  size: 22, color: AppColors.accent),
            ),
            IconButton(
              tooltip: 'Call ${peer.name}',
              onPressed: () =>
                  ContactActions.startCall(context, ref, peer, CallType.audio),
              icon: const Icon(Icons.call_rounded,
                  size: 20, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final sameDay =
        now.year == date.year && now.month == date.month && now.day == date.day;
    if (sameDay) return DateFormat.Hm().format(date);
    return now.year == date.year
        ? DateFormat('MMM d').format(date)
        : DateFormat('MMM d, y').format(date);
  }
}
