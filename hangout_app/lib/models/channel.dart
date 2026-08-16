import 'package:cloud_firestore/cloud_firestore.dart';

/// A public channel surfaced in the Discovery tab (`channels/{id}`).
///
/// The collection is optional: when it's empty the Discovery tab shows a
/// friendly placeholder instead of the "Trending Channels" list.
class Channel {
  final String id;
  final String name;
  final int members;
  final int online;
  final String? icon;

  const Channel({
    required this.id,
    required this.name,
    this.members = 0,
    this.online = 0,
    this.icon,
  });

  factory Channel.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Channel(
      id: doc.id,
      name: data['name'] as String? ?? 'Channel',
      members: (data['members'] as num?)?.toInt() ?? 0,
      online: (data['online'] as num?)?.toInt() ?? 0,
      icon: data['icon'] as String?,
    );
  }

  /// "12.4k members · 45 online"
  String get subtitle {
    final memberLabel = members >= 1000
        ? '${(members / 1000).toStringAsFixed(1)}k members'
        : '$members members';
    if (online > 0) return '$memberLabel · $online online';
    return memberLabel;
  }
}
