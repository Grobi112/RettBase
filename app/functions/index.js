const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

/** Tauscht ID-Token gegen Custom-Token für iframe-Auth-Bridge.
 *  Ermöglicht WebView-Module (Mitgliederverwaltung etc.) zentral gehostete Flutter-WebApp.
 */
exports.exchangeToken = functions.region("europe-west1").https.onCall(async (data, context) => {
  const idToken = data?.idToken;
  if (!idToken || typeof idToken !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "idToken erforderlich");
  }
  try {
    const decoded = await admin.auth().verifyIdToken(idToken);
    const customToken = await admin.auth().createCustomToken(decoded.uid);
    return { customToken };
  } catch (e) {
    console.warn("exchangeToken Fehler:", e.message);
    throw new functions.https.HttpsError("unauthenticated", "Token ungültig oder abgelaufen");
  }
});

/** Erstellt einen Firebase Auth Nutzer (Admin-Funktion).
 *  Wird von der Mitgliederverwaltung aufgerufen – Admin bleibt eingeloggt.
 */
exports.createAuthUser = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const { email, password } = data;
  if (!email || typeof email !== "string" || !password || typeof password !== "string") {
    throw new functions.https.HttpsError("invalid-argument", "email und password erforderlich");
  }
  if (password.length < 6) {
    throw new functions.https.HttpsError("invalid-argument", "Passwort mindestens 6 Zeichen");
  }
  try {
    const userRecord = await admin.auth().createUser({ email: email.trim(), password });
    return { uid: userRecord.uid };
  } catch (e) {
    if (e.code === "auth/email-already-in-use") {
      throw new functions.https.HttpsError("already-exists", "E-Mail bereits registriert");
    }
    throw new functions.https.HttpsError("internal", e.message);
  }
});

/** Setzt das Passwort eines Mitarbeiters (Admin-Funktion).
 *  Wird von der Mitgliederverwaltung aufgerufen.
 */
exports.updateMitarbeiterPassword = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const { uid, email, newPassword } = data;
  if (!newPassword || newPassword.length < 6) {
    throw new functions.https.HttpsError("invalid-argument", "newPassword (mind. 6 Zeichen) erforderlich");
  }
  let targetUid = uid;
  if (!targetUid && email) {
    try {
      const userRecord = await admin.auth().getUserByEmail(email);
      targetUid = userRecord.uid;
    } catch (e) {
      if (e.code === "auth/user-not-found") {
        throw new functions.https.HttpsError("not-found", "Benutzer mit dieser E-Mail nicht gefunden");
      }
      throw new functions.https.HttpsError("internal", e.message);
    }
  }
  if (!targetUid) {
    throw new functions.https.HttpsError("invalid-argument", "uid oder email erforderlich");
  }
  try {
    await admin.auth().updateUser(targetUid, { password: newPassword });
    return { success: true, uid: targetUid };
  } catch (e) {
    if (e.code === "auth/user-not-found") {
      throw new functions.https.HttpsError("not-found", "Benutzer nicht gefunden");
    }
    throw new functions.https.HttpsError("internal", e.message);
  }
});

function toPlainObject(obj) {
  if (obj == null) return obj;
  if (obj instanceof admin.firestore.Timestamp) {
    return obj.toDate().toISOString();
  }
  if (Array.isArray(obj)) return obj.map(toPlainObject);
  if (typeof obj === "object" && obj.constructor === Object) {
    const out = {};
    for (const [k, v] of Object.entries(obj)) out[k] = toPlainObject(v);
    return out;
  }
  return obj;
}

/** Prüft ob eine Kunden-ID existiert (ohne Auth, für Eingabe beim Start).
 *  Sucht kundenId + subdomain zusammen (keg hat subdomain kkg, evtl. kein kundenId),
 *  bevorzugt Doc mit anderer ID (Umbenennung), dann per Document-ID. */
exports.kundeExists = functions.region("europe-west1").https.onCall(async (data) => {
  const companyId = data?.companyId;
  if (!companyId || typeof companyId !== "string") {
    return { exists: false };
  }
  const id = companyId.trim().toLowerCase();
  if (!id) return { exists: false };
  try {
    const seen = new Set();
    const allDocs = [];
    const byKundenId = await db.collection("kunden").where("kundenId", "==", id).limit(5).get();
    byKundenId.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    const bySubdomain = await db.collection("kunden").where("subdomain", "==", id).limit(5).get();
    bySubdomain.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    if (allDocs.length > 0) {
      const docId = _pickBestDocId(allDocs, id);
      if (docId) return { exists: true, docId };
    }
    const doc = await db.collection("kunden").doc(id).get();
    if (doc.exists) {
      return { exists: true, docId: doc.id };
    }
    return { exists: false };
  } catch (e) {
    console.warn("kundeExists Fehler:", e.message);
    return { exists: false };
  }
});

