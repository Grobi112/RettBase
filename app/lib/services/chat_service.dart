import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/chat.dart';

/// Chat-Service – gleiche Logik wie rettbase/module/chat/chat.js
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static String getDirectChatId(String u1, String u2) {
    final a = [u1, u2]..sort();
    return 'direct_${a[0]}_${a[1]}';
  }

  String? get userId => _auth.currentUser?.uid;

  Future<List<MitarbeiterForChat>> loadMitarbeiter(String companyId) async {
    final uid = userId;
    if (uid == null) return [];

    final usersSnap = await _db.collection('kunden').doc(companyId).collection('users').get();
    final emailToUid = <String, String>{};
    for (final u in usersSnap.docs) {
      final em = (u.data()['email'] ?? '').toString().toLowerCase().trim();
      if (em.isNotEmpty) emailToUid[em] = u.id;
    }

    final mitarbeiterSnap = await _db.collection('kunden').doc(companyId).collection('mitarbeiter').get();
    final list = <MitarbeiterForChat>[];
    for (final d in mitarbeiterSnap.docs) {
      final data = d.data();
      if (data['active'] == false) continue;
      final email = (data['email'] ?? data['eMail'] ?? '').toString().trim();
      var uid = (emailToUid[email.toLowerCase()] ?? data['uid']?.toString() ?? d.id).toString();
      if (uid.isEmpty) uid = d.id;
      if (uid == this.userId) continue;

      final vorname = data['vorname']?.toString() ?? '';
      final nachname = data['nachname']?.toString() ?? '';
      final namePart = [vorname, nachname].where((e) => e.isNotEmpty).join(' ').trim();
      final name = namePart.isNotEmpty ? namePart : (data['name']?.toString() ?? email);
      if (_isExternPlaceholder(name)) continue;

      list.add(MitarbeiterForChat(
        uid: uid,
        docId: d.id,
        vorname: vorname,
        nachname: nachname,
        name: name,
        email: email,
      ));
    }
    return list;
  }

  bool _isExternPlaceholder(String? name) {
    if (name == null || name.isEmpty) return false;
    return RegExp(r'^Extern(\s+\d+)?$', caseSensitive: false).hasMatch(name.trim());
  }

  Stream<List<ChatModel>> streamChats(String companyId) {
    final uid = userId;
    if (uid == null) return Stream.value([]);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => ChatModel.fromFirestore(d.id, d.data()))
          .where((c) => !c.deletedBy.contains(uid))
          .toList();
      list.sort((a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<ChatMessage>> streamMessages(String companyId, String chatId) {
    final uid = userId;
    if (uid == null) return Stream.value([]);

    _markChatRead(companyId, chatId, uid);

    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(100)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((d) => ChatMessage.fromFirestore(d.id, d.data()))
          .where((m) => !m.deletedBy.contains(uid))
          .toList();
    });
  }

  Future<void> _markChatRead(String companyId, String chatId, String userId) async {
    try {
      await _db
          .collection('kunden')
          .doc(companyId)
          .collection('chats')
          .doc(chatId)
          .update({
        'lastReadAt.$userId': FieldValue.serverTimestamp(),
        'unreadCount.$userId': 0,
      });
    } catch (_) {}
  }

  Future<void> startDirectChat(String companyId, MitarbeiterForChat mitarbeiter) async {
    final uid = userId;
    if (uid == null) return;

    final chatId = getDirectChatId(uid, mitarbeiter.uid);
    final ref = _db.collection('kunden').doc(companyId).collection('chats').doc(chatId);
    final snap = await ref.get();
    if (!snap.exists) {
      final senderName = await _getSenderName(companyId);
      await ref.set({
        'type': 'direct',
        'participants': [uid, mitarbeiter.uid],
        'participantNames': [
          {'uid': uid, 'name': senderName},
          {'uid': mitarbeiter.uid, 'name': mitarbeiter.name},
        ],
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageText': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String> createGroupChat(String companyId, String name, List<MitarbeiterForChat> members) async {
    final uid = userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final senderName = await _getSenderName(companyId);
    final participants = [uid, ...members.map((m) => m.uid)];
    final participantNames = [
      {'uid': uid, 'name': senderName},
      ...members.map((m) => {'uid': m.uid, 'name': m.name}),
    ];

    final ref = await _db.collection('kunden').doc(companyId).collection('chats').add({
      'type': 'group',
      'name': name,
      'participants': participants,
      'participantNames': participantNames,
      'createdBy': uid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageText': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
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
        if (v.toString().isNotEmpty || n.toString().isNotEmpty) {
          return '${v} ${n}'.trim();
        }
      }
    } catch (_) {}
    return user.email?.split('@').first ?? 'Unbekannt';
  }

  Future<void> sendMessage(
    String companyId,
    String chatId,
    String text, {
    List<Uint8List>? imageBytes,
    List<String>? imageNames,
  }) async {
    final uid = userId;
    if (uid == null) throw Exception('Nicht angemeldet');
    if (text.trim().isEmpty && (imageBytes == null || imageBytes!.isEmpty)) return;

    final senderName = await _getSenderName(companyId);
    List<Map<String, dynamic>>? attachments;

    if (imageBytes != null && imageBytes.isNotEmpty) {
      attachments = [];
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < imageBytes.length; i++) {
        final name = (i < (imageNames?.length ?? 0) ? imageNames![i] : 'image_$i.jpg')
            .replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
        final path = 'kunden/$companyId/chat-attachments/$chatId/${ts}_$i\_$name';
        final ref = _storage.ref(path);
        await ref.putData(imageBytes[i], SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();
        attachments.add({'url': url, 'name': name, 'type': 'image/jpeg'});
      }
    }

    final messagesRef = _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .doc(chatId)
        .collection('messages');

    await messagesRef.add({
      'from': uid,
      'senderName': senderName,
      'text': text.trim().isNotEmpty ? text.trim() : null,
      'attachments': attachments,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final lastPreview = text.trim().isNotEmpty
        ? text.trim()
        : (attachments != null ? (attachments.any((a) => (a['type'] ?? '').startsWith('audio/')) ? '🎤 Sprachnachricht' : '📎 Datei') : '');

    final chatRef = _db.collection('kunden').doc(companyId).collection('chats').doc(chatId);
    final chatSnap = await chatRef.get();
    final chat = chatSnap.data();
    final participants = (chat?['participants'] as List?)?.cast<String>() ?? [];

    await chatRef.set({
      'lastMessageText': lastPreview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageFrom': uid,
    }, SetOptions(merge: true));

    for (final pid in participants) {
      if (pid != uid && pid.isNotEmpty) {
        try {
          await chatRef.update({'unreadCount.$pid': FieldValue.increment(1)});
        } catch (_) {}
      }
    }
  }

  Future<void> deleteChatForMe(String companyId, String chatId) async {
    final uid = userId;
    if (uid == null) return;
    await _db.collection('kunden').doc(companyId).collection('chats').doc(chatId).update({
      'deletedBy': FieldValue.arrayUnion([uid]),
    });
  }
}
