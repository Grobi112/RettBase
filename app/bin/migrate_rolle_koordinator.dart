/// Migration: Rolle "koordinator" in Firestore-Datenbank einpflegen
/// Aktualisiert settings/modules/items und settings/globalMenu
/// Läuft mit: dart run app:migrate_rolle_koordinator

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _newRole = 'koordinator';
const _referenceRole = 'leiterssd'; // Koordinator bekommt Zugriff, wo LeiterSSD Zugriff hat

Future<void> main() async {
  print('=== Migration: Rolle Koordinator in DB einpflegen ===\n');

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
        appId: '1:740721219821:ios:a8e7f8070f875866ccd4e4',
        messagingSenderId: '740721219821',
        projectId: 'rett-fe0fa',
        storageBucket: 'rett-fe0fa.firebasestorage.app',
        iosBundleId: 'com.mikefullbeck.rettbase',
      ),
    );
  } catch (e) {
    print('Firebase Init Fehler: $e');
    exit(1);
  }

  final db = FirebaseFirestore.instance;
  int modulesUpdated = 0;
  int menuItemsUpdated = 0;

  // 1. settings/modules/items – bei Modulen mit leiterssd auch koordinator ergänzen
  final modulesSnap = await db.collection('settings').doc('modules').collection('items').get();
  for (final doc in modulesSnap.docs) {
    final data = doc.data();
    final roles = data['roles'];
    if (roles is List) {
      final list = roles.map((r) => r.toString().toLowerCase()).toList();
      final hasLeiterssd = list.contains(_referenceRole);
      final hasKoordinator = list.contains(_newRole);
      if (hasLeiterssd && !hasKoordinator) {
        list.add(_newRole);
        await doc.reference.update({'roles': list});
        modulesUpdated++;
        print('Module ${doc.id}: koordinator hinzugefügt');
      }
    }
  }

  // 2. settings/globalMenu – bei Items mit leiterssd auch koordinator ergänzen
  final menuDoc = await db.doc('settings/globalMenu').get();
  if (menuDoc.exists) {
    final data = menuDoc.data();
    final items = data?['items'];
    if (items is List) {
      var changed = false;
      final updated = <Map<String, dynamic>>[];
      for (final raw in items) {
        if (raw is! Map) {
          updated.add(raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw));
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        final roles = item['roles'];
        if (roles is List) {
          final list = roles.map((r) => r.toString().toLowerCase()).toList();
          final hasLeiterssd = list.contains(_referenceRole);
          final hasKoordinator = list.contains(_newRole);
          if (hasLeiterssd && !hasKoordinator) {
            list.add(_newRole);
            item['roles'] = list;
            changed = true;
            menuItemsUpdated++;
            print('Menü-Item ${item['id'] ?? item['label']}: koordinator hinzugefügt');
          }
        }
        updated.add(item);
      }
      if (changed) {
        await db.doc('settings/globalMenu').update({
          'items': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  print('\n=== Fertig ===');
  print('Module aktualisiert: $modulesUpdated');
  print('Menü-Items aktualisiert: $menuItemsUpdated');
  exit(0);
}
