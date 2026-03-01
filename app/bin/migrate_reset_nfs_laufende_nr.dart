/// Migration: Zähler für laufende interne Nr. (Einsatzprotokoll NFS) auf 0 setzen.
/// Nächste vergebene Nr. ist dann 20260001.
///
/// Läuft mit: flutter run -t bin/migrate_reset_nfs_laufende_nr.dart
/// Setzt für alle Kunden kunden/{companyId}/einsatzprotokoll-nfs-zähler/2026.lastNumber = 0

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _year = 2026;

Future<void> main() async {
  print('=== Migration: NFS Zähler auf ${_year}0001 zurücksetzen ===\n');

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
  final kundenSnap = await db.collection('kunden').get();
  int count = 0;

  for (final doc in kundenSnap.docs) {
    final companyId = doc.id;
    await db
        .collection('kunden')
        .doc(companyId)
        .collection('einsatzprotokoll-nfs-zähler')
        .doc('$_year')
        .set({'lastNumber': 0});
    count++;
    print('Kunde $companyId: Zähler zurückgesetzt.');
  }

  print('\n=== Fertig ===');
  print('$count Kunden aktualisiert. Nächste Nr.: ${_year}0001');
  exit(0);
}
