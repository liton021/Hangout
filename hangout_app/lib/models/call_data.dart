import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { audio, video }

enum CallStatus {
  ringing,
  ongoing,
  ended,
  rejected,
  missed,
  cancelled;

  static CallStatus fromName(String? s) => CallStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => CallStatus.ringing,
      );
}

/// A call session stored in Firestore (`calls/{id}`) for signaling.
class CallData {
  final String id;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final String channelName;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;

  const CallData({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.channelName,
    required this.type,
    required this.status,
    required this.createdAt,
  });

  CallData copyWith({CallStatus? status}) => CallData(
        id: id,
        callerId: callerId,
        callerName: callerName,
        calleeId: calleeId,
        calleeName: calleeName,
        channelName: channelName,
        type: type,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  factory CallData.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data()! as Map<String, dynamic>;
    return CallData(
      id: doc.id,
      callerId: data['callerId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? 'User',
      calleeId: data['calleeId'] as String? ?? '',
      calleeName: data['calleeName'] as String? ?? 'User',
      channelName: data['channelName'] as String? ?? doc.id,
      type: data['type'] == 'video' ? CallType.video : CallType.audio,
      status: CallStatus.fromName(data['status'] as String?),
      createdAt: (data['createdAt'] as dynamic).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'callerId': callerId,
        'callerName': callerName,
        'calleeId': calleeId,
        'calleeName': calleeName,
        'channelName': channelName,
        'type': type == CallType.video ? 'video' : 'audio',
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
