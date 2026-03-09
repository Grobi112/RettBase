import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;

import '../models/chat.dart';
import 'chat_offline_queue.dart';

/// Chat-Service – gleiche Logik wie rettbase/module/chat/chat.js
class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static bool _connectivityListenerActive = false;
  static ChatService? _activeService;

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

  /// Einmaliges Lesen der Ungelesen-Anzahl (für Badge-Polling, robust auf Web).
  Future<int> getUnreadCount(String companyId) async {
    final uid = userId;
    if (uid == null) return 0;
    try {
      final snap = await _db
          .collection('kunden')
          .doc(companyId)
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();
      var total = 0;
      for (final d in snap.docs) {
        final data = d.data();
        if ((data['deletedBy'] as List?)?.contains(uid) == true) continue;
        var unread = (data['unreadCount'] is Map ? (data['unreadCount'] as Map)[uid] : null);
        if (unread is int) {
          total += unread;
        } else if (unread == null || unread == 0) {
          final lastFrom = data['lastMessageFrom'];
          final lastAt = data['lastMessageAt'];
          if (lastFrom != null && lastFrom != uid && lastAt != null) {
            final lastRead = (data['lastReadAt'] is Map ? (data['lastReadAt'] as Map)[uid] : null);
            DateTime? lastReadAt;
            if (lastRead != null) {
              if (lastRead is Timestamp) lastReadAt = lastRead.toDate();
              else if (lastRead is DateTime) lastReadAt = lastRead;
            }
            final msgAt = lastAt is Timestamp ? lastAt.toDate() : (lastAt is DateTime ? lastAt : null);
            if (msgAt != null && (lastReadAt == null || msgAt.isAfter(lastReadAt))) total += 1;
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Gesamtzahl ungelesener Nachrichten für Badge-Anzeige (Menü, Schnellstart).
  Stream<int> streamUnreadCount(String companyId) {
    return streamChats(companyId).map((chats) {
      final uid = userId;
      if (uid == null) return 0;
      var total = 0;
      for (final c in chats) {
        var unread = c.unreadCount[uid] ?? 0;
        if (unread == 0 &&
            c.lastMessageFrom != null &&
            c.lastMessageFrom != uid &&
            c.lastMessageAt != null) {
          final lastRead = c.lastReadAt[uid];
          DateTime? lastReadAt;
          if (lastRead is Timestamp) lastReadAt = lastRead.toDate();
          if (lastRead is DateTime) lastReadAt = lastRead;
          if (lastReadAt == null || c.lastMessageAt!.isAfter(lastReadAt)) unread = 1;
        }
        total += unread;
      }
      return total;
    });
  }

  /// Einmaliges Laden der Nachrichten (robuster auf Flutter Web als snapshots).
  Future<List<ChatMessage>> loadMessages(String companyId, String chatId) async {
    final uid = userId;
    if (uid == null) return [];
    _markChatRead(companyId, chatId, uid);
    final snap = await _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(100)
        .get();
    return snap.docs
        .map((d) => ChatMessage.fromFirestore(d.id, d.data()))
        .where((m) => !m.deletedBy.contains(uid))
        .toList();
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
      final list = snap.docs
          .map((d) => ChatMessage.fromFirestore(d.id, d.data()))
          .where((m) => !m.deletedBy.contains(uid))
          .toList();
      for (final d in snap.docs) {
        final data = d.data();
        final from = data['from']?.toString();
        final delivered = (data['deliveredTo'] as List?)?.map((e) => e.toString()).toList() ?? [];
        if (from != null && from != uid && !delivered.contains(uid)) {
          unawaited(d.reference.update({'deliveredTo': FieldValue.arrayUnion([uid])}));
        }
      }
      return list;
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

  /// Öffentliche Methode zum Markieren eines Chats als gelesen (z.B. aus dashboard_screen).
  Future<void> markChatReadPublic(String companyId, String chatId) async {
    final uid = userId;
    if (uid == null) return;
    await _markChatRead(companyId, chatId, uid);
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

  static void ensureConnectivityListener(ChatService service) {
    if (kIsWeb) return;
    _activeService = service;
    if (_connectivityListenerActive) return;
    _connectivityListenerActive = true;
    _connectivitySub = ChatOfflineQueue.onConnectivityChanged.listen((_) async {
      if (await ChatOfflineQueue.isOnline) {
        final svc = _activeService;
        if (svc != null) unawaited(svc.processOfflineQueue());
      }
    });
  }

  /// Connectivity-Listener stoppen und Referenz freigeben (z.B. beim App-Ende).
  static void disposeConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _connectivityListenerActive = false;
    _activeService = null;
  }

  /// Verarbeitet die Offline-Queue – sendet alle ausstehenden Nachrichten.
  Future<void> processOfflineQueue() async {
    if (kIsWeb || userId == null) return;
    try {
      final pending = await ChatOfflineQueue.getAll();
      for (final p in pending) {
        try {
          await sendMessage(
            p.companyId,
            p.chatId,
            p.text,
            imageBytes: p.imageBytes,
            imageNames: p.imageNames,
            audioBytes: p.audioBytes,
            audioNames: p.audioNames,
          );
          await ChatOfflineQueue.remove(p.id);
        } catch (e) {
          if (kDebugMode) debugPrint('RettBase processOfflineQueue: $e');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('RettBase processOfflineQueue: $e');
    }
  }

  /// Sendet die Nachricht oder legt sie in die Offline-Queue (bei fehlendem Netz).
  Future<String> sendMessageOrQueue(
    String companyId,
    String chatId,
    String text, {
    List<Uint8List>? imageBytes,
    List<String>? imageNames,
    List<Uint8List>? audioBytes,
    List<String>? audioNames,
  }) async {
    final uid = userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final hasImages = imageBytes != null && imageBytes.isNotEmpty;
    final hasAudio = audioBytes != null && audioBytes.isNotEmpty;
    if (text.trim().isEmpty && !hasImages && !hasAudio) {
      throw Exception('Leere Nachricht');
    }

    ensureConnectivityListener(this);

    if (kIsWeb) {
      await sendMessage(companyId, chatId, text,
          imageBytes: imageBytes, imageNames: imageNames,
          audioBytes: audioBytes, audioNames: audioNames);
      return 'web-${DateTime.now().millisecondsSinceEpoch}';
    }

    final online = await ChatOfflineQueue.isOnline;
    if (online) {
      await sendMessage(companyId, chatId, text,
          imageBytes: imageBytes, imageNames: imageNames,
          audioBytes: audioBytes, audioNames: audioNames);
      return 'sent-${DateTime.now().millisecondsSinceEpoch}';
    }

    final id = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    await ChatOfflineQueue.enqueue(PendingChatMessage(
      id: id,
      companyId: companyId,
      chatId: chatId,
      text: text,
      imageBytes: imageBytes,
      imageNames: imageNames,
      audioBytes: audioBytes,
      audioNames: audioNames,
      createdAt: DateTime.now(),
    ));
    return id;
  }

  Future<void> sendMessage(
    String companyId,
    String chatId,
    String text, {
    List<Uint8List>? imageBytes,
    List<String>? imageNames,
    List<Uint8List>? audioBytes,
    List<String>? audioNames,
  }) async {
    final uid = userId;
    if (uid == null) throw Exception('Nicht angemeldet');

    final hasImages = imageBytes != null && imageBytes.isNotEmpty;
    final hasAudio = audioBytes != null && audioBytes.isNotEmpty;
    if (text.trim().isEmpty && !hasImages && !hasAudio) return;

    final senderName = await _getSenderName(companyId);

    List<Map<String, dynamic>>? attachments = [];
    final ts = DateTime.now().millisecondsSinceEpoch;

    if (hasImages) {
      for (var i = 0; i < imageBytes!.length; i++) {
        final name = (i < (imageNames?.length ?? 0) ? imageNames![i] : 'image_$i.jpg')
            .replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
        final path = 'kunden/$companyId/chat-attachments/$chatId/${ts}_img_${i}_$name';
        final ref = _storage.ref(path);
        await ref.putData(imageBytes[i], SettableMetadata(contentType: 'image/jpeg'));
        final url = await ref.getDownloadURL();
        attachments.add({'url': url, 'name': name, 'type': 'image/jpeg'});
      }
    }
    if (hasAudio) {
      for (var i = 0; i < audioBytes!.length; i++) {
        final name = (i < (audioNames?.length ?? 0) ? audioNames![i] : 'audio_$i.m4a')
            .replaceAll(RegExp(r'[^a-zA-Z0-9.-]'), '_');
        final path = 'kunden/$companyId/chat-attachments/$chatId/${ts}_audio_${i}_$name';
        final ref = _storage.ref(path);
        await ref.putData(audioBytes[i], SettableMetadata(contentType: 'audio/m4a'));
        final url = await ref.getDownloadURL();
        attachments.add({'url': url, 'name': name, 'type': 'audio/m4a'});
      }
    }
    if (attachments.isEmpty) attachments = null;

    // FIX Bug 8: Batch-Write statt sequentielle Get+Set+Update Calls.
    // participants werden beim sendMessage direkt aus dem Chat-Dokument gelesen
    // und alle Writes in einem WriteBatch gebündelt – keine Race-Condition mehr.
    final chatRef = _db.collection('kunden').doc(companyId).collection('chats').doc(chatId);
    final messagesRef = chatRef.collection('messages');

    final chatSnap = await chatRef.get();
    final chat = chatSnap.data() as Map<String, dynamic>?;
    final participants = (chat?['participants'] as List?)?.cast<String>() ?? [];

    final lastPreview = text.trim().isNotEmpty
        ? text.trim()
        : (attachments != null
            ? (attachments.any((a) => (a['type'] ?? '').startsWith('audio/'))
                ? '🎤 Sprachnachricht'
                : '📎 Datei')
            : '');

    final batch = _db.batch();

    final msgRef = messagesRef.doc();
    batch.set(msgRef, {
      'from': uid,
      'senderName': senderName,
      'text': text.trim().isNotEmpty ? text.trim() : null,
      'attachments': attachments,
      'createdAt': FieldValue.serverTimestamp(),
      'deliveredTo': [uid],
    });

    batch.set(chatRef, {
      'lastMessageText': lastPreview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageFrom': uid,
    }, SetOptions(merge: true));

    for (final pid in participants) {
      if (pid != uid && pid.isNotEmpty) {
        batch.update(chatRef, {'unreadCount.$pid': FieldValue.increment(1)});
      }
    }

    await batch.commit();
  }

  Future<void> deleteChatForMe(String companyId, String chatId) async {
    final uid = userId;
    if (uid == null) return;
    await _db.collection('kunden').doc(companyId).collection('chats').doc(chatId).update({
      'deletedBy': FieldValue.arrayUnion([uid]),
    });
  }

  /// Nachricht für mich löschen (nur für den Nutzer ausgeblendet).
  Future<void> deleteMessageForMe(String companyId, String chatId, String messageId) async {
    final uid = userId;
    if (uid == null) return;
    await _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'deletedBy': FieldValue.arrayUnion([uid])});
  }

  /// Nachricht(en) an anderen Chat weiterleiten.
  /// HINWEIS: URLs aus Anhängen werden direkt weitergeleitet (gleicher Storage-Bucket,
  /// kein Re-Upload nötig). Storage Rules müssen sicherstellen dass nur Teilnehmer Zugriff haben.
  Future<void> forwardMessages(
    String companyId,
    String targetChatId,
    List<ChatMessage> messages,
  ) async {
    final uid = userId;
    if (uid == null) throw Exception('Nicht angemeldet');
    final senderName = await _getSenderName(companyId);

    final chatRef = _db.collection('kunden').doc(companyId).collection('chats').doc(targetChatId);
    final messagesRef = chatRef.collection('messages');

    final chatSnap = await chatRef.get();
    final chat = chatSnap.data() as Map<String, dynamic>?;
    final participants = (chat?['participants'] as List?)?.cast<String>() ?? [];

    // FIX Bug 8: Batch-Write für forwardMessages
    final batch = _db.batch();

    ChatMessage? lastForwarded;
    for (final m in messages) {
      final text = (m.text ?? '').trim();
      final attachments = m.attachments
          ?.map((a) => {
                'url': a.url,
                'name': a.name,
                'type': a.type,
                if (a.duration != null) 'duration': a.duration,
              })
          .toList();
      if (text.isEmpty && (attachments == null || attachments.isEmpty)) continue;
      lastForwarded = m;
      final msgRef = messagesRef.doc();
      batch.set(msgRef, {
        'from': uid,
        'senderName': senderName,
        'text': text.isNotEmpty ? text : null,
        'attachments': attachments,
        'createdAt': FieldValue.serverTimestamp(),
        'deliveredTo': [uid],
      });
    }

    if (lastForwarded == null) return; // nichts zu forwarden

    final lastPreview = (lastForwarded.text ?? '').trim().isNotEmpty
        ? (lastForwarded.text ?? '').trim()
        : (lastForwarded.attachments != null && lastForwarded.attachments!.isNotEmpty
            ? '📎 Datei'
            : '');

    batch.set(chatRef, {
      'lastMessageText': lastPreview,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageFrom': uid,
    }, SetOptions(merge: true));

    for (final pid in participants) {
      if (pid != uid && pid.isNotEmpty) {
        batch.update(chatRef, {'unreadCount.$pid': FieldValue.increment(1)});
      }
    }

    await batch.commit();
  }

  /// FIX Bug 2: Nachricht für alle löschen – nur der Absender darf löschen.
  Future<void> deleteMessageForEveryone(String companyId, String chatId, String messageId) async {
    final uid = userId;
    if (uid == null) return;
    final ref = _db
        .collection('kunden')
        .doc(companyId)
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    // Sicherheitsprüfung: nur eigene Nachrichten dürfen für alle gelöscht werden
    final doc = await ref.get();
    if (!doc.exists) return;
    if (doc.data()?['from'] != uid) {
      if (kDebugMode) debugPrint('RettBase: deleteMessageForEveryone verweigert – nicht Absender');
      return;
    }
    await ref.delete();
  }

  /// Pfad für Chat-Präferenzen (angepinnte Chats) pro Nutzer.
  DocumentReference _chatPrefsRef(String companyId) {
    final uid = userId;
    if (uid == null) throw StateError('Nicht angemeldet');
    return _db.collection('kunden').doc(companyId).collection('chatPrefs').doc(uid);
  }

  /// Chat anpinnen – bleibt oben in der Liste.
  Future<void> pinChat(String companyId, String chatId) async {
    final ref = _chatPrefsRef(companyId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    final list = (data?['pinnedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (list.contains(chatId)) return;
    list.add(chatId);
    await ref.set({'pinnedChatIds': list}, SetOptions(merge: true));
  }

  /// Chat von Anpinnen entfernen.
  Future<void> unpinChat(String companyId, String chatId) async {
    final ref = _chatPrefsRef(companyId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    final list = (data?['pinnedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (list.contains(chatId)) {
      final updated = list.where((id) => id != chatId).toList();
      await ref.set({'pinnedChatIds': updated}, SetOptions(merge: true));
    }
  }

  /// Stream der angepinnten Chat-IDs (Reihenfolge = Reihenfolge oben).
  Stream<List<String>> streamPinnedChatIds(String companyId) {
    final uid = userId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('chatPrefs')
        .doc(uid)
        .snapshots()
        .map((snap) {
      final data = snap.data() as Map<String, dynamic>?;
      final list = (data?['pinnedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      return list;
    });
  }

  /// Chat stumm schalten – keine Push-Benachrichtigungen.
  Future<void> muteChat(String companyId, String chatId) async {
    final ref = _chatPrefsRef(companyId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    final list = (data?['mutedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (list.contains(chatId)) return;
    list.add(chatId);
    await ref.set({'mutedChatIds': list}, SetOptions(merge: true));
  }

  /// Stummschaltung aufheben.
  Future<void> unmuteChat(String companyId, String chatId) async {
    final ref = _chatPrefsRef(companyId);
    final snap = await ref.get();
    final data = snap.data() as Map<String, dynamic>?;
    final list = (data?['mutedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (list.contains(chatId)) {
      final updated = list.where((id) => id != chatId).toList();
      await ref.set({'mutedChatIds': updated}, SetOptions(merge: true));
    }
  }

  /// Stream der stumm geschalteten Chat-IDs.
  Stream<List<String>> streamMutedChatIds(String companyId) {
    final uid = userId;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('kunden')
        .doc(companyId)
        .collection('chatPrefs')
        .doc(uid)
        .snapshots()
        .map((snap) {
      final data = snap.data() as Map<String, dynamic>?;
      final list = (data?['mutedChatIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      return list;
    });
  }
}
