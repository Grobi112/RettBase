const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

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

const db = admin.firestore();

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
