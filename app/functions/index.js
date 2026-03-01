const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Projekt explizit für Auth-Konsistenz (rett-fe0fa = Flutter-App + alle Module)
admin.initializeApp({
  projectId: process.env.GCLOUD_PROJECT || "rett-fe0fa",
  storageBucket: "rett-fe0fa.firebasestorage.app",
});

const db = admin.firestore();

/** Rate-Limit für kundeExists und resolveLoginInfo: pro Client maximal 5 Aufrufe/Minute (Schutz vor Enumerations-Angriffen). */
const _kundeExistsRateLimit = new Map();
const KUNDE_EXISTS_MAX_PER_MINUTE = 5;

function _checkKundeExistsRateLimit(context) {
  const now = Date.now();
  const windowMs = 60000;
  const ip = context?.rawRequest?.ip
    || (context?.rawRequest?.headers && (context.rawRequest.headers["x-forwarded-for"] || "").split(",")[0]?.trim())
    || context?.rawRequest?.connection?.remoteAddress
    || "unknown";
  let entry = _kundeExistsRateLimit.get(ip);
  if (!entry || now - entry.windowStart > windowMs) {
    entry = { count: 0, windowStart: now };
    _kundeExistsRateLimit.set(ip, entry);
  }
  entry.count++;
  if (entry.count > KUNDE_EXISTS_MAX_PER_MINUTE) {
    throw new functions.https.HttpsError("resource-exhausted", "Zu viele Anfragen. Bitte später erneut versuchen.");
  }
}

/** Basis-URL der Web-App für Push-Klick-Links (zentral gehostet, z.B. app.rettbase.de). */
const WEB_APP_BASE_URL = "https://app.rettbase.de";

/** Push-Benachrichtigungen (und Badge bei geschlossener App – SW setzt Badge beim Push-Empfang). */
const PUSH_ENABLED = true;

/** Tauscht Auth gegen Custom-Token für iframe-Auth-Bridge.
 *  Nutzt context.auth (automatisch vom Callable-Client) – robuster als manuelles idToken.
 *  Fallback: idToken aus data (für Clients, die ihn explizit senden).
 */
exports.exchangeToken = functions.region("europe-west1").https.onCall(async (data, context) => {
  let uid = context?.auth?.uid;
  if (!uid) {
    const idToken = data?.idToken;
    if (idToken && typeof idToken === "string") {
      try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
      } catch (e) {
        console.warn("exchangeToken verifyIdToken Fehler:", e.message);
        throw new functions.https.HttpsError("unauthenticated", "Token ungültig oder abgelaufen");
      }
    }
  }
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Bitte erneut anmelden");
  }
  const uidStr = String(uid).trim();
  if (!uidStr) {
    throw new functions.https.HttpsError("invalid-argument", "uid leer");
  }
  try {
    const customToken = await admin.auth().createCustomToken(uidStr);
    return { customToken };
  } catch (e) {
    console.error("exchangeToken createCustomToken Fehler:", e.code || e.message, e);
    throw new functions.https.HttpsError("internal", (e.code || "unknown") + ": " + (e.message || "createCustomToken fehlgeschlagen"));
  }
});

