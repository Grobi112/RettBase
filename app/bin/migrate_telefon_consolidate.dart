/// Migration: Handynummer nach Telefonnummer konsolidieren
/// Überträgt handynummer/handy nach telefon wenn telefon leer ist,
/// löscht handynummer und handy aus allen Mitarbeiter-Dokumenten.
/// Läuft mit: dart run bin/migrate_telefon_consolidate.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  print('=== Migration: Telefon konsolidieren (Handynummer → Telefonnummer) ===\n');

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
  int updated = 0;

  final kundenSnap = await db.collection('kunden').get();

  for (final kunde in kundenSnap.docs) {
    final companyId = kunde.id;
    final mitarbeiterSnap = await db.collection('kunden').doc(companyId).collection('mitarbeiter').get();

    for (final doc in mitarbeiterSnap.docs) {
      final d = doc.data();
      final telefon = d['telefon']?.toString().trim();
      final telefonnummer = d['telefonnummer']?.toString().trim();
      final handynummer = d['handynummer']?.toString().trim();
      final handy = d['handy']?.toString().trim();

      final hasTelefon = (telefon ?? '').isNotEmpty || (telefonnummer ?? '').isNotEmpty;
      final hasHandy = (handynummer ?? '').isNotEmpty || (handy ?? '').isNotEmpty;

      if (!hasHandy && hasTelefon) {
        continue;
      }

      String? newTelefon;
      if (hasTelefon) {
        newTelefon = telefon ?? telefonnummer;
      } else if (hasHandy) {
        newTelefon = handynummer ?? handy;
      }

      if (newTelefon == null || newTelefon.isEmpty) continue;

      await db.collection('kunden').doc(companyId).collection('mitarbeiter').doc(doc.id).update({
        'telefon': newTelefon,
        'telefonnummer': newTelefon,
        'handynummer': FieldValue.delete(),
        'handy': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      updated++;
      print('  ${doc.id}: Telefonnummer übernommen');
    }
  }

  print('\n=== Fertig ===');
  print('Mitarbeiter aktualisiert: $updated');
  exit(0);
}