function _pickBestDocId(docs, searchId) {
  if (!docs || docs.length === 0) return null;
  const withDifferentId = docs.filter((d) => d.id !== searchId);
  if (withDifferentId.length > 0) {
    return withDifferentId[0].id;
  }
  return docs[0].id;
}

/** Lädt alle Kunden (Firmen) – umgeht Firestore-Regeln für Web-App.
 *  Projekt: rett-fe0fa, Collection: kunden. */
exports.loadKunden = functions.region("europe-west1").https.onCall(async (data, context) => {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "(unknown)";
  console.log("loadKunden: Projekt=", projectId, "Collection=kunden");
  try {
    if (!context?.auth) {
      console.warn("loadKunden: Nicht authentifiziert (uid fehlt)");
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const snap = await db.collection("kunden").get();
    const list = snap.docs.map((d) => toPlainObject({ id: d.id, ...d.data() }));
    list.sort((a, b) => (a.name || "").toLowerCase().localeCompare((b.name || "").toLowerCase()));
    console.log("loadKunden: ", list.length, " Kunden in kunden-Collection gefunden");
    return { kunden: list };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("loadKunden Fehler:", e);
    throw new functions.https.HttpsError("internal", e.message || String(e));
  }
});

function toFirestoreValue(v) {
  if (v == null) return v;
  if (v && typeof v === "object" && v.__delete === true) return admin.firestore.FieldValue.delete();
  if (typeof v === "number" && v > 1e12) return admin.firestore.Timestamp.fromMillis(v);
  if (v && typeof v === "object" && ("_seconds" in v || "seconds" in v)) {
    const s = v._seconds ?? v.seconds ?? 0;
    const n = v._nanoseconds ?? v.nanoseconds ?? 0;
    return new admin.firestore.Timestamp(s, n);
  }
  return v;
}

function sanitizeForFirestore(obj) {
  if (obj == null) return obj;
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    if (k.startsWith("__")) continue;
    const converted = toFirestoreValue(v);
    if (converted === undefined) continue;
    out[k] = converted;
  }
  return out;
}

/** Schreibt Mitarbeiter-Dokument (umgeht Firestore-Regeln für Web-App). */
exports.saveMitarbeiterDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId, docId, data: docData } = data || {};
    if (!companyId || !docId || !docData || typeof docData !== "object") {
      throw new functions.https.HttpsError("invalid-argument", "companyId, docId und data erforderlich");
    }
    const ref = db.collection("kunden").doc(companyId).collection("mitarbeiter").doc(docId);
    const toWrite = sanitizeForFirestore({ ...docData, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    delete toWrite.createdAt;
    await ref.set(toWrite, { merge: true });
    return { success: true };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("saveMitarbeiterDoc Fehler:", e);
    throw new functions.https.HttpsError("internal", e.message || String(e));
  }
});

/** Schreibt users-Dokument (umgeht Firestore-Regeln für Web-App). */
exports.saveUsersDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId, uid, data: docData } = data || {};
    if (!companyId || !uid || !docData || typeof docData !== "object") {
      throw new functions.https.HttpsError("invalid-argument", "companyId, uid und data erforderlich");
    }
    const ref = db.collection("kunden").doc(companyId).collection("users").doc(uid);
    const toWrite = sanitizeForFirestore({ ...docData, updatedAt: admin.firestore.FieldValue.serverTimestamp(), companyId });
    await ref.set(toWrite, { merge: true });
    return { success: true };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("saveUsersDoc Fehler:", e);
    throw new functions.https.HttpsError("internal", e.message || String(e));
  }
});

/** Erstellt neues Mitarbeiter-Dokument (für Neuanlage). */
exports.createMitarbeiterDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId, data: docData } = data || {};
    if (!companyId || !docData || typeof docData !== "object") {
      throw new functions.https.HttpsError("invalid-argument", "companyId und data erforderlich");
    }
    const ref = db.collection("kunden").doc(companyId).collection("mitarbeiter").doc();
    const toWrite = sanitizeForFirestore({
      ...docData,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await ref.set(toWrite);
    return { docId: ref.id };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("createMitarbeiterDoc Fehler:", e);
    throw new functions.https.HttpsError("internal", e.message || String(e));
  }
});
