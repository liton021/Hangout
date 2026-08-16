import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/call_data.dart';
import '../services/push_sender.dart';
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

/// Manages call signaling over Firestore.
///
/// In-app flow (both parties have the app open):
///   1. Caller calls [startCall] -> creates a `calls/{id}` doc (status=ringing).
///   2. Callee's [init] subscription sees the ringing call -> [incomingCall].
///   3. Callee accepts -> doc status=ongoing; both join the Agora channel.
///   4. Either side ends -> doc status=ended.
///
/// NOTE: waking a *closed* app for an incoming call requires FCM + a
/// full-screen-intent notification (documented in the README as a follow-up).
class CallController extends StateNotifier<CallControllerState> {
  CallController(this._db) : super(const CallControllerState());

  final FirebaseFirestore _db;
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
    _sendCallPush(call, callee);
    return call;
  }

  /// Fires the FCM push to the callee via the free Cloudflare Worker so the
  /// incoming call rings even when the callee's app is killed/backgrounded.
  /// Runs fire-and-forget — the Firestore signaling still works without it.
  Future<void> _sendCallPush(CallData call, AppUser callee) async {
    try {
      // Fetch the callee's FCM token from their user doc.
      final userDoc = await _db.collection('users').doc(callee.uid).get();
      final token = userDoc.data()?['fcmToken'] as String?;
      if (token == null || token.isEmpty) return;

      await PushSender.sendCallPush(
        calleeFcmToken: token,
        callId: call.id,
        channelName: call.channelName,
        callerId: call.callerId,
        callerName: call.callerName,
        isVideo: call.type == CallType.video,
      );
    } catch (_) {
      // Ignore — the in-app Firestore signaling still works.
    }
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
  }

  /// Caller cancels a call that is still ringing.
  Future<void> cancel(CallData call) async {
    await _calls.doc(call.id).set(
          {'status': CallStatus.cancelled.name},
          SetOptions(merge: true),
        );
  }

  /// Marks a call as ended.
  Future<void> end(CallData call) async {
    await _calls.doc(call.id).set(
          {'status': CallStatus.ended.name},
          SetOptions(merge: true),
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
  return CallController(ref.watch(firestoreProvider));
});