/** Prüft ob der Aufrufer Admin/Superadmin/LeiterSSD ist (für createAuthUser, updateMitarbeiterPassword). */
async function _requireAdminRole(context, companyId) {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const uid = context.auth.uid;
  const email = (context.auth.token?.email || "").toString().toLowerCase();
  const adminRoles = ["superadmin", "admin", "leiterssd", "koordinator"];
  const isGlobalSuperadmin = email === "admin@rettbase.de" || email === "admin@rettbase";
  const is112Admin = companyId === "admin" && email === "112@admin.rettbase.de";
  if (isGlobalSuperadmin || is112Admin) return;
  // Admin-Superadmins (users/mitarbeiter in admin mit role superadmin) dürfen in allen Firmen Admin-Aktionen ausführen
  if (companyId !== "admin") {
    const [adminUser, adminMitarbeiter] = await Promise.all([
      db.collection("kunden").doc("admin").collection("users").doc(uid).get(),
      db.collection("kunden").doc("admin").collection("mitarbeiter").where("uid", "==", uid).limit(1).get(),
    ]);
    if (adminUser.exists && (adminUser.data()?.role || "").toString().toLowerCase() === "superadmin") return;
    if (!adminMitarbeiter.empty && (adminMitarbeiter.docs[0].data()?.role || "").toString().toLowerCase() === "superadmin") return;
    const pn112 = await db.collection("kunden").doc("admin").collection("mitarbeiter").where("personalnummer", "==", "112").limit(1).get();
    if (!pn112.empty && pn112.docs[0].data()?.uid === uid) return;
  }
  const usersSnap = await db.collection("kunden").doc(String(companyId)).collection("users").doc(uid).get();
  if (usersSnap.exists) {
    const role = (usersSnap.data()?.role || "").toString().toLowerCase();
    if (adminRoles.includes(role)) return;
  }
  const mitarbeiterSnap = await db.collection("kunden").doc(String(companyId)).collection("mitarbeiter").where("uid", "==", uid).limit(1).get();
  if (!mitarbeiterSnap.empty) {
    const role = (mitarbeiterSnap.docs[0].data()?.role || "").toString().toLowerCase();
    if (adminRoles.includes(role)) return;
  }
  if (companyId === "admin") {
    const adminMitarbeiter = await db.collection("kunden").doc("admin").collection("mitarbeiter").where("personalnummer", "==", "112").limit(1).get();
    if (!adminMitarbeiter.empty && adminMitarbeiter.docs[0].data()?.uid === uid) return;
  }
  throw new functions.https.HttpsError("permission-denied", "Nur Admin, Superadmin oder LeiterSSD können diese Aktion ausführen.");
}

/** Erstellt einen Firebase Auth Nutzer (Admin-Funktion).
 *  Wird von der Mitgliederverwaltung aufgerufen – Admin bleibt eingeloggt.
 */
