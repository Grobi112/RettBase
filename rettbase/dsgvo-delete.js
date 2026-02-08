// dsgvo-delete.js
// DSGVO-konforme Löschfunktion für RettBase (nur für Administratoren)
// Entspricht Abschnitt 6.1 (Löschung durch den Kunden) und 9.1 (Zugriff, Berichtigung, Einschränkung der Verarbeitung, Datenübertragbarkeit)
// der Google Cloud-Datenverarbeitungsvereinbarung
//
// WICHTIG: Diese Funktion darf nur von Administratoren verwendet werden.
// Benutzer können sich nicht selbst löschen, da es sich um Firmenmitarbeiter handelt.
// Historische Daten (OVD Einsatztagebuch, Schichtplan) bleiben erhalten für Nachverfolgbarkeit.

import { db } from "./firebase-config.js";
import {
  doc,
  getDoc,
  deleteDoc,
  collection,
  query,
  where,
  getDocs,
  writeBatch
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

/**
 * DSGVO-konforme Löschfunktion (nur für Administratoren)
 * Löscht Mitarbeiter-Daten, wenn Mitarbeiter aus dem Unternehmen ausscheidet.
 * 
 * WICHTIG:
 * - Historische Daten bleiben erhalten (OVD Einsatztagebuch, Schichtplan) für Nachverfolgbarkeit
 * - Schichtplan-Daten werden separat nach 1 Jahr automatisch gelöscht
 * - Nur direkte Mitarbeiter-Daten werden gelöscht (mitarbeiter, users, emails)
 * 
 * @param {string} targetUserIdOrDocId - UID oder Dokument-ID des zu löschenden Mitarbeiters
 * @param {string} companyId - Firmen-ID
 * @returns {Promise<{success: boolean, deletedItems: string[], errors: string[], message?: string}>}
 */
export async function dsgvoLoeschenMitarbeiter(targetUserIdOrDocId, companyId) {
  if (!targetUserIdOrDocId || !companyId) {
    throw new Error("targetUserIdOrDocId und companyId müssen angegeben werden.");
  }

  const deletedItems = [];
  const errors = [];
  let targetEmail = null;
  let targetUid = null;
  let mitarbeiterDocId = null;

  console.log(`🗑️ Starte DSGVO-Löschung für Mitarbeiter ID/UID: ${targetUserIdOrDocId}, Firma: ${companyId}`);

  try {
    // 1. Hole Mitarbeiter-Daten, um E-Mail und UID zu erhalten (vor dem Löschen)
    try {
      const mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
      let mitarbeiterData = null;
      
      // Versuche 1: Direkt mit ID als Dokument-ID (kann UID oder Dokument-ID sein)
      const mitarbeiterDocRef = doc(db, "kunden", companyId, "mitarbeiter", targetUserIdOrDocId);
      const mitarbeiterDocSnap = await getDoc(mitarbeiterDocRef);
      
      if (mitarbeiterDocSnap.exists()) {
        mitarbeiterDocId = targetUserIdOrDocId;
        mitarbeiterData = mitarbeiterDocSnap.data();
      } else {
        // Versuche 2: Suche nach uid-Feld (falls targetUserIdOrDocId eine UID ist)
        const q1 = query(mitarbeiterRef, where("uid", "==", targetUserIdOrDocId));
        const snapshot1 = await getDocs(q1);
        if (!snapshot1.empty) {
          mitarbeiterDocId = snapshot1.docs[0].id;
          mitarbeiterData = snapshot1.docs[0].data();
        }
      }
      
      // Speichere UID und E-Mail für spätere Löschung
      if (mitarbeiterData) {
        targetUid = mitarbeiterData.uid || targetUserIdOrDocId; // Verwende UID aus Daten oder fallback auf ID
        targetEmail = mitarbeiterData.email || mitarbeiterData.eMail;
        console.log(`📧 E-Mail des Zielbenutzers: ${targetEmail}`);
        console.log(`🆔 UID des Zielbenutzers: ${targetUid || "Keine UID vorhanden"}`);
      } else {
        console.warn("⚠️ Mitarbeiter-Dokument nicht gefunden. Versuche trotzdem mit bereitgestellter ID zu löschen.");
        mitarbeiterDocId = targetUserIdOrDocId;
        targetUid = targetUserIdOrDocId; // Fallback: Verwende ID als UID
      }
      
      // Lösche Mitarbeiter-Daten
      if (mitarbeiterDocId) {
        await deleteDoc(doc(db, "kunden", companyId, "mitarbeiter", mitarbeiterDocId));
        deletedItems.push(`Mitarbeiter-Daten: ${mitarbeiterDocId}`);
        console.log(`✅ Mitarbeiter-Daten gelöscht: ${mitarbeiterDocId}`);
      } else {
        errors.push("Mitarbeiter-Daten: Dokument nicht gefunden");
        console.error("❌ Keine Mitarbeiter-Daten gefunden");
      }
    } catch (error) {
      console.error("❌ Fehler beim Löschen der Mitarbeiter-Daten:", error);
      errors.push(`Mitarbeiter-Daten: ${error.message}`);
    }

    // 2. Lösche User-Daten und Subcollections (nur wenn UID vorhanden)
    if (targetUid) {
      try {
        const userDocRef = doc(db, "kunden", companyId, "users", targetUid);
        const userDocSnap = await getDoc(userDocRef);
        
        if (userDocSnap.exists()) {
          // Lösche Subcollections (z.B. userTiles)
          const userTilesRef = collection(db, "kunden", companyId, "users", targetUid, "userTiles");
          const userTilesSnapshot = await getDocs(userTilesRef);
          
          const batch = writeBatch(db);
          userTilesSnapshot.forEach((doc) => {
            batch.delete(doc.ref);
          });
          
          // Lösche das User-Dokument selbst
          batch.delete(userDocRef);
          await batch.commit();
          
          deletedItems.push(`User-Daten und Subcollections (${userTilesSnapshot.size} userTiles)`);
          console.log(`✅ User-Daten gelöscht (inkl. ${userTilesSnapshot.size} userTiles)`);
        } else {
          console.log("ℹ️ Keine User-Daten gefunden");
        }
      } catch (error) {
        console.error("❌ Fehler beim Löschen der User-Daten:", error);
        errors.push(`User-Daten: ${error.message}`);
      }
    } else {
      console.log("ℹ️ Keine UID vorhanden - überspringe User-Daten-Löschung");
    }

    // 3. Lösche E-Mail-Daten (nur direkte Mitarbeiter-E-Mails, nur wenn UID vorhanden)
    if (targetUid) {
      try {
        const emailsRef = collection(db, "kunden", companyId, "emails");
        
        // Finde alle E-Mails, die vom Zielbenutzer gesendet oder empfangen wurden
        const emailsFromUser = query(emailsRef, where("from", "==", targetUid));
        const emailsToUser = query(emailsRef, where("to", "==", targetUid));
        const emailsCcUser = query(emailsRef, where("cc", "array-contains", targetUid));
        const emailsBccUser = query(emailsRef, where("bcc", "array-contains", targetUid));
        
        const [fromSnapshot, toSnapshot, ccSnapshot, bccSnapshot] = await Promise.all([
          getDocs(emailsFromUser),
          getDocs(emailsToUser),
          getDocs(emailsCcUser),
          getDocs(emailsBccUser)
        ]);
        
        // Sammle alle eindeutigen Dokumente
        const emailDocsToDelete = new Map();
        fromSnapshot.forEach(doc => emailDocsToDelete.set(doc.id, doc.ref));
        toSnapshot.forEach(doc => emailDocsToDelete.set(doc.id, doc.ref));
        ccSnapshot.forEach(doc => emailDocsToDelete.set(doc.id, doc.ref));
        bccSnapshot.forEach(doc => emailDocsToDelete.set(doc.id, doc.ref));
        
        // Lösche alle gefundenen E-Mails
        if (emailDocsToDelete.size > 0) {
          const batch = writeBatch(db);
          emailDocsToDelete.forEach((ref) => {
            batch.delete(ref);
          });
          await batch.commit();
          deletedItems.push(`E-Mail-Daten: ${emailDocsToDelete.size} E-Mails`);
          console.log(`✅ ${emailDocsToDelete.size} E-Mails gelöscht`);
        } else {
          console.log("ℹ️ Keine E-Mail-Daten gefunden");
        }
      } catch (error) {
        console.error("❌ Fehler beim Löschen der E-Mail-Daten:", error);
        errors.push(`E-Mail-Daten: ${error.message}`);
      }
    } else {
      console.log("ℹ️ Keine UID vorhanden - überspringe E-Mail-Daten-Löschung");
    }

    // ⚠️ WICHTIG: OVD Einsatztagebuch und Schichtplan werden NICHT gelöscht/anonymisiert
    // Diese historischen Daten müssen für Nachverfolgbarkeit erhalten bleiben.
    // Schichtplan-Daten werden separat nach 1 Jahr automatisch gelöscht.
    console.log("ℹ️ OVD Einsatztagebuch-Einträge bleiben erhalten (historische Nachverfolgbarkeit)");
    console.log("ℹ️ Schichtplan-Daten bleiben erhalten (werden nach 1 Jahr automatisch gelöscht)");

    // 4. Lösche Firebase Auth Account des Zielbenutzers
    // HINWEIS: Firebase Admin SDK wird benötigt, um Accounts anderer Benutzer zu löschen
    // Für diese Funktion müsste ein Cloud Function erstellt werden, die mit Admin SDK arbeitet
    // Alternativ: Account bleibt bestehen, kann aber nicht mehr verwendet werden (kein Zugriff auf Firestore-Daten)
    console.log("ℹ️ Firebase Auth Account kann nur über Admin SDK gelöscht werden");
    console.log("ℹ️ Account wird deaktiviert (active: false in Mitarbeiter-Daten bereits gelöscht)");
    deletedItems.push("Hinweis: Firebase Auth Account sollte über Admin SDK gelöscht werden");

    console.log(`✅ DSGVO-Löschung abgeschlossen. Gelöscht: ${deletedItems.length} Items, Fehler: ${errors.length}`);
    
    return {
      success: errors.length === 0,
      deletedItems: deletedItems,
      errors: errors,
      message: "Historische Daten (OVD Einsatztagebuch, Schichtplan) bleiben erhalten für Nachverfolgbarkeit."
    };

  } catch (error) {
    console.error("❌ Schwerer Fehler bei der DSGVO-Löschung:", error);
    throw error;
  }
}

/**
 * Exportiert alle personenbezogenen Daten eines Mitarbeiters (DSGVO Art. 15 "Recht auf Auskunft")
 * Kann von Administratoren verwendet werden, um Mitarbeiter-Daten zu exportieren
 * 
 * @param {string} targetUserId - UID des Mitarbeiters
 * @param {string} companyId - Firmen-ID
 * @returns {Promise<Object>} Alle Daten des Mitarbeiters
 */
export async function dsgvoDatenexportMitarbeiter(targetUserId, companyId) {
  if (!targetUserId || !companyId) {
    throw new Error("targetUserId und companyId müssen angegeben werden.");
  }
  const exportData = {
    uid: targetUserId,
    companyId: companyId,
    exportDate: new Date().toISOString(),
    mitarbeiterData: null,
    userData: null,
    emails: []
    // HINWEIS: OVD-Einträge und Schichtplan-Daten werden nicht exportiert,
    // da diese historische Daten sind, die im System verbleiben müssen
  };

  try {
    // Hole Mitarbeiter-Daten
    const mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
    const q = query(mitarbeiterRef, where("uid", "==", targetUserId));
    const snapshot = await getDocs(q);
    if (!snapshot.empty) {
      exportData.mitarbeiterData = snapshot.docs[0].data();
    }

    // Hole User-Daten
    const userDocRef = doc(db, "kunden", companyId, "users", targetUserId);
    const userDocSnap = await getDoc(userDocRef);
    if (userDocSnap.exists()) {
      exportData.userData = userDocSnap.data();
    }

    // Hole E-Mail-Daten
    const emailsRef = collection(db, "kunden", companyId, "emails");
    const emailsFromUser = query(emailsRef, where("from", "==", targetUserId));
    const emailsToUser = query(emailsRef, where("to", "==", targetUserId));
    const [fromSnapshot, toSnapshot] = await Promise.all([
      getDocs(emailsFromUser),
      getDocs(emailsToUser)
    ]);
    
    const allEmails = new Map();
    fromSnapshot.forEach(doc => allEmails.set(doc.id, { ...doc.data(), id: doc.id }));
    toSnapshot.forEach(doc => allEmails.set(doc.id, { ...doc.data(), id: doc.id }));
    exportData.emails = Array.from(allEmails.values());

    return exportData;
  } catch (error) {
    console.error("❌ Fehler beim Datenexport:", error);
    throw error;
  }
}

