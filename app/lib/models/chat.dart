import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String id;
  final String type; // 'direct' | 'group'
  final String? name;
  final List<String> participants;
  final List<ParticipantName> participantNames;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final String? lastMessageFrom;
  final Map<String, int> unreadCount;
  final Map<String, dynamic> lastReadAt;
  final List<String> deletedBy;

  ChatModel({
    required this.id,
    required this.type,
    this.name,
    required this.participants,
    this.participantNames = const [],
    this.lastMessageText,
    this.lastMessageAt,
    this.lastMessageFrom,
    this.unreadCount = const {},
    this.lastReadAt = const {},
    this.deletedBy = const [],
  });

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
    DateTime? lastAt;
    final lma = d['lastMessageAt'];
    if (lma is Timestamp) lastAt = lma.toDate();
    if (lma is DateTime) lastAt = lma;

    return ChatModel(
      id: id,
      type: d['type']?.toString() ?? 'direct',
      name: d['name']?.toString(),
      participants: participants,
      participantNames: pn,
      lastMessageText: d['lastMessageText']?.toString(),
      lastMessageAt: lastAt,
      lastMessageFrom: d['lastMessageFrom']?.toString(),
      unreadCount: unreadMap,
      lastReadAt: Map<String, dynamic>.from(lastRead),
      deletedBy: deletedBy,
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
  final List<String> readBy;
  final List<String> deletedBy;

  ChatMessage({
    required this.id,
    required this.from,
    this.senderName,
    this.text,
    this.attachments,
    this.createdAt,
    this.readBy = const [],
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
    final readBy = (d['readBy'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final deletedBy = (d['deletedBy'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return ChatMessage(
      id: id,
      from: d['from']?.toString() ?? '',
      senderName: d['senderName']?.toString(),
      text: d['text']?.toString(),
      attachments: att,
      createdAt: createdAt,
      readBy: readBy,
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
