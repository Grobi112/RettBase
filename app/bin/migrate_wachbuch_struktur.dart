/// Migration: Wachbuch-Datenbankstruktur anlegen
/// Erstellt wachbuchConfig/config für alle Kunden, optional Standard-Ereignisse
/// Läuft mit: dart run app:migrate_wachbuch_struktur

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _defaultEreignisse = ['Wachbeginn', 'Wachende', 'Einsatz', 'Pause', 'Sonstiges'];

Future<void> main() async {
  print('=== Migration: Wachbuch-Struktur anlegen ===\n');

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
  int configCreated = 0;
  int ereignisseCreated = 0;

  final kundenSnap = await db.collection('kunden').get();
  print('Gefunden: ${kundenSnap.docs.length} Kunden\n');

  for (final kunde in kundenSnap.docs) {
    final companyId = kunde.id;
    print('Kunde: $companyId');

    final configRef = db.collection('kunden').doc(companyId).collection('wachbuchConfig').doc('config');
    final configSnap = await configRef.get();
    if (!configSnap.exists) {
      await configRef.set({
        'editAllowedRoles': ['superadmin', 'admin', 'leiterssd', 'koordinator'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      configCreated++;
      print('  - wachbuchConfig/config angelegt');
    }

    final ereignisseRef = db.collection('kunden').doc(companyId).collection('wachbuchEreignisse');
    final ereignisseSnap = await ereignisseRef.get();
    if (ereignisseSnap.docs.isEmpty) {
      for (var i = 0; i < _defaultEreignisse.length; i++) {
        final id = _defaultEreignisse[i].toLowerCase().replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9-]'), '');
        await ereignisseRef.doc(id).set({
          'name': _defaultEreignisse[i],
          'order': i,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
        ereignisseCreated++;
      }
      print('  - ${_defaultEreignisse.length} Standard-Ereignisse angelegt');
    }
  }

  print('\n=== Fertig ===');
  print('Config-Dokumente angelegt: $configCreated');
  print('Ereignisse angelegt: $ereignisseCreated');
  exit(0);
}
