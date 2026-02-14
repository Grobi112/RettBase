const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const Imap = require("imap");
const { simpleParser } = require("mailparser");

// Initialisiere Admin SDK
// WICHTIG: admin.firestore() umgeht die Security Rules automatisch
// Verwende applicationDefault() für Service Account Credentials
// EXPLIZIT: Projekt-ID rettbase-app (einheitlich für alle RettBase-Systeme)
if (!admin.apps.length) {
  try {
    // Prüfe Environment Variables
    console.log("🔍 Environment Check:");
    console.log(`🔍 GCLOUD_PROJECT: ${process.env.GCLOUD_PROJECT || "nicht gesetzt"}`);
    console.log(`🔍 GOOGLE_APPLICATION_CREDENTIALS: ${process.env.GOOGLE_APPLICATION_CREDENTIALS || "nicht gesetzt"}`);
    
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: "rettbase-app",
      databaseURL: "https://rettbase-app-default-rtdb.firebaseio.com",
    });
    console.log("✅ Admin SDK initialisiert mit Projekt: rettbase-app");
    console.log(`✅ Admin Apps: ${admin.apps.length}`);
    
    // Prüfe ob Firestore verfügbar ist
    const testDb = admin.firestore();
    console.log(`✅ Firestore verfügbar: ${!!testDb}`);
    const app = admin.app();
    console.log(`✅ Firestore Project ID: ${app?.options?.projectId || "unbekannt"}`);
  } catch (error) {
    console.error("❌ Fehler bei Admin SDK Initialisierung:", error);
    console.error("❌ Error Stack:", error.stack);
    // Fallback: Versuche ohne explizite Konfiguration
    try {
      admin.initializeApp();
      console.log("⚠️ Admin SDK mit Fallback initialisiert");
    } catch (fallbackError) {
      console.error("❌ ❌ ❌ KRITISCHER FEHLER: Admin SDK konnte nicht initialisiert werden ❌ ❌ ❌");
      console.error("❌ Fallback Error:", fallbackError);
      throw fallbackError;
    }
  }
}
const db = admin.firestore();
// Stelle sicher, dass Firestore mit den richtigen Einstellungen verwendet wird
db.settings({ ignoreUndefinedProperties: true });
console.log("✅ Firestore Admin SDK bereit");
const app = admin.app();
console.log(`✅ Firestore Project ID: ${app?.options?.projectId || "unbekannt"}`);

// 🔥 TEST: Prüfe ob Admin SDK Firestore-Zugriff funktioniert
async function testAdminFirestoreAccess() {
  try {
    console.log("🔍 TEST: Versuche Admin SDK Firestore-Zugriff auf kunden-Collection...");
    
    // 🔥 WICHTIG: Logge Environment Variables zur Diagnose
    console.log("🔍 🔍 🔍 DIAGNOSE-INFOS 🔍 🔍 🔍");
    console.log(`🔍 GCLOUD_PROJECT: ${process.env.GCLOUD_PROJECT || "NICHT GESETZT"}`);
    console.log(`🔍 FIREBASE_CONFIG: ${process.env.FIREBASE_CONFIG || "NICHT GESETZT"}`);
    if (process.env.FIREBASE_CONFIG) {
      try {
        const firebaseConfig = JSON.parse(process.env.FIREBASE_CONFIG);
        console.log(`🔍 FIREBASE_CONFIG (parsed):`, JSON.stringify(firebaseConfig, null, 2));
      } catch (e) {
        console.log(`🔍 FIREBASE_CONFIG konnte nicht geparst werden`);
      }
    }
    console.log(`🔍 GOOGLE_APPLICATION_CREDENTIALS: ${process.env.GOOGLE_APPLICATION_CREDENTIALS || "NICHT GESETZT"}`);
    
    // Prüfe Admin SDK Status
    const app = admin.app();
    console.log(`🔍 Admin SDK App Options:`, {
      projectId: app?.options?.projectId || "unbekannt",
      credential: app?.options?.credential ? "gesetzt" : "nicht gesetzt",
      databaseURL: app?.options?.databaseURL || "unbekannt"
    });
    
    // Prüfe ob Firestore verfügbar ist
    const testDb = admin.firestore();
    console.log(`🔍 Firestore verfügbar: ${!!testDb}`);
    console.log(`🔍 Firestore Type: ${testDb.constructor.name}`);
    
    // Versuche den Test-Read
    console.log("🔍 Versuche Test-Read auf kunden-Collection...");
    const testSnap = await testDb.collection("kunden").limit(1).get();
    console.log(`✅ ✅ ✅ ADMIN TEST READ OK: ${testSnap.size} Dokumente gefunden ✅ ✅ ✅`);
    console.log(`✅ Admin SDK funktioniert korrekt - Firestore-Zugriff erfolgreich`);
    return true;
  } catch (e) {
    console.error(`❌ ❌ ❌ ADMIN TEST READ FEHLGESCHLAGEN ❌ ❌ ❌`);
    console.error(`❌ Error Code: ${e.code}`);
    console.error(`❌ Error Message: ${e.message}`);
    console.error(`❌ Error Details:`, JSON.stringify(e, null, 2));
    console.error(`❌ Error Stack:`, e.stack);
    console.error(`❌ Das bedeutet: Admin SDK hat keine Firestore-Berechtigung, falsches Projekt, oder Datastore-Modus`);
    console.error(`❌ Mögliche Ursachen:`);
    console.error(`❌ 1. Firestore ist im Datastore-Modus statt Native-Modus`);
    console.error(`❌ 2. Function läuft im falschen GCP-Projekt`);
    console.error(`❌ 3. Service Account hat keine IAM-Berechtigungen (Cloud Datastore User)`);
    return false;
  }
}

/**
 * Cloud Function zum Versenden von E-Mails über Strato SMTP
 * 
 * SMTP-Konfiguration wird über Environment Variables gesetzt:
 * - SMTP_HOST: smtp.strato.de
 * - SMTP_PORT: 587 (oder 465 für SSL)
 * - SMTP_USER: mail@rettbase.de
 * - SMTP_PASS: (Passwort)
 */
