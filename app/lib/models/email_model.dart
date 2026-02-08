import 'package:cloud_firestore/cloud_firestore.dart';

class EmailItem {
  final String id;
  final String from;
  final String? to;
  final String fromName;
  final String fromEmail;
  final String? toName;
  final String? toEmail;
  final String subject;
  final String body;
  final bool read;
  final bool draft;
  final bool deleted;
  final DateTime? createdAt;
  final bool isGroupEmail;
  final String? groupId;
  final String? groupName;
  final bool isExternal;

  EmailItem({
    required this.id,
    required this.from,
    this.to,
    required this.fromName,
    required this.fromEmail,
    this.toName,
    this.toEmail,
    required this.subject,
    required this.body,
    this.read = false,
    this.draft = false,
    this.deleted = false,
    this.createdAt,
    this.isGroupEmail = false,
    this.groupId,
    this.groupName,
    this.isExternal = false,
  });

  factory EmailItem.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime? createdAt;
    final ca = d['createdAt'];
    if (ca is Timestamp) createdAt = ca.toDate();
    if (ca is DateTime) createdAt = ca;

    return EmailItem(
      id: id,
      from: d['from']?.toString() ?? '',
      to: d['to']?.toString(),
      fromName: d['fromName']?.toString() ?? '',
      fromEmail: d['fromEmail']?.toString() ?? '',
      toName: d['toName']?.toString(),
      toEmail: d['toEmail']?.toString(),
      subject: d['subject']?.toString() ?? '',
      body: d['body']?.toString() ?? '',
      read: d['read'] == true,
      draft: d['draft'] == true,
      deleted: d['deleted'] == true,
      createdAt: createdAt,
      isGroupEmail: d['isGroupEmail'] == true,
      groupId: d['groupId']?.toString(),
      groupName: d['groupName']?.toString(),
      isExternal: d['isExternal'] == true,
    );
  }
}

class EmailUser {
  final String uid;
  final String name;
  final String email;

  EmailUser({required this.uid, required this.name, required this.email});
}

class GroupMember {
  final String? uid;
  final String name;
  final String email;

  GroupMember({this.uid, required this.name, required this.email});

  Map<String, dynamic> toMap() => {'uid': uid, 'name': name, 'email': email};
}

class EmailGroup {
  final String id;
  final String name;
  final String? description;
  final List<GroupMember> members;

  EmailGroup({required this.id, required this.name, this.description, required this.members});

  factory EmailGroup.fromFirestore(String id, Map<String, dynamic> d) {
    final membersRaw = d['members'] as List? ?? [];
    final members = membersRaw.map((m) {
      if (m is Map) {
        final v = m['vorname']?.toString() ?? '';
        final n = m['nachname']?.toString() ?? '';
        final name = [v, n].join(' ').trim();
        final displayName = (m['name'] ?? name).toString();
        final email = (m['internalEmail'] ?? m['email'] ?? '').toString();
        return GroupMember(
          uid: m['uid']?.toString(),
          name: displayName.isNotEmpty ? displayName : email,
          email: email,
        );
      }
      return null;
    }).whereType<GroupMember>().toList();
    return EmailGroup(
      id: id,
      name: d['name']?.toString() ?? '',
      description: d['description']?.toString(),
      members: members,
    );
  }
}
