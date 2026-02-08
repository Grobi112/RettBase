import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/email_model.dart';

/// E-Mail-Service – gleiche Firestore-Struktur wie rettbase/module/office/email.js
class EmailService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  Future<List<EmailUser>> loadEmailUsers(String companyId) async {
    final snap = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').get();
    final users = <EmailUser>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (data['active'] == false) continue;

      final email = (data['internalEmail'] ?? data['email'] ?? data['eMail'] ?? '').toString().trim();
      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      final name = [vorname, nachname].where((e) => e.isNotEmpty).join(' ').trim();
      final displayName = name.isNotEmpty ? name : (data['name']?.toString() ?? email);
      final uid = data['uid']?.toString() ?? d.id;

      if (uid.isNotEmpty) {
        users.add(EmailUser(uid: uid, name: displayName, email: email.isNotEmpty ? email : '$uid@$companyId.rettbase.de'));
      }
    }
    return users;
  }

  Future<String> _getSenderName(String companyId) async {
    final user = _auth.currentUser;
    if (user == null) return 'Unbekannt';
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        final v = d['vorname'] ?? '';
        final n = d['nachname'] ?? '';
        if (v.toString().isNotEmpty || n.toString().isNotEmpty) return '${v} ${n}'.trim();
        return d['name']?.toString() ?? '';
      }
    } catch (_) {}
    return user.email?.split('@').first ?? 'Unbekannt';
  }

  Future<String> _getSenderEmail(String companyId) async {
    final user = _auth.currentUser;
    if (user == null) return '';
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('mitarbeiter')
          .where('uid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final d = snap.docs.first.data();
        return (d['internalEmail'] ?? d['email'] ?? d['eMail'] ?? user.email ?? '').toString();
      }
    } catch (_) {}
    return user.email ?? '';
  }

  Stream<List<EmailItem>> streamInbox(String companyId) {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('emails')
        .where('to', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => EmailItem.fromFirestore(d.id, d.data()))
          .where((e) => !e.draft && !e.deleted)
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<EmailItem>> streamSent(String companyId) {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('emails')
        .where('from', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => EmailItem.fromFirestore(d.id, d.data()))
          .where((e) => !e.draft && !e.deleted && (e.isGroupEmail ? e.to == null : e.to != null))
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<EmailItem>> streamDrafts(String companyId) {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('emails')
        .where('from', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => EmailItem.fromFirestore(d.id, d.data()))
          .where((e) => e.draft && !e.deleted)
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<EmailItem>> streamTrash(String companyId) {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('emails')
        .where('deleted', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => EmailItem.fromFirestore(d.id, d.data()))
          .where((e) => e.from == uid || e.to == uid)
          .toList();
      list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Future<void> markAsRead(String companyId, String emailId) async {
    await _db.collection('kunden').doc(companyId).collection('emails').doc(emailId).update({'read': true});
  }

  Future<void> sendEmail(
    String companyId,
    String toUid,
    String toName,
    String toEmail,
    String subject,
    String body,
  ) async {
    final uid = _userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final fromName = await _getSenderName(companyId);
    final fromEmail = await _getSenderEmail(companyId);

    await _db.collection('kunden').doc(companyId).collection('emails').add({
      'from': uid,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'to': toUid,
      'toName': toName,
      'toEmail': toEmail,
      'subject': subject,
      'body': body,
      'read': false,
      'draft': false,
      'deleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveDraft(
    String companyId,
    String? draftId,
    String? toUid,
    String? toName,
    String? toEmail,
    String subject,
    String body,
  ) async {
    final uid = _userId;
    if (uid == null) return;
    if (subject.isEmpty && body.isEmpty && toUid == null) return;

    final fromName = await _getSenderName(companyId);
    final fromEmail = await _getSenderEmail(companyId);

    final data = {
      'from': uid,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'to': toUid,
      'toName': toName,
      'toEmail': toEmail,
      'subject': subject,
      'body': body,
      'draft': true,
      'deleted': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (draftId != null && draftId.isNotEmpty) {
      await _db.collection('kunden').doc(companyId).collection('emails').doc(draftId).set(data, SetOptions(merge: true));
    } else {
      await _db.collection('kunden').doc(companyId).collection('emails').add({...data, 'createdAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> deleteEmail(String companyId, String emailId) async {
    await _db.collection('kunden').doc(companyId).collection('emails').doc(emailId).update({'deleted': true});
  }

  Future<void> deleteDraft(String companyId, String emailId) async {
    await _db.collection('kunden').doc(companyId).collection('emails').doc(emailId).delete();
  }

  // --- Gruppen ---

  Future<List<EmailGroup>> loadGroups(String companyId) async {
    final snap = await _db.collection('kunden').doc(companyId).collection('emailGroups').get();
    return snap.docs.map((d) => EmailGroup.fromFirestore(d.id, d.data())).toList();
  }

  Future<List<GroupMember>> loadGroupMembers(String companyId) async {
    final snap = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').get();
    final members = <GroupMember>[];
    for (final d in snap.docs) {
      final data = d.data();
      if (data['active'] == false) continue;
      final v = data['vorname']?.toString() ?? '';
      final n = data['nachname']?.toString() ?? '';
      final name = [v, n].join(' ').trim();
      final displayName = name.isNotEmpty ? name : (data['name']?.toString() ?? '');
      final email = (data['internalEmail'] ?? data['email'] ?? data['eMail'] ?? '').toString();
      final uid = data['uid']?.toString() ?? d.id;
      members.add(GroupMember(uid: uid, name: displayName.isNotEmpty ? displayName : email, email: email));
    }
    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return members;
  }

  Future<void> createGroup(String companyId, String name, String description, List<GroupMember> members) async {
    final uid = _userId;
    if (uid == null) throw Exception('Nicht angemeldet');
    await _db.collection('kunden').doc(companyId).collection('emailGroups').add({
      'name': name,
      'description': description,
      'members': members.map((m) => {'uid': m.uid, 'name': m.name, 'email': m.email, 'internalEmail': m.email}).toList(),
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendEmailToGroup(
    String companyId,
    EmailGroup group,
    String subject,
    String body,
  ) async {
    final uid = _userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final fromName = await _getSenderName(companyId);
    final fromEmail = await _getSenderEmail(companyId);
    final emailsRef = _db.collection('kunden').doc(companyId).collection('emails');

    final recipientList = <Map<String, dynamic>>[];
    for (final m in group.members) {
      if (m.uid == null || m.uid!.isEmpty) continue;
      recipientList.add({'uid': m.uid, 'name': m.name, 'email': m.email, 'internalEmail': m.email});

      await emailsRef.add({
        'from': uid,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'to': m.uid,
        'toName': m.name,
        'toEmail': m.email,
        'subject': subject,
        'body': body,
        'read': false,
        'draft': false,
        'deleted': false,
        'isGroupEmail': true,
        'groupId': group.id,
        'groupName': group.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await emailsRef.add({
      'from': uid,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'to': null,
      'toName': '[Gruppe: ${group.name}]',
      'toEmail': null,
      'subject': subject,
      'body': body,
      'read': false,
      'draft': false,
      'deleted': false,
      'isGroupEmail': true,
      'groupId': group.id,
      'groupName': group.name,
      'recipients': recipientList,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Externe E-Mails (Cloud Function) ---

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static bool isValidEmail(String s) => _emailRegex.hasMatch(s.trim());

  Future<void> sendExternalEmail(
    String companyId,
    String toEmail,
    String toName,
    String subject,
    String body, {
    String? replyTo,
    String? fromEmailOverride,
    String? fromNameOverride,
  }) async {
    final uid = _userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final fromName = fromNameOverride ?? await _getSenderName(companyId);
    final fromEmail = fromEmailOverride ?? await _getSenderEmail(companyId);

    await _db.collection('kunden').doc(companyId).collection('emails').add({
      'from': uid,
      'fromName': fromName,
      'fromEmail': fromEmail,
      'to': null,
      'toName': toName,
      'toEmail': toEmail,
      'subject': subject,
      'body': body,
      'read': false,
      'draft': false,
      'deleted': false,
      'isExternal': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    final effectiveFromEmail = fromEmail.isNotEmpty ? fromEmail : 'mail@rettbase.de';
    await functions.httpsCallable('sendEmail').call({
      'to': toEmail.trim(),
      'subject': subject,
      'body': body,
      'fromEmail': effectiveFromEmail,
      'fromName': fromName,
      if (replyTo != null) 'replyTo': replyTo,
    });
  }
}