exports.sendEmail = functions.region("us-central1").https.onCall(async (data, context) => {
  console.log("📧 sendEmail Function aufgerufen");
  console.log("📧 Context:", context ? "Auth vorhanden" : "Keine Auth");
  console.log("📧 Data:", data);
  
  // Prüfe Authentifizierung
  if (!context || !context.auth) {
    console.error("❌ Keine Authentifizierung");
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Benutzer muss authentifiziert sein"
    );
  }

  const { to, subject, body, fromEmail, fromName, replyTo } = data;
  console.log("📧 E-Mail-Parameter:", { to, subject, fromEmail, fromName, replyTo });

  // Validierung
  if (!to || !subject || !body) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "to, subject und body sind erforderlich"
    );
  }

  // SMTP-Konfiguration aus Environment Variables
  const config = functions.config();
  console.log("📧 Config vorhanden:", !!config.smtp);
  
  const smtpConfig = {
    host: config.smtp?.host || "smtp.strato.de",
    port: parseInt(config.smtp?.port || "587"),
    secure: false, // true für Port 465, false für Port 587
    auth: {
      user: config.smtp?.user || "mail@rettbase.de",
      pass: config.smtp?.pass || "",
    },
  };
  
  console.log("📧 SMTP Config:", { host: smtpConfig.host, port: smtpConfig.port, user: smtpConfig.auth.user });

  // Erstelle Transporter
  const transporter = nodemailer.createTransport(smtpConfig);

  // E-Mail-Optionen
  // WICHTIG: Strato akzeptiert nur E-Mail-Adressen, die als Alias eingerichtet sind
  // Daher verwenden wir immer die Haupt-E-Mail als Absender (from)
  // 🔥 NEU: Bei Antworten verwenden wir die interne E-Mail-Adresse (Alias) als Reply-To
  const mainEmail = smtpConfig.auth.user; // Haupt-E-Mail (mail@rettbase.de)
  const internalEmail = fromEmail && fromEmail !== mainEmail ? fromEmail : null; // Interne E-Mail (falls vorhanden)
  
  // 🔥 NEU: Verwende replyTo wenn übergeben, sonst interne E-Mail-Adresse, sonst Haupt-E-Mail
  // Bei Antworten sollte replyTo die interne E-Mail-Adresse (Alias) des ursprünglichen Absenders sein
  const replyToEmail = replyTo || internalEmail || mainEmail;
  
  console.log(`📧 Reply-To: ${replyToEmail} (replyTo=${replyTo || "nicht gesetzt"}, internalEmail=${internalEmail || "nicht gesetzt"})`);
  
  // 🔥 ENTFERNT: Keine automatische Ergänzung im Betreff mehr
  // Der Betreff wird unverändert verwendet
  let emailSubject = subject;
  
  // 🔥 ENTFERNT: Keine automatische Fußzeile mehr
  // Der E-Mail-Text wird unverändert verwendet
  let emailBody = body;
  let emailBodyHtml = body.replace(/\n/g, "<br>");
  
  const mailOptions = {
    from: `"${fromName || "RettBase"}" <${mainEmail}>`, // Immer Haupt-E-Mail als Absender
    replyTo: replyToEmail, // 🔥 NEU: Reply-To auf interne E-Mail-Adresse (Alias) bei Antworten, sonst Haupt-E-Mail
    to: to,
    subject: emailSubject, // Betreff mit kodierter interner E-Mail-Adresse
    html: emailBodyHtml, // HTML-Version mit Fußzeile
    text: emailBody, // Plain-Text-Version mit Fußzeile
  };
  
  console.log(`📧 E-Mail-Optionen: from=${mainEmail}, replyTo=${replyToEmail}, to=${to}, internalEmail=${internalEmail || "keine"}`);

  try {
    // Versende E-Mail
    const info = await transporter.sendMail(mailOptions);
    console.log("✅ E-Mail erfolgreich versendet:", info.messageId);
    return {
      success: true,
      messageId: info.messageId,
    };
  } catch (error) {
    console.error("❌ Fehler beim Versenden der E-Mail:", error);
    throw new functions.https.HttpsError(
      "internal",
      "Fehler beim Versenden der E-Mail: " + error.message
    );
  }
});

/**
 * Cloud Function zum Löschen von E-Mails aus mail@rettbase.de
 * Wird aufgerufen, wenn eine E-Mail endgültig gelöscht wird
 */
exports.deleteEmailFromMailbox = functions.region("us-central1").https.onCall(async (data, context) => {
  console.log("🗑️ deleteEmailFromMailbox Function aufgerufen");
  console.log("🗑️ Context:", context ? "Auth vorhanden" : "Keine Auth");
  console.log("🗑️ Data:", data);
  
  // Prüfe Authentifizierung
  if (!context || !context.auth) {
    console.error("❌ Keine Authentifizierung");
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Benutzer muss authentifiziert sein"
    );
  }

  const { subject, to, from } = data;
  console.log("🗑️ E-Mail-Parameter:", { subject, to, from });

  // Validierung
  if (!subject) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "subject ist erforderlich"
    );
  }

  const config = functions.config();
  const imapConfig = {
    user: config.imap?.user || config.smtp?.user || "mail@rettbase.de",
    password: config.imap?.pass || config.smtp?.pass || "",
    host: config.imap?.host || "imap.strato.de",
    port: 993,
    tls: true,
    tlsOptions: { rejectUnauthorized: false },
  };

  return new Promise((resolve, reject) => {
    const imap = new Imap(imapConfig);
    
    imap.once("ready", () => {
      console.log("✅ IMAP-Verbindung hergestellt");
      imap.openBox("INBOX", false, (err, box) => {
        if (err) {
          console.error("❌ Fehler beim Öffnen des Postfachs:", err);
          imap.end();
          reject(err);
          return;
        }
        
        // Suche nach E-Mail mit passendem Betreff
        imap.search([["SUBJECT", subject]], (err, results) => {
          if (err) {
            console.error("❌ Fehler bei der E-Mail-Suche:", err);
            imap.end();
            reject(err);
            return;
          }
          
          if (!results || results.length === 0) {
            console.log("⚠️ Keine E-Mail mit diesem Betreff gefunden");
            imap.end();
            resolve({ deleted: false, reason: "not_found" });
            return;
          }
          
          console.log(`🗑️ ${results.length} E-Mail(s) mit Betreff "${subject}" gefunden`);
          
          // Lösche alle gefundenen E-Mails
          imap.setFlags(results, "\\Deleted", (err) => {
            if (err) {
              console.error("❌ Fehler beim Markieren der E-Mails als gelöscht:", err);
              imap.end();
              reject(err);
              return;
            }
            
            // Expunge (endgültig löschen)
            imap.expunge((err) => {
              if (err) {
                console.error("❌ Fehler beim endgültigen Löschen:", err);
                imap.end();
                reject(err);
                return;
              }
              
              console.log(`✅ ${results.length} E-Mail(s) erfolgreich gelöscht`);
              imap.end();
              resolve({ deleted: true, count: results.length });
            });
          });
        });
      });
    });
    
    imap.once("error", (err) => {
      console.error("❌ IMAP-Fehler:", err);
      reject(err);
    });
    
    imap.connect();
  });
});