exports.createAuthUser = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const companyId = (data?.companyId || "").trim();
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  await _requireAdminRole(context, companyId);
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
    const code = e.code || e.errorInfo?.code || "";
    if (code === "auth/email-already-in-use" || code === "auth/email-already-exists") {
      throw new functions.https.HttpsError("already-exists", "E-Mail bereits registriert. Nutzen Sie „Passwort setzen“ bei bestehendem Mitglied.");
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
  const companyId = (data?.companyId || "").trim();
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  await _requireAdminRole(context, companyId);
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
  const cid = (await _resolveToDocId(companyId)) || companyId.toLowerCase();
  const [userInCompany, mitarbeiterSnap] = await Promise.all([
    db.collection("kunden").doc(cid).collection("users").doc(targetUid).get(),
    db.collection("kunden").doc(cid).collection("mitarbeiter").where("uid", "==", targetUid).limit(1).get(),
  ]);
  const isInCompany = userInCompany.exists || !mitarbeiterSnap.empty;
  if (!isInCompany) {
    throw new functions.https.HttpsError("permission-denied", "Nutzer gehört nicht zu dieser Firma – Passwort-Änderung nicht erlaubt.");
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

const ROOT_DOMAIN = "rettbase.de";

/** Login-Lookup ohne Auth. Rate-Limit wie kundeExists. Ersetzt direkten Firestore-Zugriff durch Client
 *  (mitarbeiter war allow read: if true – DSGVO/Sicherheitsrisiko). */
exports.resolveLoginInfo = functions.region("europe-west1").https.onCall(async (data, context) => {
  _checkKundeExistsRateLimit(context);
  const { companyId: companyIdParam, emailOrPersonalnummer } = data || {};
  const input = (emailOrPersonalnummer || "").toString().trim();
  if (!input) {
    throw new functions.https.HttpsError("invalid-argument", "Bitte Benutzerkennung eingeben.");
  }
  const normalizedCompanyId = (companyIdParam || "").trim().toLowerCase();
  if (!normalizedCompanyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }

  const isEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input);
  const isGlobalSuperadmin = (s) => {
    const e = s.trim().toLowerCase();
    return e === "admin@rettbase.de" || e === "admin@rettbase";
  };

  if (isGlobalSuperadmin(input)) {
    return { email: "admin@rettbase.de", mitarbeiterDocPath: null, effectiveCompanyId: normalizedCompanyId };
  }
  if (normalizedCompanyId === "admin" && input.trim() === "112") {
    return { email: "112@admin." + ROOT_DOMAIN, mitarbeiterDocPath: null, effectiveCompanyId: "admin" };
  }

  const companyId = (await _resolveToDocId(normalizedCompanyId)) || normalizedCompanyId;
  const mitarbeiterRef = db.collection("kunden").doc(companyId).collection("mitarbeiter");

  let snapshot;
  if (isEmail) {
    snapshot = await mitarbeiterRef.where("email", "==", input.trim()).limit(1).get();
  } else {
    snapshot = await mitarbeiterRef.where("personalnummer", "==", input).limit(1).get();
    if (snapshot.empty && /^\d+$/.test(input)) {
      snapshot = await mitarbeiterRef.where("personalnummer", "==", parseInt(input, 10)).limit(1).get();
    }
  }

  if (snapshot.empty) {
    const msg = isEmail ? `Benutzer mit E-Mail-Adresse "${input}" nicht in der Mitarbeiterverwaltung gefunden.` : `Benutzer mit Personalnummer "${input}" nicht gefunden.`;
    throw new functions.https.HttpsError("not-found", msg);
  }
  const doc = snapshot.docs[0];
  const mData = doc.data();
  if (mData.active === false || mData.status === false) {
    throw new functions.https.HttpsError("failed-precondition", "Benutzer ist deaktiviert.");
  }
  const docPseudo = (mData.pseudoEmail || "").toString().trim();
  const realEmail = (mData.email || "").toString().trim();
  const isPseudo = realEmail && realEmail.endsWith("." + ROOT_DOMAIN);
  let email;
  // PseudoEmail hat Vorrang: Firebase Auth wurde damit erstellt; echte E-Mail im Profil
  // ändert die Auth-Identity nicht – Login muss immer mit pseudoEmail erfolgen
  if (docPseudo) {
    email = docPseudo;
  } else if (realEmail && !isPseudo) {
    email = realEmail;
  } else {
    email = input + "@" + companyId + "." + ROOT_DOMAIN;
  }
  const path = "kunden/" + companyId + "/mitarbeiter/" + doc.id;
  return { email, mitarbeiterDocPath: path, effectiveCompanyId: companyId };
});

/** Prüft ob eine Kunden-ID existiert (ohne Auth, für Eingabe beim Start).
 *  Sucht kundenId + subdomain zusammen (keg hat subdomain kkg, evtl. kein kundenId),
 *  bevorzugt Doc mit anderer ID (Umbenennung), dann per Document-ID.
 *  Rate-Limit: max 5 Aufrufe/Minute pro Client (Schutz vor Enumerations-Angriffen). */
exports.kundeExists = functions.region("europe-west1").https.onCall(async (data, context) => {
  _checkKundeExistsRateLimit(context);
  const companyId = data?.companyId;
  if (!companyId || typeof companyId !== "string") {
    return { exists: false };
  }
  const id = companyId.trim().toLowerCase();
  if (!id) return { exists: false };
  try {
    const seen = new Set();
    const allDocs = [];
    const [byKundenId, bySubdomain] = await Promise.all([
      db.collection("kunden").where("kundenId", "==", id).limit(5).get(),
      db.collection("kunden").where("subdomain", "==", id).limit(5).get(),
    ]);
    byKundenId.docs.forEach((d) => {
      if (!seen.has(d.id)) { seen.add(d.id); allDocs.push(d); }
    });
    bySubdomain.docs.forEach((d) => {
      if (!seen.has(d.id)) { seen.add(d.id); allDocs.push(d); }
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

async function _resolveToDocId(companyId) {
  if (!companyId || typeof companyId !== "string") return null;
  const id = String(companyId).trim().toLowerCase();
  if (!id) return null;
  try {
    const seen = new Set();
    const allDocs = [];
    const [byKundenId, bySubdomain] = await Promise.all([
      db.collection("kunden").where("kundenId", "==", id).limit(5).get(),
      db.collection("kunden").where("subdomain", "==", id).limit(5).get(),
    ]);
    byKundenId.docs.forEach((d) => {
      if (!seen.has(d.id)) { seen.add(d.id); allDocs.push(d); }
    });
    bySubdomain.docs.forEach((d) => {
      if (!seen.has(d.id)) { seen.add(d.id); allDocs.push(d); }
    });
    if (allDocs.length > 0) return _pickBestDocId(allDocs, id);
    const doc = await db.collection("kunden").doc(id).get();
    return doc.exists ? doc.id : null;
  } catch (e) {
    console.warn("_resolveToDocId Fehler:", e.message);
    return null;
  }
}

function _pickBestDocId(docs, searchId) {
  if (!docs || docs.length === 0) return null;
  const withDifferentId = docs.filter((d) => d.id !== searchId);
  if (withDifferentId.length > 0) {
    return withDifferentId[0].id;
  }
  return docs[0].id;
}

/** Prüft ob der Aufrufer Superadmin ist (für loadKunden, Kundenverwaltung). */
async function _requireSuperadminRole(context) {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const uid = context.auth.uid;
  const email = (context.auth.token?.email || "").toString().toLowerCase();
  if (email === "admin@rettbase.de" || email === "admin@rettbase") return;
  if (email === "112@admin." + ROOT_DOMAIN) return;
  const adminUser = await db.collection("kunden").doc("admin").collection("users").doc(uid).get();
  if (adminUser.exists && (adminUser.data()?.role || "").toString().toLowerCase() === "superadmin") return;
  const mitSnap = await db.collection("kunden").doc("admin").collection("mitarbeiter").where("uid", "==", uid).limit(1).get();
  if (!mitSnap.empty && (mitSnap.docs[0].data()?.role || "").toString().toLowerCase() === "superadmin") return;
  throw new functions.https.HttpsError("permission-denied", "Nur Superadmin kann die Kundenverwaltung nutzen.");
}

/** Lädt alle Kunden (Firmen) – nur für Superadmin. Projekt: rett-fe0fa, Collection: kunden. */
exports.loadKunden = functions.region("europe-west1").https.onCall(async (data, context) => {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "(unknown)";
  console.log("loadKunden: Projekt=", projectId, "Collection=kunden");
  try {
    await _requireSuperadminRole(context);
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

/** Schreibt Mitarbeiter-Dokument (umgeht Firestore-Regeln für Web-App). Nur Admin/Superadmin/LeiterSSD. */
exports.saveMitarbeiterDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId: rawCompanyId, docId, data: docData } = data || {};
    const companyId = (await _resolveToDocId(rawCompanyId)) || (rawCompanyId || "").trim().toLowerCase();
    if (companyId) await _requireAdminRole(context, companyId);
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

/** Stellt sicher, dass users-Dokument existiert (für Firestore-Zugriffsregeln nach Login).
 *  Prüft, ob Aufrufer in mitarbeiter der Firma ist; erstellt users-Doc falls nötig.
 *  Löst kundenId → docId auf (z.B. kkg-luenen → keg-luenen). */
exports.ensureUsersDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const inputCompanyId = (data?.companyId || "").trim();
  if (!inputCompanyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  const companyId = (await _resolveToDocId(inputCompanyId)) || inputCompanyId.toLowerCase();
  const uid = context.auth.uid;
  const email = (context.auth.token?.email || "").toString();
  const isGlobalSuperadmin = email === "admin@rettbase.de" || email === "admin@rettbase";
  const is112Admin = email === "112@admin.rettbase.de";
  let isAdminCompanySuperadmin = false;
  if (!isGlobalSuperadmin && !is112Admin) {
    const [adminUser, byUidAdmin] = await Promise.all([
      db.collection("kunden").doc("admin").collection("users").doc(uid).get(),
      db.collection("kunden").doc("admin").collection("mitarbeiter").where("uid", "==", uid).limit(1).get(),
    ]);
    if (adminUser.exists && (adminUser.data()?.role || "").toString().toLowerCase() === "superadmin") isAdminCompanySuperadmin = true;
    if (!isAdminCompanySuperadmin && !byUidAdmin.empty && (byUidAdmin.docs[0].data()?.role || "").toString().toLowerCase() === "superadmin") isAdminCompanySuperadmin = true;
  }
  const ref = db.collection("kunden").doc(companyId).collection("users").doc(uid);
  const isSuperadminUser = isGlobalSuperadmin || is112Admin || isAdminCompanySuperadmin;

  if (isSuperadminUser) {
    await ref.set({ companyId, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  } else {
    const byUid = await db.collection("kunden").doc(companyId).collection("mitarbeiter").where("uid", "==", uid).limit(1).get();
    if (byUid.empty) {
      const userDoc = await db.collection("kunden").doc(companyId).collection("users").doc(uid).get();
      if (userDoc.exists) {
        await _setStorageClaims(uid, companyId, false);
        return { success: true };
      }
      throw new functions.https.HttpsError("permission-denied", "Nutzer ist kein Mitarbeiter dieser Firma");
    }
    const m = byUid.docs[0].data();
    await ref.set({
      companyId,
      email: m.email || email,
      role: (m.role || "user").toString().toLowerCase(),
      mitarbeiterDocId: byUid.docs[0].id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
  }

  await _setStorageClaims(uid, companyId, isSuperadminUser);
  return { success: true };
});

/** Setzt Custom Claims für Storage-Regeln (companyId / superadmin). Nur bei Änderung, um Token-Invalidierung zu vermeiden. */
async function _setStorageClaims(uid, companyId, isSuperadmin) {
  try {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};
    const needSuperadmin = !!isSuperadmin;
    const needCompanyId = String(companyId || "");
    if (existing.companyId === needCompanyId && !!existing.superadmin === needSuperadmin) return;
    const next = { ...existing };
    if (needSuperadmin) {
      next.superadmin = true;
    } else {
      delete next.superadmin;
    }
    next.companyId = needCompanyId;
    await admin.auth().setCustomUserClaims(uid, next);
  } catch (e) {
    console.warn("_setStorageClaims Fehler:", e.message);
  }
}

/** Schreibt users-Dokument (umgeht Firestore-Regeln für Web-App). Nur Admin/Superadmin/LeiterSSD. */
exports.saveUsersDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId: rawCompanyId, uid, data: docData } = data || {};
    const companyId = (await _resolveToDocId(rawCompanyId)) || (rawCompanyId || "").trim().toLowerCase();
    if (companyId) await _requireAdminRole(context, companyId);
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

/** Callable: Prüft ob FCM-Token für aktuellen Nutzer in Firestore ist (für Debug/Status-Anzeige). */
exports.getFcmTokenStatus = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Nicht angemeldet");
  }
  const uid = context.auth.uid;
  const companyId = (data?.companyId || "").trim() || null;
  try {
    let token = "";
    if (companyId) {
      const userSnap = await db.collection("kunden").doc(companyId).collection("users").doc(uid).get();
      if (userSnap.exists) token = (userSnap.data().fcmToken || "").trim();
    }
    if (!token) {
      const globalSnap = await db.collection("fcmTokens").doc(uid).get();
      if (globalSnap.exists) token = (globalSnap.data().fcmToken || "").trim();
    }
    return { hasToken: token.length > 0 };
  } catch (e) {
    console.warn("getFcmTokenStatus Fehler:", e.message);
    return { hasToken: false };
  }
});

async function getFcmToken(companyId, uid) {
  let token = "";
  const userSnap = await admin.firestore().collection("kunden").doc(companyId).collection("users").doc(uid).get();
  if (userSnap.exists) token = (userSnap.data().fcmToken || "").trim();
  if (!token) {
    const globalSnap = await admin.firestore().collection("fcmTokens").doc(uid).get();
    if (globalSnap.exists) token = (globalSnap.data().fcmToken || "").trim();
  }
  return token;
}

/** Summiert ungelesene Nachrichten über alle Chats eines Nutzers (inkl. neuer Nachricht). */
async function getTotalUnreadForUser(companyId, uid, currentChatId) {
  try {
    const chatsSnap = await admin.firestore()
      .collection("kunden").doc(companyId).collection("chats")
      .where("participants", "array-contains", uid)
      .get();
    let total = 0;
    for (const d of chatsSnap.docs) {
      const data = d.data();
      const unread = (data.unreadCount && data.unreadCount[uid]) || 0;
      total += Number(unread);
      if (d.id === currentChatId) total += 1;
    }
    return Math.min(99, Math.max(1, total));
  } catch (e) {
    console.warn("getTotalUnreadForUser Fehler:", e.message);
    return 1;
  }
}

async function sendChatPush(token, title, body, companyId, chatId, extraData = {}) {
  if (!PUSH_ENABLED || !token) return;
  const data = { type: "chat", companyId, chatId, badge: "1", ...extraData };
  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
    android: { priority: "high", notification: { channelId: "chat_messages" } },
    apns: { payload: { aps: { sound: "default" } }, fcmOptions: {} },
    webpush: {
      notification: { title, body },
      fcmOptions: { link: `${WEB_APP_BASE_URL}/#chat/${companyId}/${chatId}` },
    },
  });
}

/** Firestore-Trigger: Bei neuer Chat-Nachricht → Push an Empfänger senden. */
exports.onNewChatMessage = functions.region("europe-west1").firestore
  .document("kunden/{companyId}/chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const { companyId, chatId } = context.params;
    const msg = snap.data();
    const from = (msg && msg.from) ? String(msg.from).trim() : "";
    if (!from) return;

    try {
      const chatRef = admin.firestore().collection("kunden").doc(companyId).collection("chats").doc(chatId);
      const chatSnap = await chatRef.get();
      const chat = chatSnap.data();
      const participants = (chat && chat.participants && Array.isArray(chat.participants))
        ? chat.participants.map((p) => String(p).trim()).filter(Boolean)
        : [];
      const recipients = participants.filter((p) => p !== from);
      if (recipients.length === 0) return;

      const senderName = (msg.senderName || "Jemand").toString().trim();
      const text = (msg.text || "").toString().trim().slice(0, 80);
      const body = text ? `${senderName}: ${text}` : `${senderName} hat eine Nachricht gesendet`;

      if (!PUSH_ENABLED) return;
      for (const uid of recipients) {
        try {
          const token = await getFcmToken(companyId, uid);
          if (!token) {
            console.log("onNewChatMessage: Kein FCM-Token für uid=" + uid);
            continue;
          }
          const unread = (chat && chat.unreadCount && chat.unreadCount[uid]) || 0;
          const badge = Math.min(99, Math.max(1, Number(unread) + 1));
          const totalUnread = await getTotalUnreadForUser(companyId, uid, chatId);
          const summaryBody = totalUnread === 1
            ? body
            : totalUnread + " ungelesene Nachrichten";
          const payload = {
            token,
            notification: { title: "Neue Chat-Nachricht", body },
            data: {
              type: "chat", companyId, chatId, from,
              badge: String(badge),
              totalUnread: String(totalUnread),
            },
            android: { priority: "high", notification: { channelId: "chat_messages" } },
            apns: { payload: { aps: { badge: totalUnread, sound: "default" } }, fcmOptions: {} },
            webpush: {
              notification: {
                title: totalUnread === 1 ? "Neue Chat-Nachricht" : totalUnread + " ungelesene Nachrichten",
                body: totalUnread === 1 ? body : "Neueste: " + body,
              },
              fcmOptions: { link: `${WEB_APP_BASE_URL}/#chat/${companyId}/${chatId}` },
            },
          };
          await admin.messaging().send(payload);
        } catch (e) {
          console.warn("onNewChatMessage: FCM an", uid, "fehlgeschlagen:", e.message);
        }
      }
    } catch (e) {
      console.error("onNewChatMessage Fehler:", e);
    }
  });

exports.onNewGroupChat = functions.region("europe-west1").firestore
  .document("kunden/{companyId}/chats/{chatId}")
  .onCreate(async (snap, context) => {
    const { companyId, chatId } = context.params;
    const chat = snap.data();
    if ((chat.type || "").toLowerCase() !== "group") return;
    const createdBy = (chat.createdBy || "").trim();
    const participants = (chat.participants && Array.isArray(chat.participants))
      ? chat.participants.map((p) => String(p).trim()).filter(Boolean)
      : [];
    const groupName = (chat.name || "Neue Gruppe").toString().trim();
    const recipients = participants.filter((p) => p !== createdBy);
    if (recipients.length === 0) return;
    if (!PUSH_ENABLED) return;
    try {
      for (const uid of recipients) {
        try {
          const token = await getFcmToken(companyId, uid);
          await sendChatPush(
            token,
            "Zur Gruppe hinzugefügt",
            `Du wurdest zu "${groupName}" hinzugefügt.`,
            companyId,
            chatId,
          );
        } catch (e) {
          console.warn("onNewGroupChat: FCM an", uid, "fehlgeschlagen:", e.message);
        }
      }
    } catch (e) {
      console.error("onNewGroupChat Fehler:", e);
    }
  });

/** Vollständige Löschung eines Mitglieds (DSGVO). Entfernt alle personenbezogenen Daten:
 *  - Firebase Auth Nutzer
 *  - Firestore: mitarbeiter, users, userTiles, fcmTokens
 *  - Storage: Profil-Fotos
 *  - Schichtplan-NFS/Schichtplan-Mitarbeiter (per E-Mail-Match)
 *  Nur Admin/Superadmin/LeiterSSD. */
exports.deleteMitarbeiterFull = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId: companyIdParam, mitarbeiterId, uid: inputUid, fromUsersOnly, email: inputEmail } = data || {};
    const rawCompanyId = (companyIdParam || "").trim();
    if (!rawCompanyId) {
      throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
    }
    const companyId = (await _resolveToDocId(rawCompanyId)) || rawCompanyId.toLowerCase();
    await _requireAdminRole(context, companyId);

    let uid = inputUid ? String(inputUid).trim() : null;
    let email = inputEmail ? String(inputEmail).trim().toLowerCase() : null;
    const usersRef = db.collection("kunden").doc(companyId).collection("users");
    const mitarbeiterRef = db.collection("kunden").doc(companyId).collection("mitarbeiter");

    if (fromUsersOnly && uid) {
      await _deleteUserData(db, companyId, uid, email);
      await usersRef.doc(uid).delete();
      return { success: true };
    }

    const mid = (mitarbeiterId || "").trim();
    if (!mid) {
      throw new functions.https.HttpsError("invalid-argument", "mitarbeiterId erforderlich");
    }
    let mitarbeiterSnap = await mitarbeiterRef.doc(mid).get();
    let byUid = null;
    if (!mitarbeiterSnap.exists) {
      byUid = await mitarbeiterRef.where("uid", "==", mid).limit(1).get();
      if (byUid.empty) {
        throw new functions.https.HttpsError("not-found", "Mitglied nicht gefunden.");
      }
    }
    const mData = mitarbeiterSnap.exists ? mitarbeiterSnap.data() : byUid.docs[0].data();
    const actualMid = mitarbeiterSnap.exists ? mid : byUid.docs[0].id;
    uid = uid || mData?.uid?.toString() || null;
    email = email || mData?.email?.toString()?.trim().toLowerCase() || mData?.pseudoEmail?.toString()?.trim().toLowerCase() || null;

    if (uid) {
      await _deleteUserData(db, companyId, uid, email);
      await usersRef.doc(uid).delete();
    }
    await mitarbeiterRef.doc(actualMid).delete();
    const pseudoEmail = mData?.pseudoEmail?.toString()?.trim().toLowerCase();
    const emailsToMatch = [email, pseudoEmail].filter(Boolean);
    const seenPaths = new Set();
    const toDelete = [];
    for (const em of [...new Set(emailsToMatch)]) {
      const nfsSnap = await db.collection("kunden").doc(companyId).collection("schichtplanNfsMitarbeiter").where("email", "==", em).get();
      nfsSnap.docs.forEach((d) => { if (!seenPaths.has(d.ref.path)) { seenPaths.add(d.ref.path); toDelete.push(d.ref); } });
      const schichtSnap = await db.collection("kunden").doc(companyId).collection("schichtplanMitarbeiter").where("email", "==", em).get();
      schichtSnap.docs.forEach((d) => { if (!seenPaths.has(d.ref.path)) { seenPaths.add(d.ref.path); toDelete.push(d.ref); } });
    }
    const byIdRef = db.collection("kunden").doc(companyId).collection("schichtplanMitarbeiter").doc(actualMid);
    const byId = await byIdRef.get();
    if (byId.exists && !seenPaths.has(byIdRef.path)) toDelete.push(byIdRef);
    if (toDelete.length > 0) {
      const batch = db.batch();
      toDelete.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
    return { success: true };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("deleteMitarbeiterFull Fehler:", e.message || e);
    throw new functions.https.HttpsError("internal", e.message || String(e));
  }
});

