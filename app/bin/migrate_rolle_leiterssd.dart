/// Migration: Rollen rettungsdienstleiter, rettungsdienstleitung, stützpunktleiter -> leiterssd
/// Läuft mit: dart run app:migrate_rolle_leiterssd
/// Voraussetzung: cd /Users/mikefullbeck/RettBase/app

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

const _oldRoles = ['rettungsdienstleiter', 'rettungsdienstleitung', 'stuetzpunktleiter', 'stützpunktleiter'];
const _newRole = 'leiterssd';

Future<void> main() async {
  print('=== Migration: Rolle zu LeiterSSD ===\n');

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
  int mitarbeiterUpdated = 0;
  int usersUpdated = 0;

  final kundenSnap = await db.collection('kunden').get();
  print('Gefunden: ${kundenSnap.docs.length} Kunden\n');

  for (final kunde in kundenSnap.docs) {
    final companyId = kunde.id;
    print('Kunde: $companyId');

    final mitarbeiterSnap = await db.collection('kunden').doc(companyId).collection('mitarbeiter').get();
    for (final doc in mitarbeiterSnap.docs) {
      final role = doc.data()['role']?.toString().toLowerCase().trim();
      if (role != null && _oldRoles.contains(role)) {
        await doc.reference.update({'role': _newRole});
        mitarbeiterUpdated++;
        print('  - Mitarbeiter ${doc.id}: $role -> $_newRole');
      }
    }

    final usersSnap = await db.collection('kunden').doc(companyId).collection('users').get();
    for (final doc in usersSnap.docs) {
      final role = doc.data()['role']?.toString().toLowerCase().trim();
      if (role != null && _oldRoles.contains(role)) {
        await doc.reference.update({'role': _newRole});
        usersUpdated++;
        print('  - User ${doc.id}: $role -> $_newRole');
      }
    }
  }

  print('\n=== Fertig ===');
  print('Mitarbeiter aktualisiert: $mitarbeiterUpdated');
  print('Users aktualisiert: $usersUpdated');
  exit(0);
}