/**
 * Cloud Function zum Verarbeiten eingehender E-Mails
 * Prüft regelmäßig das Postfach mail@rettbase.de auf neue E-Mails
 * und leitet sie an die richtige interne E-Mail-Adresse weiter
 */
exports.processIncomingEmails = functions.region("us-central1").pubsub
  .schedule("every 1 minutes")
  .onRun(async (context) => {
    // 🔥 TEST: Prüfe Admin SDK Firestore-Zugriff am Anfang jeder Ausführung
    const adminTestOk = await testAdminFirestoreAccess();
    if (!adminTestOk) {
      console.error("❌ ❌ ❌ KRITISCH: Admin SDK Firestore-Zugriff fehlgeschlagen - Function wird abgebrochen ❌ ❌ ❌");
      return null;
    }
    console.log("📥 Prüfe auf eingehende E-Mails...");
    
    const config = functions.config();
    const imapConfig = {
      user: config.imap?.user || config.smtp?.user || "mail@rettbase.de",
      password: config.imap?.pass || config.smtp?.pass || "",
      host: config.imap?.host || "imap.strato.de",
      port: 993,
      tls: true,
      tlsOptions: { rejectUnauthorized: false },
    };
    
    return new Promise((resolve, reject) => {
      const imap = new Imap(imapConfig);
      
      imap.once("ready", () => {
        console.log("✅ IMAP-Verbindung hergestellt");
        imap.openBox("INBOX", false, (err, box) => {
          if (err) {
            console.error("❌ Fehler beim Öffnen des Postfachs:", err);
            imap.end();
            reject(err);
            return;
          }
          
          // Funktion zum Verarbeiten gefundener E-Mails
          const processFoundEmails = (results) => {
            if (!results || results.length === 0) {
              console.log("📭 Keine E-Mails gefunden");
              imap.end();
              resolve({ processed: 0, reason: "no_emails" });
              return;
            }
            
            console.log(`📧 ${results.length} E-Mail(s) gefunden`);
            
            const fetch = imap.fetch(results, { bodies: "" });
            const emails = [];
            const emailUids = []; // Speichere UIDs für erfolgreich verarbeitete E-Mails
            
            console.log(`📥 Beginne E-Mail-Fetch für ${results.length} E-Mail(s)...`);
            
            fetch.on("message", (msg, seqno) => {
              console.log(`📧 Lade E-Mail ${seqno}...`);
              let emailData = "";
              let emailUid = null;
              
              // Speichere UID der E-Mail
              msg.once("attributes", (attrs) => {
                emailUid = attrs.uid;
              });
              
              msg.on("body", (stream, info) => {
                stream.on("data", (chunk) => {
                  emailData += chunk.toString("utf8");
                });
              });
              
              msg.once("end", () => {
                simpleParser(emailData)
                  .then((parsed) => {
                    emails.push({ email: parsed, uid: emailUid });
                  })
                  .catch((err) => {
                    console.error(`❌ Fehler beim Parsen der E-Mail ${seqno}:`, err);
                  });
              });
            });
            
            fetch.once("end", async () => {
              // Warte kurz, damit alle E-Mails geparst sind
              await new Promise(resolveTimeout => setTimeout(resolveTimeout, 2000));
              
              console.log(`📧 ${emails.length} E-Mail(s) geparst, beginne Verarbeitung...`);
              
              if (emails.length === 0) {
                console.log("⚠️ Keine E-Mails zum Verarbeiten gefunden");
                imap.end();
                resolve({ processed: 0, reason: "no_emails_parsed" });
                return;
              }
              
              // Verarbeite alle E-Mails
              try {
                const results = await Promise.all(
                  emails.map(async ({ email, uid }) => {
                    try {
                      // Extrahiere interne E-Mail-Adresse aus dem Betreff oder E-Mail-Text
                      const subject = email.subject || "";
                      const emailText = email.text || email.html || "";
                      const inReplyTo = email.inReplyTo || email.headers?.get("in-reply-to") || "";
                      const references = email.references || email.headers?.get("references") || "";
                      
                      console.log(`📧 ========== NEUE E-MAIL GEFUNDEN ==========`);
                      console.log(`📧 E-Mail-Betreff: ${subject}`);
                      console.log(`📧 E-Mail-Details:`, {
                        from: email.from?.value?.[0]?.address || email.from?.text,
                        to: email.to?.value?.[0]?.address || email.to?.text,
                        replyTo: email.replyTo?.value?.[0]?.address || email.replyTo?.text,
                        subject: subject,
                        inReplyTo: inReplyTo,
                        references: references,
                        date: email.date
                      });
                      console.log(`📧 E-Mail-Text (erste 200 Zeichen): ${(emailText || "").substring(0, 200)}`);
                      
                      let internalEmail = null;
                      
                      // 🔥 HELPER: Prüfe ob eine E-Mail-Adresse eine RettBase-Domain hat (inkl. Subdomains)
                      function isRettbaseDomain(email) {
                        if (!email || typeof email !== "string") return false;
                        const at = email.lastIndexOf("@");
                        if (at === -1) return false;
                        const domain = email.slice(at + 1).toLowerCase();
                        return domain === "rettbase.de" || domain.endsWith(".rettbase.de");
                      }
                      
                      // Prüfe ob es eine Antwort ist ODER eine direkte E-Mail an mail@rettbase.de
                      const isReply = inReplyTo || references || subject.toLowerCase().startsWith("re:") || subject.toLowerCase().startsWith("re :");
                      const toAddress = email.to?.value?.[0]?.address || email.to?.text || "";
                      const isDirectEmail = toAddress.toLowerCase() === "mail@rettbase.de" || isRettbaseDomain(toAddress);
                      
                      console.log(`📧 Reply-Detection: inReplyTo=${!!inReplyTo}, references=${!!references}, subject starts with "re:"=${subject.toLowerCase().startsWith("re:")}`);
                      console.log(`📧 isReply=${isReply}, toAddress=${toAddress}`);
                      
                      // 🔥 WICHTIG: Prüfe ALLE Empfänger (to, cc, bcc) für Alias-E-Mails
                      const allRecipients = [];
                      
                      // Extrahiere alle Empfänger aus to
                      if (email.to?.value && Array.isArray(email.to.value)) {
                        for (const addrObj of email.to.value) {
                          if (addrObj && addrObj.address) {
                            allRecipients.push(addrObj.address);
                          }
                        }
                      }
                      
                      // Extrahiere alle Empfänger aus cc
                      if (email.cc?.value && Array.isArray(email.cc.value)) {
                        for (const addrObj of email.cc.value) {
                          if (addrObj && addrObj.address) {
                            allRecipients.push(addrObj.address);
                          }
                        }
                      }
                      
                      // Extrahiere alle Empfänger aus bcc
                      if (email.bcc?.value && Array.isArray(email.bcc.value)) {
                        for (const addrObj of email.bcc.value) {
                          if (addrObj && addrObj.address) {
                            allRecipients.push(addrObj.address);
                          }
                        }
                      }
                      
                      // Fallback: Wenn toAddress vorhanden ist, aber nicht in allRecipients
                      if (toAddress && !allRecipients.includes(toAddress)) {
                        allRecipients.push(toAddress);
                      }
                      
                      console.log(`📧 E-Mail-Typ: isReply=${isReply}, isDirectEmail=${isDirectEmail}`);
                      console.log(`📧 To-Adresse: ${toAddress}`);
                      console.log(`📧 email.to?.value:`, JSON.stringify(email.to?.value));
                      console.log(`📧 Alle Empfänger: ${JSON.stringify(allRecipients)}`);
                      
                      // 🔥 PRIORITÄT 1: Prüfe zuerst, ob die E-Mail direkt an eine Alias-E-Mail (@rettbase.de) gerichtet ist
                      // Das ist der einfachste Fall: E-Mail kommt direkt an die interne E-Mail-Adresse
                      // Unterstützt auch Subdomains wie admin-testfirma@testfirma.rettbase.de
                      // WICHTIG: Dies hat Priorität, auch bei Antworten!
                      console.log(`🔍 Prüfe ${allRecipients.length} Empfänger auf Alias-E-Mails...`);
                      console.log(`🔍 Aktueller internalEmail-Wert: ${internalEmail || "null/undefined"}`);
                      
                      // WICHTIG: Prüfe JEDEN Empfänger explizit
                      for (let i = 0; i < allRecipients.length; i++) {
                        const addr = allRecipients[i];
                        console.log(`🔍 [${i+1}/${allRecipients.length}] Prüfe Empfänger: "${addr}" (Typ: ${typeof addr})`);
                        
                        if (!addr) {
                          console.log(`⚠️ Empfänger [${i+1}] ist null/undefined/empty`);
                          continue;
                        }
                        
                        // Konvertiere zu String und normalisiere
                        const addrStr = String(addr).trim();
                        const addrLower = addrStr.toLowerCase();
                        console.log(`🔍 [${i+1}] Normalisiert: "${addrLower}"`);
                        
                        // 🔥 KORREKT: Prüfe die Domain nach dem @ (inkl. Subdomains)
                        const isRettbase = isRettbaseDomain(addrLower);
                        
                        // Extrahiere Domain für Logging
                        const at = addrLower.lastIndexOf("@");
                        const domain = at !== -1 ? addrLower.slice(at + 1) : "keine Domain";
                        console.log(`🔍 [${i+1}] Extrahierte Domain: "${domain}"`);
                        console.log(`🔍 [${i+1}] Ist RettBase-Domain? ${isRettbase} (domain === "rettbase.de" oder domain.endsWith(".rettbase.de"))`);
                        
                        if (isRettbase) {
                          // Verwende die vollständige E-Mail-Adresse (inkl. Subdomain falls vorhanden)
                          // z.B. admin-testfirma@testfirma.rettbase.de oder breuer@reinoldus.rettbase.de
                          internalEmail = addrLower.trim();
                          console.log(`✅ ✅ ✅ ALIAS-E-MAIL GEFUNDEN IM TO-FELD: ${internalEmail} ✅ ✅ ✅`);
                          console.log(`✅ Diese E-Mail ist direkt an die interne E-Mail-Adresse gerichtet`);
                          console.log(`✅ internalEmail wurde gesetzt auf: "${internalEmail}"`);
                          break;
                        } else {
                          console.log(`⚠️ [${i+1}] Empfänger "${addrLower}" enthält NICHT "@rettbase.de"`);
                        }
                      }
                      
                      console.log(`🔍 Nach Schleife - internalEmail: "${internalEmail || "null/undefined"}"`);
                      
                      // 🔥 PRIORITÄT 2: Wenn keine direkte Alias-E-Mail gefunden wurde UND es eine Antwort ist,
                      // suche nach der ursprünglichen E-Mail in Firestore
                      if (!internalEmail && isReply) {
                        console.log(`📧 Dies ist eine Antwort-E-Mail`);
                        console.log(`📧 Betreff der Antwort: ${subject}`);
                        console.log(`📧 E-Mail-Text (erste 500 Zeichen): ${(emailText || "").substring(0, 500)}`);
                        
                        // WICHTIG: Bei Antworten ist die interne E-Mail-Adresse normalerweise NICHT mehr im Betreff
                        // Sie muss aus der ursprünglichen E-Mail in Firestore extrahiert werden
                        
                        // Suche nach der ursprünglichen E-Mail in Firestore
                        let companiesSnapshot;
                        try {
                          // Verwende admin.firestore() - umgeht Security Rules
                          console.log("🔍 Versuche Firestore-Zugriff auf kunden-Collection...");
                          console.log("🔍 Admin SDK Status:", admin.apps.length > 0 ? "Initialisiert" : "NICHT initialisiert");
                          // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                          const adminDb = admin.firestore();
                          companiesSnapshot = await adminDb.collection("kunden").get();
                          console.log(`✅ ${companiesSnapshot.size} Firmen gefunden`);
                        } catch (firestoreError) {
                          console.error("❌ ❌ ❌ FEHLER BEIM FIRESTORE-ZUGRIFF ❌ ❌ ❌");
                          console.error("❌ Firestore Error Code:", firestoreError.code);
                          console.error("❌ Firestore Error Message:", firestoreError.message);
                          console.error("❌ Firestore Error Details:", JSON.stringify(firestoreError, null, 2));
                          console.error("❌ Admin SDK Apps:", admin.apps.length);
                          // Versuche trotzdem, die interne E-Mail-Adresse aus dem Betreff zu extrahieren
                          companiesSnapshot = { docs: [] };
                        }
                        
                        for (const companyDoc of companiesSnapshot.docs) {
                          // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                          const adminDb = admin.firestore();
                          const emailsRef = adminDb
                            .collection("kunden")
                            .doc(companyDoc.id)
                            .collection("emails");
                          
                          // Lade alle E-Mails (ohne where-Filter, um Index-Probleme zu vermeiden)
                          let allEmailsSnapshot;
                          try {
                            allEmailsSnapshot = await emailsRef
                              .limit(500)
                              .get();
                            console.log(`✅ ${allEmailsSnapshot.size} E-Mails in Firma ${companyDoc.id} geladen`);
                          } catch (firestoreError) {
                            console.error(`❌ Fehler beim Laden der E-Mails für Firma ${companyDoc.id}:`, firestoreError);
                            console.error(`❌ Firestore Error Code:`, firestoreError.code);
                            console.error(`❌ Firestore Error Message:`, firestoreError.message);
                            continue; // Überspringe diese Firma
                          }
                          
                          // Filtere clientseitig nach draft=false und deleted=false
                          const sentEmails = allEmailsSnapshot.docs.filter(emailDoc => {
                            const emailData = emailDoc.data();
                            return emailData.draft === false && emailData.deleted === false;
                          });
                          
                          console.log(`✅ ${sentEmails.length} gesendete E-Mails (nach Filterung) in Firma ${companyDoc.id}`);
                          
                          // Sortiere E-Mails nach Datum (neueste zuerst)
                          const sortedEmails = sentEmails.sort((a, b) => {
                            const aDate = a.data().createdAt?.toMillis?.() || 0;
                            const bDate = b.data().createdAt?.toMillis?.() || 0;
                            return bDate - aDate;
                          });
                          
                          // Prüfe ob eine der gesendeten E-Mails zum Betreff passt
                          console.log(`🔍 Suche nach ursprünglicher E-Mail für Betreff: "${subject}"`);
                          console.log(`🔍 Prüfe ${sortedEmails.length} E-Mails (neueste 200)...`);
                          
                          for (const emailDoc of sortedEmails.slice(0, 200)) {
                            const emailData = emailDoc.data();
                            const originalSubject = emailData.subject || "";
                            
                            // Entferne "Re:" oder "RE:" vom aktuellen Betreff und vergleiche
                            // Entferne auch [Von: ...] vom aktuellen Betreff (falls vorhanden)
                            let cleanSubject = subject.replace(/^(re|RE|RE:|Re:):\s*/i, "").replace(/\[Von: [^\]]+\]/, "").trim();
                            let cleanOriginalSubject = originalSubject.replace(/\[Von: [^\]]+\]/, "").trim();
                            
                            // Normalisiere
                            cleanSubject = cleanSubject.toLowerCase().trim();
                            cleanOriginalSubject = cleanOriginalSubject.toLowerCase().trim();
                            
                            // Prüfe ob der Betreff übereinstimmt (toleranter Vergleich)
                            const subjectMatches = cleanSubject === cleanOriginalSubject ||
                                cleanSubject.includes(cleanOriginalSubject) ||
                                cleanOriginalSubject.includes(cleanSubject) ||
                                (cleanSubject.length > 10 && cleanOriginalSubject.length > 10 && 
                                 cleanSubject.substring(0, Math.min(cleanSubject.length, cleanOriginalSubject.length, 20)) === 
                                 cleanOriginalSubject.substring(0, Math.min(cleanSubject.length, cleanOriginalSubject.length, 20)));
                            
                            if (subjectMatches) {
                              console.log(`✅ ✅ ✅ URSPRÜNGLICHE E-MAIL GEFUNDEN ✅ ✅ ✅`);
                              console.log(`✅ Betreff-Vergleich: "${cleanSubject}" passt zu "${cleanOriginalSubject}"`);
                              console.log(`✅ Original-Betreff: ${originalSubject}`);
                              console.log(`✅ fromEmail: ${emailData.fromEmail}`);
                              console.log(`✅ toEmail: ${emailData.toEmail}`);
                              console.log(`✅ isExternal: ${emailData.isExternal || false}`);
                              
                              // WICHTIG: Bei externen E-Mails ist fromEmail die interne E-Mail-Adresse des Absenders
                              // Prüfe zuerst, ob fromEmail eine interne E-Mail ist (mit isRettbaseDomain)
                              if (emailData.fromEmail && isRettbaseDomain(emailData.fromEmail)) {
                                internalEmail = emailData.fromEmail.toLowerCase().trim();
                                console.log(`✅ ✅ ✅ INTERNE E-MAIL-ADRESSE GEFUNDEN: ${internalEmail} ✅ ✅ ✅`);
                                console.log(`✅ Interne E-Mail-Adresse des ursprünglichen Absenders (fromEmail): ${internalEmail}`);
                                break; // WICHTIG: Sofort abbrechen, wenn gefunden
                              } else {
                                // Versuche aus dem Betreff zu extrahieren ([Von: ...])
                                const subjectMatch = originalSubject.match(/\[Von: ([^\]]+)\]/);
                                if (subjectMatch) {
                                  internalEmail = subjectMatch[1].toLowerCase().trim();
                                  console.log(`✅ Interne E-Mail-Adresse aus Betreff extrahiert: ${internalEmail}`);
                                  break; // WICHTIG: Sofort abbrechen, wenn gefunden
                                } else {
                                  console.log(`⚠️ Ursprüngliche E-Mail gefunden, aber keine interne E-Mail-Adresse identifizierbar`);
                                  console.log(`⚠️ fromEmail: ${emailData.fromEmail}, toEmail: ${emailData.toEmail}`);
                                  console.log(`⚠️ Prüfe ob fromEmail eine RettBase-Domain ist: ${emailData.fromEmail ? isRettbaseDomain(emailData.fromEmail) : "keine fromEmail"}`);
                                }
                              }
                            }
                          }
                          
                          if (internalEmail) {
                            console.log(`✅ ✅ ✅ INTERNE E-MAIL-ADRESSE AUS URSPRÜNGLICHER E-MAIL GEFUNDEN: ${internalEmail} ✅ ✅ ✅`);
                            break; // Breche auch die Firmen-Schleife ab
                          }
                          
                          if (internalEmail) break;
                        }
                      }
                      
                      // Falls keine Antwort oder ursprüngliche E-Mail nicht gefunden, versuche andere Methoden
                      if (!internalEmail) {
                        console.log(`🔍 Versuche interne E-Mail-Adresse aus Betreff/Text zu extrahieren...`);
                        console.log(`🔍 isReply: ${isReply}, isDirectEmail: ${isDirectEmail}`);
                        
                        // 1. Suche nach [Von: ...] im Betreff (nur bei direkten E-Mails, nicht bei Antworten)
                        if (!isReply) {
                          let match = subject.match(/\[Von: ([^\]]+)\]/);
                          if (match) {
                            internalEmail = match[1].trim().toLowerCase();
                            console.log(`✅ Interne E-Mail aus Betreff extrahiert: ${internalEmail}`);
                          }
                        }
                        
                        // 2. Falls nicht im Betreff, versuche aus dem E-Mail-Text zu extrahieren
                        if (!internalEmail && emailText) {
                          // Suche nach [Von: ...]
                          let match = emailText.match(/\[Von: ([^\]]+)\]/);
                          if (match) {
                            internalEmail = match[1].trim().toLowerCase();
                            console.log(`✅ Interne E-Mail aus E-Mail-Text ([Von: ...]) extrahiert: ${internalEmail}`);
                          }
                          
                          // Suche nach "Antworten bitte an:" (könnte in der ursprünglichen E-Mail enthalten sein)
                          if (!internalEmail) {
                            match = emailText.match(/Antworten bitte an:\s*([^\s\n<]+@[^\s\n<]+)/i);
                            if (match) {
                              internalEmail = match[1].trim().toLowerCase();
                              console.log(`✅ Interne E-Mail aus E-Mail-Text (Antworten bitte an:) extrahiert: ${internalEmail}`);
                            }
                          }
                        }
                        
                        // 3. Versuche auch aus HTML-Body zu extrahieren (falls vorhanden)
                        if (!internalEmail && email.html) {
                          // Suche nach "Antworten bitte an:" mit Link
                          let match = email.html.match(/Antworten bitte an:\s*<a[^>]*>([^<]+@[^<]+)<\/a>/i);
                          if (match) {
                            internalEmail = match[1].trim().toLowerCase();
                            console.log(`✅ Interne E-Mail aus HTML-Body (Antworten bitte an: mit Link) extrahiert: ${internalEmail}`);
                          }
                          
                          // Suche nach "Antworten bitte an:" ohne Link
                          if (!internalEmail) {
                            match = email.html.match(/Antworten bitte an:\s*([^\s\n<]+@[^\s\n<]+)/i);
                            if (match) {
                              internalEmail = match[1].trim().toLowerCase();
                              console.log(`✅ Interne E-Mail aus HTML-Body (Antworten bitte an: ohne Link) extrahiert: ${internalEmail}`);
                            }
                          }
                        }
                        
                        // 4. Falls es eine direkte E-Mail an mail@rettbase.de ist, versuche die interne E-Mail aus dem Betreff zu extrahieren
                        if (!internalEmail && isDirectEmail) {
                          console.log(`📧 Direkte E-Mail an mail@rettbase.de, versuche interne Adresse zu finden...`);
                        }
                      }
                      
                      if (!internalEmail) {
                        console.log(`⚠️ ⚠️ ⚠️ KEINE INTERNE E-MAIL-ADRESSE GEFUNDEN ⚠️ ⚠️ ⚠️`);
                        console.log(`⚠️ Betreff: ${subject}`);
                        console.log(`⚠️ To-Adresse: ${toAddress}`);
                        console.log(`⚠️ Alle Empfänger: ${JSON.stringify(allRecipients)}`);
                        console.log(`⚠️ E-Mail-Text (erste 500 Zeichen): ${(emailText || "").substring(0, 500)}`);
                        console.log(`⚠️ isReply: ${isReply}, isDirectEmail: ${isDirectEmail}`);
                        console.log(`⚠️ E-Mail-Header:`, {
                          from: email.from?.value?.[0]?.address || email.from?.text,
                          to: email.to?.value?.map(addr => addr.address) || email.to?.text,
                          cc: email.cc?.value?.map(addr => addr.address) || email.cc?.text,
                          subject: subject
                        });
                        console.log(`⚠️ email.to?.value (roh):`, JSON.stringify(email.to?.value, null, 2));
                        console.log(`⚠️ email.to?.text:`, email.to?.text);
                        return null;
                      }
                      
                      console.log(`✅ ✅ ✅ INTERNE E-MAIL-ADRESSE GEFUNDEN: ${internalEmail} ✅ ✅ ✅`);
                      
                      console.log(`✅ ✅ ✅ INTERNE E-MAIL-ADRESSE GEFUNDEN: ${internalEmail} ✅ ✅ ✅`);
                      
                      // Finde den Benutzer mit dieser internen E-Mail-Adresse
                      // Versuche zuerst über schichtplanMitarbeiter (da dort die internalEmail gespeichert ist)
                      let foundUser = null;
                      let companyId = null;
                      
                      console.log(`🔍 Suche nach Benutzer mit interner E-Mail: ${internalEmail}`);
                      
                      // Suche in allen Firmen nach schichtplanMitarbeiter mit dieser internalEmail
                      let companiesSnapshot2;
                      try {
                        console.log("🔍 Versuche Firestore-Zugriff auf kunden-Collection (Benutzer-Suche)...");
                        console.log(`🔍 Admin SDK Status: ${admin.apps.length > 0 ? "Initialisiert" : "NICHT initialisiert"}`);
                        const app = admin.app();
                        console.log(`🔍 Firestore Project ID: ${app?.options?.projectId || "unbekannt"}`);
                        console.log(`🔍 Verwende Admin SDK: ${db.constructor.name === "Firestore" ? "Ja" : "Nein"}`);
                        
                        // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                        const adminDb = admin.firestore();
                        companiesSnapshot2 = await adminDb.collection("kunden").get();
                        console.log(`✅ ${companiesSnapshot2.size} Firmen für Benutzer-Suche gefunden`);
                      } catch (firestoreError) {
                        console.error("❌ ❌ ❌ FEHLER BEIM FIRESTORE-ZUGRIFF (Benutzer-Suche) ❌ ❌ ❌");
                        console.error("❌ Firestore Error Code:", firestoreError.code);
                        console.error("❌ Firestore Error Message:", firestoreError.message);
                        console.error("❌ Firestore Error Details:", JSON.stringify(firestoreError, null, 2));
                        console.error("❌ Admin SDK Apps:", admin.apps.length);
                        const app = admin.app();
                        console.error("❌ Firestore Project ID:", app?.options?.projectId || "unbekannt");
                        companiesSnapshot2 = { docs: [] };
                      }
                      
                      for (const companyDoc of companiesSnapshot2.docs) {
                        try {
                          // Lade alle Mitarbeiter der Firma (ohne where-Filter, um Index-Probleme zu vermeiden)
                          // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                          const adminDb = admin.firestore();
                          const allMitarbeiterSnapshot = await adminDb
                            .collection("kunden")
                            .doc(companyDoc.id)
                            .collection("schichtplanMitarbeiter")
                            .get();
                          
                          console.log(`🔍 Firma ${companyDoc.id}: ${allMitarbeiterSnapshot.size} Mitarbeiter insgesamt geladen`);
                          
                          // Filtere clientseitig nach internalEmail (case-insensitive)
                          const matchingMitarbeiter = allMitarbeiterSnapshot.docs.find(mitarbeiterDoc => {
                            const mitarbeiterData = mitarbeiterDoc.data();
                            const storedInternalEmail = (mitarbeiterData.internalEmail || "").toLowerCase().trim();
                            return storedInternalEmail === internalEmail;
                          });
                          
                          if (matchingMitarbeiter) {
                            companyId = companyDoc.id;
                            const mitarbeiterData = matchingMitarbeiter.data();
                            console.log(`✅ Mitarbeiter gefunden in Firma ${companyId}:`, {
                              email: mitarbeiterData.email,
                              internalEmail: mitarbeiterData.internalEmail,
                              vorname: mitarbeiterData.vorname,
                              nachname: mitarbeiterData.nachname
                            });
                            
                            // Finde den zugehörigen User (über Login-E-Mail) - auch hier clientseitige Filterung
                            // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                            const adminDb = admin.firestore();
                            const allUsersSnapshot = await adminDb
                              .collection("kunden")
                              .doc(companyId)
                              .collection("users")
                              .get();
                            
                            const matchingUser = allUsersSnapshot.docs.find(userDoc => {
                              const userData = userDoc.data();
                              return userData.email === mitarbeiterData.email;
                            });
                            
                            if (matchingUser) {
                              foundUser = matchingUser;
                              console.log(`✅ User gefunden: ${foundUser.id} in Firma ${companyId}`);
                              break;
                            } else {
                              console.log(`⚠️ Kein User-Account für Mitarbeiter ${mitarbeiterData.email} gefunden`);
                            }
                          } else {
                            console.log(`🔍 Firma ${companyDoc.id}: Kein Mitarbeiter mit internalEmail ${internalEmail} gefunden`);
                          }
                        } catch (firestoreError) {
                          console.error(`❌ Fehler beim Suchen in Firma ${companyDoc.id}:`, firestoreError);
                          console.error(`❌ Firestore Error Code:`, firestoreError.code);
                          console.error(`❌ Firestore Error Message:`, firestoreError.message);
                          continue;
                        }
                      }
                      
                      // Falls nicht gefunden, versuche auch über users collection in jeder Firma (falls internalEmail dort gespeichert ist)
                      // Lade alle User und filtere clientseitig, um Index-Probleme zu vermeiden
                      if (!foundUser) {
                        console.log(`🔍 Versuche direkte Suche in users-Collection jeder Firma (clientseitige Filterung)...`);
                        for (const companyDoc of companiesSnapshot2.docs) {
                          try {
                            // Lade alle User der Firma (ohne where-Filter, um Index-Probleme zu vermeiden)
                            // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                            const adminDb = admin.firestore();
                            const allUsersSnapshot = await adminDb
                              .collection("kunden")
                              .doc(companyDoc.id)
                              .collection("users")
                              .get();
                            
                            console.log(`🔍 Firma ${companyDoc.id}: ${allUsersSnapshot.size} User insgesamt geladen`);
                            
                            // Filtere clientseitig nach internalEmail (case-insensitive)
                            const matchingUser = allUsersSnapshot.docs.find(userDoc => {
                              const userData = userDoc.data();
                              const storedInternalEmail = (userData.internalEmail || "").toLowerCase().trim();
                              return storedInternalEmail === internalEmail;
                            });
                            
                            if (matchingUser) {
                              foundUser = matchingUser;
                              companyId = companyDoc.id;
                              console.log(`✅ User über users-Collection gefunden: ${foundUser.id} in Firma ${companyId}`);
                              break;
                            } else {
                              console.log(`🔍 Firma ${companyDoc.id}: Kein User mit internalEmail ${internalEmail} gefunden`);
                            }
                          } catch (firestoreError) {
                            console.error(`❌ Fehler beim Suchen in users-Collection für Firma ${companyDoc.id}:`, firestoreError);
                            console.error(`❌ Firestore Error Code:`, firestoreError.code);
                            console.error(`❌ Firestore Error Message:`, firestoreError.message);
                            continue;
                          }
                        }
                      }
                      
                      if (!foundUser) {
                        console.log(`⚠️ ⚠️ ⚠️ KEIN BENUTZER GEFUNDEN ⚠️ ⚠️ ⚠️`);
                        console.log(`⚠️ Interne E-Mail: ${internalEmail}`);
                        console.log(`⚠️ Gesucht wurde in: schichtplanMitarbeiter und users`);
                        console.log(`⚠️ Anzahl Firmen durchsucht: ${companiesSnapshot2?.size || 0}`);
                        return null;
                      }
                      
                      console.log(`✅ ✅ ✅ BENUTZER GEFUNDEN ✅ ✅ ✅`);
                      console.log(`✅ User ID: ${foundUser.id}`);
                      console.log(`✅ Firma: ${companyId}`);
                        
                      // Speichere E-Mail im internen System
                      const userData = foundUser.data();
                      const userName = userData.name || `${userData.vorname || ""} ${userData.nachname || ""}`.trim() || internalEmail;
                      
                      // WICHTIG: Bei eingehenden E-Mails ist:
                      // - from: externe E-Mail-Adresse (nicht User-ID, da es ein externer Absender ist)
                      // - to: interne User-ID (foundUser.id) - damit loadInbox() die E-Mail findet
                      const externalFromEmail = email.from?.value?.[0]?.address || email.from?.text || "unbekannt@example.com";
                      const externalFromName = email.from?.value?.[0]?.name || email.from?.text || "Unbekannt";
                      
                      const emailData = {
                        from: null, // Externer Absender hat keine User-ID
                        fromEmail: externalFromEmail,
                        fromName: externalFromName,
                        to: foundUser.id, // WICHTIG: User-ID des internen Empfängers
                        toEmail: internalEmail,
                        toName: userName,
                        subject: subject.replace(/ \[Von: [^\]]+\]/, "").trim(),
                        body: email.text || email.html || "",
                        read: false,
                        draft: false,
                        deleted: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        isReply: isReply || false,
                        isExternal: true, // Markiere als externe E-Mail
                      };
                      
                      try {
                        // WICHTIG: Verwende explizit admin.firestore() um sicherzustellen, dass Admin SDK verwendet wird
                        const adminDb = admin.firestore();
                        const emailRef = await adminDb
                          .collection("kunden")
                          .doc(companyId)
                          .collection("emails")
                          .add(emailData);
                        
                        console.log(`✅ ✅ ✅ E-MAIL ERFOLGREICH GESPEICHERT ✅ ✅ ✅`);
                        console.log(`✅ E-Mail-ID: ${emailRef.id}`);
                        console.log(`✅ Für: ${internalEmail}`);
                        console.log(`✅ User: ${foundUser.id}`);
                        console.log(`✅ Firma: ${companyId}`);
                        console.log(`✅ Betreff: ${emailData.subject}`);
                        return { success: true, internalEmail, companyId, userId: foundUser.id, emailId: emailRef.id, uid: uid };
                      } catch (saveError) {
                        console.error(`❌ ❌ ❌ FEHLER BEIM SPEICHERN ❌ ❌ ❌`);
                        console.error(`❌ Save Error Code:`, saveError.code);
                        console.error(`❌ Save Error Message:`, saveError.message);
                        console.error(`❌ Save Error Details:`, JSON.stringify(saveError, null, 2));
                        return null;
                      }
                    } catch (error) {
                      console.error("❌ Fehler beim Verarbeiten der E-Mail:", error);
                      console.error("❌ Error Stack:", error.stack);
                      return null;
                    }
                  })
                );
                
                const processed = results.filter((r) => r !== null && r.success);
                console.log(`✅ ${processed.length} E-Mail(s) erfolgreich verarbeitet`);
                
                // 🔥 NEU: Markiere erfolgreich verarbeitete E-Mails als gelesen (SEEN)
                // Dies verhindert, dass dieselben E-Mails bei jedem Lauf erneut verarbeitet werden
                const processedUids = processed.map((r) => r.uid).filter((uid) => uid !== null && uid !== undefined);
                if (processedUids.length > 0) {
                  console.log(`📧 Markiere ${processedUids.length} E-Mail(s) als gelesen (SEEN)...`);
                  imap.addFlags(processedUids, "\\Seen", (err) => {
                    if (err) {
                      console.error("❌ Fehler beim Markieren der E-Mails als gelesen:", err);
                    } else {
                      console.log(`✅ ${processedUids.length} E-Mail(s) erfolgreich als gelesen markiert - werden nicht erneut verarbeitet`);
                    }
                    // Schließe IMAP-Verbindung nach dem Markieren
                    imap.end();
                    resolve({ processed: processed.length, details: processed });
                  });
                } else {
                  console.log("⚠️ Keine UIDs zum Markieren gefunden - E-Mails werden möglicherweise erneut verarbeitet");
                  imap.end();
                  resolve({ processed: processed.length, details: processed });
                }
              } catch (err) {
                console.error("❌ Fehler beim Verarbeiten der E-Mails:", err);
                console.error("❌ Error Stack:", err.stack);
                imap.end();
                reject(err);
              }
            });
          };
          
          // Suche nach ungelesenen E-Mails
          console.log("🔍 Suche nach UNSEEN E-Mails...");
          // Suche nach ungelesenen E-Mails
          imap.search(["UNSEEN"], (err, results) => {
            if (err) {
              console.error("❌ Fehler bei der E-Mail-Suche (UNSEEN):", err);
              console.error("❌ Error Details:", JSON.stringify(err, null, 2));
              imap.end();
              reject(err);
              return;
            }
            
            console.log(`🔍 UNSEEN Suche abgeschlossen: ${results ? results.length : 0} E-Mail(s) gefunden`);
            
            if (!results || results.length === 0) {
              console.log("📭 Keine ungelesenen E-Mails gefunden");
              console.log("ℹ️ Hinweis: Die Function prüft nur UNSEEN E-Mails. Bereits gelesene E-Mails werden nicht verarbeitet.");
              imap.end();
              resolve({ processed: 0, reason: "no_unseen_emails" });
              return;
            }
            
            console.log(`✅ ${results.length} ungelesene E-Mail(s) gefunden, beginne Verarbeitung...`);
            processFoundEmails(results);
          });
        });
      });
      
      imap.once("error", (err) => {
        console.error("❌ IMAP-Fehler:", err);
        reject(err);
      });
      
      imap.connect();
    });
  });

