import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/call_data.dart';
import '../models/push_event.dart';
import '../services/push_service.dart';
import 'providers.dart';

/// State of the call signaling controller.
class CallControllerState {
  /// The ringing call currently directed at me (null if none).
  final CallData? incomingCall;

  const CallControllerState({this.incomingCall});

  CallControllerState copyWith({CallData? incomingCall}) => CallControllerState(
        incomingCall: incomingCall ?? this.incomingCall,
      );
}

/// Manages call signaling over Firestore, with FCM-free push wake-ups
/// delivered through [PushService] (WebSocket to the Cloudflare Worker).
///
/// In-app flow (both parties have the app open):
///   1. Caller calls [startCall] -> creates a `calls/{id}` doc (status=ringing)
///      AND pushes a `call_invite` event to the callee's device.
///   2. Callee's [init] subscription sees the ringing call -> [incomingCall].
///      (The push event is what wakes the callee when the app is in the
///      background — the app raises a full-screen-intent notification.)
///   3. Callee accepts -> doc status=ongoing; both join the Agora channel.
///   4. Either side ends -> doc status=ended.
class CallController extends StateNotifier<CallControllerState> {
  CallController(this._db, this._push) : super(const CallControllerState());

  final FirebaseFirestore _db;
  final PushService _push;
  StreamSubscription? _sub;
  String? _myUid;

  CollectionReference<Map<String, dynamic>> get _calls =>
      _db.collection('calls');

  /// Starts listening for incoming ringing calls directed at [myUid].
  void init(String myUid) {
    if (_myUid == myUid) return;
    _myUid = myUid;
    _sub?.cancel();

    _sub = _calls
        .where('calleeId', isEqualTo: myUid)
        .where('status', isEqualTo: CallStatus.ringing.name)
        .snapshots()
        .listen((snap) {
      final ringing = snap.docs.map(CallData.fromSnapshot).toList();
      if (ringing.isEmpty) {
        if (state.incomingCall != null) {
          state = const CallControllerState();
        }
        return;
      }
      ringing.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(incomingCall: ringing.first);
    });
  }

  /// Caller initiates a call. Returns the created [CallData].
  Future<CallData> startCall({
    required AppUser caller,
    required AppUser callee,
    required CallType type,
  }) async {
    final ref = _calls.doc();
    final channelName =
        'hangout_${caller.uid.hashCode}_${callee.uid.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
    final call = CallData(
      id: ref.id,
      callerId: caller.uid,
      callerName: caller.name,
      calleeId: callee.uid,
      calleeName: callee.name,
      channelName: channelName,
      type: type,
      status: CallStatus.ringing,
      createdAt: DateTime.now(),
    );
    await ref.set(call.toMap());

    // Wake the callee: push a call-invite event to their device (FCM-free).
    // Best-effort — in-app signaling still works over Firestore alone.
    await _push.send(
      toUid: callee.uid,
      type: PushEventType.callInvite,
      payload: call.toPushMap(),
    );
    return call;
  }

  /// Callee accepts the incoming call.
  Future<CallData?> accept() async {
    final call = state.incomingCall;
    if (call == null) return null;
    await _calls.doc(call.id).set(
          {'status': CallStatus.ongoing.name},
          SetOptions(merge: true),
        );
    state = const CallControllerState();
    return call.copyWith(status: CallStatus.ongoing);
  }

  /// Callee rejects the incoming call.
  Future<void> reject() async {
    final call = state.incomingCall;
    if (call == null) return;
    await _calls.doc(call.id).set(
          {'status': CallStatus.rejected.name},
          SetOptions(merge: true),
        );
    state = const CallControllerState();

    // Let the caller's device know so any ringing UI can stop immediately.
    await _push.send(
      toUid: call.callerId,
      type: PushEventType.callRejected,
      payload: {'callId': call.id},
    );
  }

  /// Caller cancels a call that is still ringing.
  Future<void> cancel(CallData call) async {
    await _calls.doc(call.id).set(
          {'status': CallStatus.cancelled.name},
          SetOptions(merge: true),
    );

    // Dismiss the callee's full-screen ringing notification (if any).
    await _push.send(
      toUid: call.calleeId,
      type: PushEventType.callCancelled,
      payload: {'callId': call.id},
    );
  }

  /// Handles a `call_invite` push event arriving over the WebSocket —
  /// the fastest path for a ringing call directed at us (usually the
  /// Firestore watch in [init] also picks it up moments later; duplicate
  /// presentations are deduped by call id in the UI).
  void handleRemoteInvite(PushEvent event) {
    final payload = event.payload;
    if ((payload['calleeId'] as String?) != _myUid) return;
    if (payload['callId'] is! String) return;
    final call = CallData.fromPushMap(payload);
    if (state.incomingCall?.id == call.id) return;
    state = state.copyWith(incomingCall: call);
  }

  /// Accepts a ringing call by id (used by the notification's Accept
  /// action, e.g. when the app was killed). Returns the accepted call,
  /// or null when the call no longer exists / is no longer ringing.
  Future<CallData?> acceptRemote(String callId) async {
    final doc = await _calls.doc(callId).get();
    if (!doc.exists) return null;
    final call = CallData.fromSnapshot(doc);
    if (call.status != CallStatus.ringing) return null;
    await _calls.doc(callId).set(
          {'status': CallStatus.ongoing.name},
          SetOptions(merge: true),
        );
    return call.copyWith(status: CallStatus.ongoing);
  }

  /// Rejects a ringing call by id (used by the notification's Decline
  /// action when the app was killed).
  Future<void> rejectRemote(String callId) async {
    final doc = await _calls.doc(callId).get();
    if (!doc.exists) return;
    if (CallStatus.fromName(doc.data()?['status']) == CallStatus.ringing) {
      await _calls.doc(callId).set(
            {'status': CallStatus.rejected.name},
            SetOptions(merge: true),
          );
    }
  }

  /// Marks a call as ended.
  Future<void> end(CallData call) async {
    await _calls.doc(call.id).set(
          {'status': CallStatus.ended.name},
          SetOptions(merge: true),
    );

    // If the caller hung up while it was still ringing, dismiss the
    // callee's full-screen ringing notification too (harmless otherwise —
    // cancelling a notification that isn't showing is a no-op).
    await _push.send(
      toUid: call.calleeId,
      type: PushEventType.callCancelled,
      payload: {'callId': call.id},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final callControllerProvider =
    StateNotifierProvider<CallController, CallControllerState>((ref) {
  return CallController(
    ref.watch(firestoreProvider),
    ref.watch(pushServiceProvider),
  );
});
