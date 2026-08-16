/// Events pushed over the Hangout signaling WebSocket (see `token_server/`).
///
/// The sender's app POSTs `{event, payload}` to the Cloudflare Worker's
/// `/send` endpoint; the Worker forwards it to the recipient's device over
/// its persistent WebSocket. The recipient then raises a local notification
/// (full-screen intent for calls, heads-up for messages) — no FCM involved.
enum PushEventType {
  callInvite, // 'call_invite'    payload: CallData.toPushMap()
  callCancelled, // 'call_cancelled'  payload: {'callId': ...}
  callRejected, // 'call_rejected'   payload: {'callId': ...}
  newMessage, // 'new_message'     payload: {'chatId','senderId','senderName','text','sentAt'}
  unknown;

  static PushEventType fromServerName(String? name) => switch (name) {
        'call_invite' => PushEventType.callInvite,
        'call_cancelled' => PushEventType.callCancelled,
        'call_rejected' => PushEventType.callRejected,
        'new_message' => PushEventType.newMessage,
        _ => PushEventType.unknown,
      };

  /// Wire name used in requests to `/send`.
  String get serverName => switch (this) {
        PushEventType.callInvite => 'call_invite',
        PushEventType.callCancelled => 'call_cancelled',
        PushEventType.callRejected => 'call_rejected',
        PushEventType.newMessage => 'new_message',
        PushEventType.unknown => 'unknown',
      };
}

/// One event received from (or sent to) the push server.
class PushEvent {
  final PushEventType type;
  final Map<String, dynamic> payload;
  final String fromUid;

  const PushEvent({
    required this.type,
    required this.payload,
    this.fromUid = '',
  });

  /// Parses the `{"type":"push","event":...,"payload":...,"from":...}`
  /// envelope the Worker sends over the WebSocket.
  factory PushEvent.fromServer(Map<String, dynamic> json) {
    final inner = json['type'] == 'push'
        ? json
        : json['event'] != null
            ? json
            : null;
    if (inner == null) {
      return const PushEvent(type: PushEventType.unknown, payload: {});
    }
    return PushEvent(
      type: PushEventType.fromServerName(inner['event'] as String?),
      payload: Map<String, dynamic>.from(
        (inner['payload'] as Map<String, dynamic>?) ?? const {},
      ),
      fromUid: (inner['from'] as String?) ?? '',
    );
  }

  /// JSON envelope stored in a notification's `payload` so taps can
  /// reconstruct the event.
  Map<String, dynamic> toJson() => {
        'event': type.serverName,
        'payload': payload,
        'from': fromUid,
      };
}