async function _deleteUserData(db, companyId, uid, _email) {
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    if (e.code !== "auth/user-not-found") console.warn("deleteMitarbeiterFull auth.deleteUser:", e.message);
  }
  await db.collection("fcmTokens").doc(uid).delete().catch(() => {});
  const userTilesRef = db.collection("kunden").doc(companyId).collection("users").doc(uid).collection("userTiles");
  const tilesSnap = await userTilesRef.get();
  if (!tilesSnap.empty) {
    const batch = db.batch();
    tilesSnap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  const bucket = admin.storage().bucket("rett-fe0fa.firebasestorage.app");
  const [files] = await bucket.getFiles({ prefix: `kunden/${companyId}/profile-images/${uid}` }).catch(() => [[],[],null]);
  await Promise.all((files || []).map((f) => f.delete().catch(() => {})));
}

/** Erstellt neues Mitarbeiter-Dokument (für Neuanlage). Nur Admin/Superadmin/LeiterSSD. */
exports.createMitarbeiterDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    if (!context?.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
    }
    const { companyId: rawCompanyId, data: docData } = data || {};
    const companyId = (await _resolveToDocId(rawCompanyId)) || (rawCompanyId || "").trim().toLowerCase();
    if (companyId) await _requireAdminRole(context, companyId);
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
