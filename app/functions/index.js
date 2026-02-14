const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// Projekt explizit für Auth-Konsistenz (rett-fe0fa = Flutter-App + alle Module)
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "rett-fe0fa" });

const db = admin.firestore();

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
  if (!token) return;
  const data = { type: "chat", companyId, chatId, badge: "1", ...extraData };
  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
    android: { priority: "high", notification: { channelId: "chat_messages" } },
    apns: { payload: { aps: { sound: "default" } }, fcmOptions: {} },
    webpush: {
      notification: { title, body },
      fcmOptions: { link: `https://${companyId}.rettbase.de/#chat/${companyId}/${chatId}` },
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
              fcmOptions: { link: `https://${companyId}.rettbase.de/#chat/${companyId}/${chatId}` },
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
