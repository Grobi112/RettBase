import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String id;
  final String type; // 'direct' | 'group'
  final String? name;
  final String? groupImageUrl;
  final String? groupDescription;
  final List<String> participants;
  final List<ParticipantName> participantNames;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageFrom;
  final Map<String, int> unreadCount;
  final Map<String, dynamic> lastReadAt;
  final List<String> deletedBy;
  final List<String> leftBy;
  final Map<String, DateTime> leftAt;

  ChatModel({
    required this.id,
    required this.type,
    this.name,
    this.groupImageUrl,
    this.groupDescription,
    required this.participants,
    this.participantNames = const [],
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageFrom,
    this.unreadCount = const {},
    this.lastReadAt = const {},
    this.deletedBy = const [],
    this.leftBy = const [],
    this.leftAt = const {},
  });

  ChatModel copyWith({
    List<String>? leftBy,
    Map<String, DateTime>? leftAt,
    List<String>? participants,
    List<ParticipantName>? participantNames,
  }) {
    return ChatModel(
      id: id,
      type: type,
      name: name,
      groupImageUrl: groupImageUrl,
      groupDescription: groupDescription,
      participants: participants ?? this.participants,
      participantNames: participantNames ?? this.participantNames,
      lastMessageText: lastMessageText,
      lastMessageAt: lastMessageAt,
      lastMessageFrom: lastMessageFrom,
      unreadCount: unreadCount,
      lastReadAt: lastReadAt,
      deletedBy: deletedBy,
      leftBy: leftBy ?? this.leftBy,
      leftAt: leftAt ?? this.leftAt,
    );
  }

  factory ChatModel.fromFirestore(String id, Map<String, dynamic> d) {
    final participants = (d['participants'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final pn = (d['participantNames'] as List?)?.map((e) {
      final m = e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{};
      return ParticipantName(uid: m['uid']?.toString() ?? '', name: m['name']?.toString() ?? '');
    }).toList() ?? [];

    final unread = d['unreadCount'];
    final Map<String, int> unreadMap = {};
    if (unread is Map) {
      for (final e in (unread as Map).entries) {
        final v = e.value;
        if (v is int) unreadMap[e.key.toString()] = v;
      }
    }

    final lastRead = d['lastReadAt'] as Map<String, dynamic>? ?? {};
    final deletedBy = (d['deletedBy'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final leftBy = (d['leftBy'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final leftAtRaw = d['leftAt'] as Map<String, dynamic>? ?? {};
    final leftAt = <String, DateTime>{};
    for (final e in leftAtRaw.entries) {
      final v = e.value;
      DateTime? dt;
      if (v is Timestamp) dt = v.toDate();
      if (v is DateTime) dt = v;
      if (dt != null) leftAt[e.key] = dt;
    }

    DateTime? lastAt;
    final lma = d['lastMessageAt'];
    if (lma is Timestamp) lastAt = lma.toDate();
    if (lma is DateTime) lastAt = lma;

    return ChatModel(
      id: id,
      type: d['type']?.toString() ?? 'direct',
      name: d['name']?.toString(),
      groupImageUrl: d['groupImageUrl']?.toString(),
      groupDescription: d['groupDescription']?.toString(),
      participants: participants,
      participantNames: pn,
      lastMessageText: d['lastMessageText']?.toString(),
      lastMessageAt: lastAt,
      lastMessageFrom: d['lastMessageFrom']?.toString(),
      unreadCount: unreadMap,
      lastReadAt: Map<String, dynamic>.from(lastRead),
      deletedBy: deletedBy,
      leftBy: leftBy,
      leftAt: leftAt,
    );
  }
}

class ParticipantName {
  final String uid;
  final String name;
  ParticipantName({required this.uid, required this.name});
}

class ChatMessage {
  final String id;
  final String from;
  final String? senderName;
  final String? text;
  final List<MessageAttachment>? attachments;
  final DateTime? createdAt;
  final List<String> deliveredTo;
  // BUG FIX 4: readBy entfernt – wurde im Service nie befüllt und ist inkonsistent
  // mit dem Chat-Dokument-basierten lastReadAt/unreadCount-Ansatz. Gelesen-Status
  // wird ausschließlich über lastReadAt im Chat-Dokument abgebildet.
  final List<String> deletedBy;

  ChatMessage({
    required this.id,
    required this.from,
    this.senderName,
    this.text,
    this.attachments,
    this.createdAt,
    this.deliveredTo = const [],
    this.deletedBy = const [],
  });

  factory ChatMessage.fromFirestore(String id, Map<String, dynamic> d) {
    final att = (d['attachments'] as List?)?.map((a) {
      final m = a is Map ? Map<String, dynamic>.from(a as Map) : <String, dynamic>{};
      return MessageAttachment(
        url: m['url']?.toString() ?? '',
        name: m['name']?.toString() ?? '',
        type: m['type']?.toString() ?? '',
        duration: (m['duration'] as num?)?.toDouble(),
      );
    }).toList();

    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    final deliveredTo = (d['deliveredTo'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final deletedBy = (d['deletedBy'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return ChatMessage(
      id: id,
      from: d['from']?.toString() ?? '',
      senderName: d['senderName']?.toString(),
      text: d['text']?.toString(),
      attachments: att,
      createdAt: createdAt,
      deliveredTo: deliveredTo,
      deletedBy: deletedBy,
    );
  }
}

class MessageAttachment {
  final String url;
  final String name;
  final String type;
  final double? duration;
  MessageAttachment({required this.url, required this.name, required this.type, this.duration});
}

class MitarbeiterForChat {
  final String uid;
  final String docId;
  final String vorname;
  final String nachname;
  final String name;
  final String email;

  MitarbeiterForChat({
    required this.uid,
    required this.docId,
    required this.vorname,
    required this.nachname,
    required this.name,
    required this.email,
  });
}
