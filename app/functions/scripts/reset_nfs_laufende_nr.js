#!/usr/bin/env node
/**
 * Setzt den Zähler für laufende interne Nr. (Einsatzprotokoll NFS) auf 0.
 * Nächste vergebene Nr. ist dann 20260001.
 *
 * Nutzung:
 *   cd app/functions && node scripts/reset_nfs_laufende_nr.js
 *
 * Voraussetzung:
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

const YEAR = 2026;

async function main() {
  console.log('=== NFS Zähler auf 20260001 zurücksetzen ===\n');

  try {
    const kundenSnap = await db.collection('kunden').get();
    let count = 0;

    for (const doc of kundenSnap.docs) {
      const companyId = doc.id;
      await db
        .collection('kunden')
        .doc(companyId)
        .collection('einsatzprotokoll-nfs-zähler')
        .doc(String(YEAR))
        .set({ lastNumber: 0 });
      count++;
      console.log('Kunde', companyId, '→ Zähler zurückgesetzt');
    }

    console.log('\n=== Fertig ===');
    console.log(count, 'Kunden aktualisiert. Nächste Nr.:', YEAR + '0001');
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