/**
 * Cloud Function zum Löschen eines Mitarbeiters (Firebase Auth Account)
 * Wird vom Client aufgerufen, um den Firebase Auth Account eines Mitarbeiters zu löschen
 */
exports.deleteMitarbeiter = functions.region("us-central1").https.onCall(async (data, context) => {
  console.log("🗑️ deleteMitarbeiter Function aufgerufen");
  console.log("🗑️ Context:", context ? "Auth vorhanden" : "Keine Auth");
  console.log("🗑️ Data:", data);
  
  // Prüfe Authentifizierung
  if (!context || !context.auth) {
    console.error("❌ Keine Authentifizierung");
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Benutzer muss authentifiziert sein"
    );
  }

  const { uid } = data;

  // Validierung
  if (!uid) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "uid ist erforderlich"
    );
  }

  try {
    // Lösche den Firebase Auth Account
    await admin.auth().deleteUser(uid);
    
    console.log("✅ Firebase Auth Account gelöscht:", uid);
    
    return { success: true, message: "Mitarbeiter-Account erfolgreich gelöscht" };
  } catch (error) {
    console.error("❌ Fehler beim Löschen des Firebase Auth Accounts:", error);
    
    // Wenn der Benutzer nicht existiert, ist das auch OK (vielleicht wurde er bereits gelöscht)
    if (error.code === "auth/user-not-found") {
      console.log("⚠️ Firebase Auth Account existiert nicht (wurde bereits gelöscht):", uid);
      return { success: true, message: "Mitarbeiter-Account wurde bereits gelöscht oder existiert nicht" };
    }
    
    throw new functions.https.HttpsError(
      "internal",
      "Fehler beim Löschen des Mitarbeiter-Accounts: " + error.message
    );
  }
});
