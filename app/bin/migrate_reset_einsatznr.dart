/// Migration: Nächste Einsatz-Nr. im Einsatzprotokoll SSD auf 20260001 setzen.
/// Alternative: In der App unter Protokollübersicht → Superadmin-Icon (↻) „Zurücksetzen“.
/// Läuft mit: flutter run -t bin/migrate_reset_einsatznr.dart (falls CLI gewünscht)
/// Setzt für alle Kunden kunden/{companyId}/settings/einsatzprotokoll-ssd.nextEinsatzNr = 20260001

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _nextNr = '20260001';

Future<void> main() async {
  print('=== Migration: Einsatz-Nr. auf $_nextNr zurücksetzen ===\n');

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
        .collection('settings')
        .doc('einsatzprotokoll-ssd')
        .set({
      'nextEinsatzNr': _nextNr,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    count++;
    print('Kunde $companyId: nextEinsatzNr auf $_nextNr gesetzt.');
  }

  print('\n=== Fertig ===');
  print('$count Kunden aktualisiert. Die nächste Einsatz-Nr. ist $_nextNr.');
  exit(0);
}
