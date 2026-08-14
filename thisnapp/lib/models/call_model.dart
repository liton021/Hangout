class CallModel {
  final String id;
  final String callerId;
  final String receiverId;
  final String callType; // 'audio' or 'video'
  final String status; // 'ringing', 'accepted', 'rejected', 'ended'
  final DateTime startedAt;
  final DateTime? endedAt;
  final Map<String, dynamic>? offerSdp;
  final Map<String, dynamic>? answerSdp;
  final List<Map<String, dynamic>>? iceCandidates;

  CallModel({
    required this.id,
    required this.callerId,
    required this.receiverId,
    required this.callType,
    this.status = 'ringing',
    required this.startedAt,
    this.endedAt,
    this.offerSdp,
    this.answerSdp,
    this.iceCandidates,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'callerId': callerId,
      'receiverId': receiverId,
      'callType': callType,
      'status': status,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'offerSdp': offerSdp,
      'answerSdp': answerSdp,
      'iceCandidates': iceCandidates,
    };
  }

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      id: map['id'] ?? '',
      callerId: map['callerId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      callType: map['callType'] ?? 'audio',
      status: map['status'] ?? 'ringing',
      startedAt: DateTime.tryParse(map['startedAt'] ?? '') ?? DateTime.now(),
      endedAt: map['endedAt'] != null ? DateTime.tryParse(map['endedAt']!) : null,
      offerSdp: map['offerSdp'],
      answerSdp: map['answerSdp'],
      iceCandidates: map['iceCandidates'] != null
          ? List<Map<String, dynamic>>.from(map['iceCandidates'])
          : null,
    );
  }
}
