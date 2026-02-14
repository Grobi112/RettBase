#!/usr/bin/env node
/**
 * Prüft, ob FCM-Tokens in Firestore gespeichert sind.
 *
 * Nutzung:
 *   cd app/functions && node scripts/check_fcm_tokens.js [companyId]
 *
 * Voraussetzung für lokale Ausführung:
 *   gcloud auth application-default login
 *   (oder GOOGLE_APPLICATION_CREDENTIALS mit Service-Account-Key)
 */

const path = require('path');
const fs = require('fs');
const admin = require('firebase-admin');

const keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS
  || path.join(__dirname, '..', 'service-account-key.json');
const keyPathResolved = path.resolve(keyPath);

if (!admin.apps.length) {
  const options = { projectId: 'rett-fe0fa' };
  if (fs.existsSync(keyPathResolved)) {
    const key = JSON.parse(fs.readFileSync(keyPathResolved, 'utf8'));
    options.credential = admin.credential.cert(key);
  }
  admin.initializeApp(options);
}
const db = admin.firestore();

async function main() {
  const companyId = process.argv[2] || 'nfsunna';

  console.log('FCM-Token-Check für Projekt rett-fe0fa\n');

  try {
    const fcmSnap = await db.collection('fcmTokens').limit(20).get();
    console.log('Collection fcmTokens:', fcmSnap.size, 'Dokumente');
    if (fcmSnap.empty) {
      console.log('  → Keine Tokens gefunden (Web-Push evtl. noch nicht aktiviert)\n');
    } else {
      for (const doc of fcmSnap.docs) {
        const d = doc.data();
        const token = (d.fcmToken || '').trim();
        const updated = d.fcmTokenUpdatedAt?.toDate?.() || d.fcmTokenUpdatedAt || '-';
        const isWeb = token.length > 200;
        console.log('  uid:', doc.id);
        console.log('    Token:', token ? (token.substring(0, 60) + '...') : '(leer)');
        console.log('    Aktualisiert:', updated);
        console.log('    Typ:', isWeb ? 'Web' : 'Native');
        console.log('');
      }
    }

    const usersSnap = await db.collection('kunden').doc(companyId).collection('users').limit(10).get();
    console.log('kunden/' + companyId + '/users:', usersSnap.size, 'Dokumente (erste 10)');
    for (const doc of usersSnap.docs) {
      const d = doc.data();
      const token = (d.fcmToken || '').trim();
      if (token) {
        console.log('  uid:', doc.id, '→ Token vorhanden (' + token.substring(0, 40) + '...)');
      } else {
        console.log('  uid:', doc.id, '→ Kein Token');
      }
    }
  } catch (e) {
    console.error('Fehler:', e.message);
    if (e.code === 'auth/credential' || (e.message && e.message.includes('credential'))) {
      console.log('\nHinweis: Bitte zuerst ausführen:');
      console.log('  gcloud auth application-default login');
      console.log('\nOder Service-Account-Key setzen:');
      console.log('  export GOOGLE_APPLICATION_CREDENTIALS=/pfad/zu/serviceAccountKey.json');
    }
    process.exit(1);
  }
}

main();
