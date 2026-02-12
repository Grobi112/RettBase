/// Seed: Erstellt settings/modules und fügt das Modul Einsatzprotokoll SSD hinzu.
/// Läuft mit: dart run app:seed_module_ssd
/// Voraussetzung: cd ins App-Verzeichnis

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _defaultRoles = [
  'superadmin', 'admin', 'leiterssd', 'geschaeftsfuehrung', 'rettungsdienstleitung',
  'koordinator', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter',
];

Future<void> main() async {
  print('=== Seed: Einsatzprotokoll SSD Modul anlegen ===\n');

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA',
        appId: '1:740721219821:web:a8e7f8070f875866ccd4e4',
        messagingSenderId: '740721219821',
        projectId: 'rett-fe0fa',
        authDomain: 'rett-fe0fa.firebaseapp.com',
        storageBucket: 'rett-fe0fa.firebasestorage.app',
      ),
    );
  } catch (e) {
    print('Firebase Init Fehler: $e');
    exit(1);
  }

  final db = FirebaseFirestore.instance;
  final itemsRef = db.collection('settings').doc('modules').collection('items');

  try {
    // 1. Parent-Dokument settings/modules anlegen (falls nicht vorhanden)
    await db.collection('settings').doc('modules').set(
      {'_exists': true},
      SetOptions(merge: true),
    );
    print('settings/modules angelegt oder aktualisiert.');

    // 2. Modul ssd in settings/modules/items anlegen
    final ssdData = {
      'label': 'Einsatzprotokoll SSD',
      'url': '',
      'icon': 'default',
      'roles': _defaultRoles,
      'free': true,
      'order': 29,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final existing = await itemsRef.doc('ssd').get();
    if (existing.exists) {
      await itemsRef.doc('ssd').update({
        'label': 'Einsatzprotokoll SSD',
        'url': '',
        'order': 29,
        'active': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('Modul ssd bereits vorhanden – aktualisiert.');
    } else {
      await itemsRef.doc('ssd').set(ssdData);
      print('Modul ssd (Einsatzprotokoll SSD) angelegt.');
    }

    print('\n=== Fertig ===');
    exit(0);
  } catch (e, st) {
    print('Fehler: $e');
    print(st);
    exit(1);
  }
}
