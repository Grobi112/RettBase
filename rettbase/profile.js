// profile.js

import { auth, db } from "./firebase-config.js";
import { getAuthData } from "./auth.js";
import { 
  collection, 
  doc, 
  getDoc, 
  setDoc, 
  query, 
  where, 
  getDocs,
  serverTimestamp
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import {
  updatePassword,
  reauthenticateWithCredential,
  EmailAuthProvider,
  onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

let userAuthData = null;
let currentMitarbeiterId = null;
let currentMitarbeiterData = null;

// DOM Elements
const backBtn = document.getElementById("backBtn");
const profileForm = document.getElementById("profileForm");
const clearDateBtn = document.getElementById("clearDateBtn");

// Form Fields
const personalnummerInput = document.getElementById("personalnummer");
const vornameInput = document.getElementById("vorname");
const nachnameInput = document.getElementById("nachname");
const geburtsdatumInput = document.getElementById("geburtsdatum");
const emailInput = document.getElementById("email");
const strasseInput = document.getElementById("strasse");
const hausnummerInput = document.getElementById("hausnummer");
const ortInput = document.getElementById("ort");
const plzInput = document.getElementById("plz");
const telefonInput = document.getElementById("telefon");
const handynummerInput = document.getElementById("handynummer");
const currentPasswordInput = document.getElementById("currentPassword");
const newPasswordInput = document.getElementById("newPassword");
const confirmPasswordInput = document.getElementById("confirmPassword");
const newPasswordToggle = document.getElementById("newPasswordToggle");
const confirmPasswordToggle = document.getElementById("confirmPasswordToggle");
const newPasswordEyeIcon = document.getElementById("newPasswordEyeIcon");
const confirmPasswordEyeIcon = document.getElementById("confirmPasswordEyeIcon");

/**
 * Wartet auf Auth-Daten vom Parent (Dashboard)
 */
function waitForAuthData() {
  return new Promise((resolve) => {
    // Wenn wir direkt vom Dashboard geladen wurden, warte auf die AUTH_DATA Nachricht
    if (window.parent && window.parent !== window) {
      const messageHandler = (event) => {
        if (event.data && event.data.type === "AUTH_DATA") {
          window.removeEventListener("message", messageHandler);
          resolve(event.data.data);
        }
      };
      window.addEventListener("message", messageHandler);
      
      // Sende "Ready" Signal
      window.parent.postMessage({ type: "IFRAME_READY" }, "*");
    } else {
      // Fallback: Verwende Firebase Auth direkt
      onAuthStateChanged(auth, async (user) => {
        if (user) {
          // Hole vollständige Auth-Daten über getAuthData
          try {
            const authData = await getAuthData(user.uid, user.email);
            resolve(authData);
          } catch (error) {
            console.error("Fehler beim Abrufen der Auth-Daten:", error);
            resolve({
              uid: user.uid,
              email: user.email,
              companyId: getKundenIdFromSubdomain() || "admin"
            });
          }
        }
      });
    }
  });
}

/**
 * Extrahiert die Company-ID aus der Subdomain
 */
function getKundenIdFromSubdomain() {
  const hostname = window.location.hostname;
  const parts = hostname.split(".");
  if (parts.length > 0 && parts[0] !== "www" && parts[0] !== "admin") {
    return parts[0];
  }
  return "admin";
}

/**
 * Lädt den Mitarbeiter-Datensatz aus Firestore
 * ⚡ OPTIMIERT: Verwendet bereits geladene Daten aus userAuthData, wenn vorhanden
 */
async function loadMitarbeiterData() {
  // ⚡ OPTIMIERT: Prüfe zuerst, ob Mitarbeiter-Daten bereits im Dashboard geladen wurden
  if (userAuthData?.mitarbeiterData) {
    currentMitarbeiterId = userAuthData.mitarbeiterDocId || userAuthData.uid;
    currentMitarbeiterData = userAuthData.mitarbeiterData;
    console.log("⚡ Mitarbeiter-Daten aus Dashboard-Cache geladen (keine Firestore-Abfrage nötig):", {
      id: currentMitarbeiterId,
      vorname: currentMitarbeiterData.vorname,
      nachname: currentMitarbeiterData.nachname,
      email: currentMitarbeiterData.email
    });
    return currentMitarbeiterData;
  }
  
  let userEmail = userAuthData?.email;
  
  // Falls keine Email in userAuthData, hole sie von Firebase Auth
  if (!userEmail && auth.currentUser) {
    userEmail = auth.currentUser.email;
  }
  
  console.log("🔍 loadMitarbeiterData - Prüfe Daten:", {
    "userAuthData vorhanden": !!userAuthData,
    "userAuthData.email": userAuthData?.email,
    "userAuthData.companyId": userAuthData?.companyId,
    "userAuthData.uid": userAuthData?.uid,
    "userEmail (final)": userEmail
  });
  
  if (!userAuthData || !userAuthData.companyId || !userAuthData.uid) {
    console.error("❌ Keine Auth-Daten verfügbar - Details:", {
      "userAuthData vorhanden": !!userAuthData,
      "companyId vorhanden": !!userAuthData?.companyId,
      "uid vorhanden": !!userAuthData?.uid,
      userAuthData: JSON.stringify(userAuthData, null, 2)
    });
    return null;
  }

  try {
    const companyId = userAuthData.companyId;
    const uid = userAuthData.uid;
    
    // Versuche 1: Direkte Abfrage mit UID als Dokument-ID (wie im Dashboard)
    const mitarbeiterRef = doc(db, "kunden", companyId, "mitarbeiter", uid);
    const mitarbeiterSnap = await getDoc(mitarbeiterRef);
    
    if (mitarbeiterSnap.exists()) {
      currentMitarbeiterId = uid;
      currentMitarbeiterData = mitarbeiterSnap.data();
      console.log("✅ Mitarbeiter-Datensatz über UID (als Dokument-ID) geladen:", {
        id: currentMitarbeiterId,
        vorname: currentMitarbeiterData.vorname,
        nachname: currentMitarbeiterData.nachname,
        email: currentMitarbeiterData.email
      });
      return currentMitarbeiterData;
    }
    
    // Versuche 2: Suche nach uid-Feld in der mitarbeiter Collection (wie im Dashboard)
    const mitarbeiterCollection = collection(db, "kunden", companyId, "mitarbeiter");
    const uidQuery = query(mitarbeiterCollection, where("uid", "==", uid));
    const uidSnapshot = await getDocs(uidQuery);
    
    if (!uidSnapshot.empty) {
      const mitarbeiterDoc = uidSnapshot.docs[0];
      currentMitarbeiterId = mitarbeiterDoc.id;
      currentMitarbeiterData = mitarbeiterDoc.data();
      console.log("✅ Mitarbeiter-Datensatz über uid-Feld geladen:", {
        id: currentMitarbeiterId,
        vorname: currentMitarbeiterData.vorname,
        nachname: currentMitarbeiterData.nachname,
        email: currentMitarbeiterData.email
      });
      return currentMitarbeiterData;
    }
    
    // Versuche 3: Suche über Email (falls vorhanden)
    if (userEmail) {
      const emailQuery = query(
        mitarbeiterCollection,
        where("email", "==", userEmail)
      );
      const emailSnapshot = await getDocs(emailQuery);
      
      if (!emailSnapshot.empty) {
        const mitarbeiterDoc = emailSnapshot.docs[0];
        currentMitarbeiterId = mitarbeiterDoc.id;
        currentMitarbeiterData = mitarbeiterDoc.data();
        console.log("✅ Mitarbeiter-Datensatz über Email geladen:", {
          id: currentMitarbeiterId,
          vorname: currentMitarbeiterData.vorname,
          nachname: currentMitarbeiterData.nachname,
          email: currentMitarbeiterData.email
        });
        return currentMitarbeiterData;
      }
    }
    
    console.warn("⚠️ Kein Mitarbeiter-Datensatz gefunden für UID:", uid, "oder Email:", userEmail);
    return null;
  } catch (error) {
    console.error("❌ Fehler beim Laden der Mitarbeiter-Daten:", error);
    return null;
  }
}

/**
 * Befüllt das Formular mit den Mitarbeiter-Daten
 */
function populateForm(mitarbeiterData) {
  if (!mitarbeiterData) {
    console.warn("⚠️ populateForm: Keine Mitarbeiter-Daten vorhanden");
    return;
  }

  console.log("📝 Befülle Formular mit Mitarbeiter-Daten:", {
    vorname: mitarbeiterData.vorname,
    nachname: mitarbeiterData.nachname,
    personalnummer: mitarbeiterData.personalnummer,
    email: mitarbeiterData.email
  });

  // Personalnummer (readonly)
  if (personalnummerInput) personalnummerInput.value = mitarbeiterData.personalnummer || "";

  if (vornameInput) vornameInput.value = mitarbeiterData.vorname || "";
  if (nachnameInput) nachnameInput.value = mitarbeiterData.nachname || "";
  
  console.log("✅ Formular-Felder befüllt:", {
    personalnummer: personalnummerInput?.value,
    vorname: vornameInput?.value,
    nachname: nachnameInput?.value
  });
  
  // Geburtsdatum: Konvertiere von verschiedenen Formaten zu YYYY-MM-DD
  if (mitarbeiterData.geburtsdatum && geburtsdatumInput) {
    let geburtsdatum = mitarbeiterData.geburtsdatum;
    
    if (typeof geburtsdatum === "string") {
      // Versuche verschiedene Datumsformate zu parsen
      if (geburtsdatum.includes(".")) {
        // DD.MM.YYYY
        const parts = geburtsdatum.split(".");
        if (parts.length === 3) {
          geburtsdatumInput.value = `${parts[2]}-${parts[1].padStart(2, "0")}-${parts[0].padStart(2, "0")}`;
        }
      } else {
        geburtsdatumInput.value = geburtsdatum;
      }
    } else if (geburtsdatum?.toDate) {
      // Firestore Timestamp
      const date = geburtsdatum.toDate();
      geburtsdatumInput.value = date.toISOString().split('T')[0];
    } else if (geburtsdatum instanceof Date) {
      geburtsdatumInput.value = geburtsdatum.toISOString().split('T')[0];
    }
  }
  
  // E-Mail-Feld befüllen - nur echte E-Mail-Adressen, keine Pseudo-Email
  if (emailInput) {
    let emailToShow = "";
    // Prüfe zuerst mitarbeiterData nach einer echten E-Mail (nicht mit .rettbase.de endend)
    if (mitarbeiterData.email && !mitarbeiterData.email.endsWith(".rettbase.de")) {
      emailToShow = mitarbeiterData.email;
    } else if (mitarbeiterData.kontaktEmail && !mitarbeiterData.kontaktEmail.endsWith(".rettbase.de")) {
      emailToShow = mitarbeiterData.kontaktEmail;
    } else if (mitarbeiterData.eMail && !mitarbeiterData.eMail.endsWith(".rettbase.de")) {
      emailToShow = mitarbeiterData.eMail;
    } else if (userAuthData.email && !userAuthData.email.endsWith(".rettbase.de")) {
      emailToShow = userAuthData.email;
    }
    emailInput.value = emailToShow;
  }
  
  if (strasseInput) strasseInput.value = mitarbeiterData.strasse || mitarbeiterData.straße || "";
  if (hausnummerInput) hausnummerInput.value = mitarbeiterData.hausnummer || mitarbeiterData.hausNummer || mitarbeiterData["haus-nr"] || "";
  if (ortInput) ortInput.value = mitarbeiterData.ort || "";
  if (plzInput) plzInput.value = mitarbeiterData.plz || mitarbeiterData.PLZ || "";
  if (telefonInput) telefonInput.value = mitarbeiterData.telefon || mitarbeiterData.telefonnummer || "";
  if (handynummerInput) handynummerInput.value = mitarbeiterData.handynummer || mitarbeiterData.handy || mitarbeiterData.mobil || "";

  // Passwort-Felder leeren
  if (currentPasswordInput) currentPasswordInput.value = "";
  if (newPasswordInput) newPasswordInput.value = "";
  if (confirmPasswordInput) confirmPasswordInput.value = "";
}

/**
 * Speichert die Formular-Daten in Firestore
 */
async function saveProfileData(formData, saveBtn) {
  if (!userAuthData || !userAuthData.companyId || !userAuthData.uid) {
    console.error("Keine Company-ID oder UID verfügbar", {
      userAuthData,
      companyId: userAuthData?.companyId,
      uid: userAuthData?.uid
    });
    return false;
  }

  try {
    const companyId = userAuthData.companyId;
    const uid = userAuthData.uid;
    const currentUser = auth.currentUser;
    
    if (!currentUser) {
      alert("Fehler: Sie sind nicht angemeldet. Bitte melden Sie sich erneut an.");
      return false;
    }

    const newEmail = formData.email.trim();
    if (!newEmail) {
      alert("Bitte geben Sie eine E-Mail-Adresse ein.");
      return false;
    }

    const oldEmail = currentUser.email;

    // Passwort-Änderung, nur wenn alle drei Felder ausgefüllt sind
    const hasCurrentPassword = formData.currentPassword && formData.currentPassword.trim().length > 0;
    const hasNewPassword = formData.newPassword && formData.newPassword.trim().length > 0;
    const hasConfirmPassword = formData.confirmPassword && formData.confirmPassword.trim().length > 0;
    
    if (hasCurrentPassword && hasNewPassword && hasConfirmPassword) {
      try {
        // Re-authenticate mit aktuellem Passwort
        const credential = EmailAuthProvider.credential(oldEmail, formData.currentPassword);
        await reauthenticateWithCredential(currentUser, credential);
        
        // Aktualisiere Passwort
        await updatePassword(currentUser, formData.newPassword);
        console.log("✅ Passwort erfolgreich aktualisiert");
        
        // Passwort-Felder leeren nach erfolgreicher Änderung
        if (currentPasswordInput) currentPasswordInput.value = "";
        if (newPasswordInput) newPasswordInput.value = "";
        if (confirmPasswordInput) confirmPasswordInput.value = "";
      } catch (error) {
        console.error("Fehler beim Aktualisieren des Passworts:", error);
        const errorCode = error.code || '';
        const errorMessage = error.message || '';
        
        if (errorCode === 'auth/wrong-password' || errorCode === 'auth/invalid-credential') {
          alert("Das aktuelle Passwort ist falsch.");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        } else if (errorCode === 'auth/weak-password') {
          alert("Das neue Passwort ist zu schwach (mindestens 6 Zeichen).");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        } else {
          alert("Fehler beim Ändern des Passworts: " + errorMessage);
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        }
      }
    }

    // Prüfe ob Mitarbeiter-Datensatz existiert und finde die richtige Dokument-ID
    let mitarbeiterDocId = currentMitarbeiterId;
    let existingData = {};
    
    // Wenn currentMitarbeiterId nicht gesetzt ist, versuche die Dokument-ID zu finden
    if (!mitarbeiterDocId) {
      // Versuche 1: Direkt mit UID als Dokument-ID
      const mitarbeiterRefByUid = doc(db, "kunden", companyId, "mitarbeiter", uid);
      const snapByUid = await getDoc(mitarbeiterRefByUid);
      if (snapByUid.exists()) {
        mitarbeiterDocId = uid;
        existingData = snapByUid.data();
      } else {
        // Versuche 2: Suche nach uid-Feld
        const mitarbeiterCollection = collection(db, "kunden", companyId, "mitarbeiter");
        const uidQuery = query(mitarbeiterCollection, where("uid", "==", uid));
        const uidSnapshot = await getDocs(uidQuery);
        if (!uidSnapshot.empty) {
          const mitarbeiterDoc = uidSnapshot.docs[0];
          mitarbeiterDocId = mitarbeiterDoc.id;
          existingData = mitarbeiterDoc.data();
          currentMitarbeiterId = mitarbeiterDocId; // Aktualisiere für zukünftige Verwendung
        } else {
          // Kein Datensatz gefunden - verwende UID als Dokument-ID für neuen Datensatz
          mitarbeiterDocId = uid;
        }
      }
    } else {
      // currentMitarbeiterId ist gesetzt - hole bestehende Daten
      const mitarbeiterRef = doc(db, "kunden", companyId, "mitarbeiter", mitarbeiterDocId);
      const existingSnap = await getDoc(mitarbeiterRef);
      existingData = existingSnap.exists() ? existingSnap.data() : {};
    }
    
    // Erstelle Referenz für Speicherung
    const mitarbeiterRef = doc(db, "kunden", companyId, "mitarbeiter", mitarbeiterDocId);

    // Konvertiere Datum
    let geburtsdatum = null;
    if (formData.geburtsdatum) {
      geburtsdatum = new Date(formData.geburtsdatum);
    } else if (existingData.geburtsdatum) {
      geburtsdatum = existingData.geburtsdatum;
    }
    
    // Erstelle vollständiges Mitarbeiter-Datenobjekt
    // WICHTIG: Personalnummer wird NICHT überschrieben (readonly für Benutzer)
    const mitarbeiterData = {
      ...existingData, // Behalte bestehende Daten (inkl. Personalnummer)
      // Überschreibe nur die Felder, die der Benutzer ändern kann
      vorname: formData.vorname || "",
      nachname: formData.nachname || "",
      name: `${formData.vorname || ""} ${formData.nachname || ""}`.trim() || newEmail,
      geburtsdatum: geburtsdatum || null,
      email: newEmail,
      strasse: formData.strasse || "",
      hausnummer: formData.hausnummer || "",
      ort: formData.ort || "",
      plz: formData.plz || "",
      telefon: formData.telefon || "",
      handynummer: formData.handynummer || null,
      uid: uid, // Stelle sicher, dass UID gesetzt ist
      active: existingData.active !== undefined ? existingData.active : true,
      role: existingData.role || userAuthData.role || "user",
      updatedAt: serverTimestamp()
    };
    
    // Stelle sicher, dass Personalnummer erhalten bleibt (falls vorhanden)
    if (existingData.personalnummer && !mitarbeiterData.personalnummer) {
      mitarbeiterData.personalnummer = existingData.personalnummer;
    }

    // Speichere/Update Datensatz in Firestore (kunden/{companyId}/mitarbeiter/{mitarbeiterDocId})
    console.log("💾 Speichere Profil-Daten in Firestore:", {
      pfad: `kunden/${companyId}/mitarbeiter/${mitarbeiterDocId}`,
      vorname: mitarbeiterData.vorname,
      nachname: mitarbeiterData.nachname,
      personalnummer: mitarbeiterData.personalnummer,
      email: mitarbeiterData.email
    });
    
    await setDoc(mitarbeiterRef, mitarbeiterData, { merge: true });
    console.log("✅ Profil erfolgreich in Firestore-Mitarbeiterdatenbank aktualisiert");
    
    // Aktualisiere currentMitarbeiterData und currentMitarbeiterId
    currentMitarbeiterId = mitarbeiterDocId;
    currentMitarbeiterData = mitarbeiterData;
    
    // Aktualisiere userAuthData.email für weitere Verwendung
    if (newEmail && newEmail !== oldEmail) {
      userAuthData.email = newEmail;
    }
    
    return true;
  } catch (error) {
    console.error("Fehler beim Speichern des Profils:", error);
    return false;
  }
}

/**
 * Initialisiert die Profilseite
 */
async function initializeProfile() {
  try {
    // Warte auf Auth-Daten
    userAuthData = await waitForAuthData();
    console.log("✅ Profil - Auth-Daten empfangen:", JSON.stringify(userAuthData, null, 2));

    // Stelle sicher, dass Email vorhanden ist
    if (!userAuthData.email && auth.currentUser) {
      userAuthData.email = auth.currentUser.email;
    }

    // Lade Mitarbeiter-Daten
    const mitarbeiterData = await loadMitarbeiterData();
    if (mitarbeiterData) {
      populateForm(mitarbeiterData);
    } else {
      console.warn("Keine Mitarbeiter-Daten gefunden");
      // Befülle zumindest die E-Mail - nur wenn es keine Pseudo-Email ist
      if (emailInput && userAuthData.email && !userAuthData.email.endsWith(".rettbase.de")) {
        emailInput.value = userAuthData.email;
      }
    }

    // Stelle sicher, dass Passwort-Felder leer sind
    if (currentPasswordInput) {
      currentPasswordInput.value = "";
      currentPasswordInput.setAttribute("autocomplete", "off");
    }
    if (newPasswordInput) {
      newPasswordInput.value = "";
    }
    if (confirmPasswordInput) {
      confirmPasswordInput.value = "";
    }

    // Event Listeners
    setupEventListeners();
  } catch (error) {
    console.error("Fehler bei der Initialisierung:", error);
  }
}

/**
 * Setzt Event Listeners auf
 */
function setupEventListeners() {
  // Back Button
  if (backBtn) {
    backBtn.addEventListener("click", () => {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: "NAVIGATE_TO_HOME" }, "*");
      } else {
        window.location.href = "home.html";
      }
    });
  }

  // Form Submit
  if (profileForm) {
    profileForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      
      const saveBtn = profileForm.querySelector(".save-btn");
      if (!saveBtn) return;
      
      saveBtn.disabled = true;
      saveBtn.textContent = "Speichere...";

      const formData = {
        personalnummer: personalnummerInput?.value.trim() || "",
        vorname: vornameInput?.value.trim() || "",
        nachname: nachnameInput?.value.trim() || "",
        geburtsdatum: geburtsdatumInput?.value || null,
        email: emailInput?.value.trim() || "",
        strasse: strasseInput?.value.trim() || "",
        hausnummer: hausnummerInput?.value.trim() || "",
        ort: ortInput?.value.trim() || "",
        plz: plzInput?.value.trim() || "",
        telefon: telefonInput?.value.trim() || "",
        handynummer: handynummerInput?.value.trim() || "",
        currentPassword: currentPasswordInput?.value || "",
        newPassword: newPasswordInput?.value || "",
        confirmPassword: confirmPasswordInput?.value || ""
      };

      // Validierung: Wenn Passwort geändert werden soll, müssen alle drei Felder ausgefüllt sein
      const hasCurrentPassword = formData.currentPassword && formData.currentPassword.trim().length > 0;
      const hasNewPassword = formData.newPassword && formData.newPassword.trim().length > 0;
      const hasConfirmPassword = formData.confirmPassword && formData.confirmPassword.trim().length > 0;
      const passwordChangeRequested = hasCurrentPassword || hasNewPassword || hasConfirmPassword;
      
      if (passwordChangeRequested) {
        // Wenn Passwort-Änderung gewünscht, müssen alle drei Felder ausgefüllt sein
        if (!hasCurrentPassword || !hasNewPassword || !hasConfirmPassword) {
          alert("Bitte füllen Sie alle drei Passwort-Felder aus, um das Passwort zu ändern. Oder lassen Sie alle Felder leer, um das Passwort beizubehalten.");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return;
        }
        
        if (formData.newPassword !== formData.confirmPassword) {
          alert("Die neuen Passwörter stimmen nicht überein.");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return;
        }
        
        if (formData.newPassword.length < 6) {
          alert("Das neue Passwort muss mindestens 6 Zeichen lang sein.");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return;
        }
      }

      const success = await saveProfileData(formData, saveBtn);
      
      saveBtn.disabled = false;
      saveBtn.textContent = "Speichern";
      
      if (success) {
        alert("Profil erfolgreich gespeichert!");
      } else {
        alert("Fehler beim Speichern des Profils. Bitte versuchen Sie es erneut.");
      }
    });
  }

  // Clear Date Button
  if (clearDateBtn) {
    clearDateBtn.addEventListener("click", () => {
      if (geburtsdatumInput) {
        geburtsdatumInput.value = "";
      }
    });
  }

  // Passwort-Toggle für "Neues Passwort"
  if (newPasswordToggle && newPasswordInput && newPasswordEyeIcon) {
    newPasswordToggle.addEventListener("click", () => {
      const isPassword = newPasswordInput.type === "password";
      newPasswordInput.type = isPassword ? "text" : "password";
      
      // Ändere das Icon (Auge offen/geschlossen)
      if (isPassword) {
        // Zeige geschlossenes Auge (Passwort ist sichtbar)
        newPasswordEyeIcon.innerHTML = `
          <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
          <line x1="1" y1="1" x2="23" y2="23"></line>
        `;
      } else {
        // Zeige offenes Auge (Passwort ist versteckt)
        newPasswordEyeIcon.innerHTML = `
          <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
          <circle cx="12" cy="12" r="3"></circle>
        `;
      }
    });
  }

  // Passwort-Toggle für "Passwort-Wiederholung"
  if (confirmPasswordToggle && confirmPasswordInput && confirmPasswordEyeIcon) {
    confirmPasswordToggle.addEventListener("click", () => {
      const isPassword = confirmPasswordInput.type === "password";
      confirmPasswordInput.type = isPassword ? "text" : "password";
      
      // Ändere das Icon (Auge offen/geschlossen)
      if (isPassword) {
        // Zeige geschlossenes Auge (Passwort ist sichtbar)
        confirmPasswordEyeIcon.innerHTML = `
          <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
          <line x1="1" y1="1" x2="23" y2="23"></line>
        `;
      } else {
        // Zeige offenes Auge (Passwort ist versteckt)
        confirmPasswordEyeIcon.innerHTML = `
          <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
          <circle cx="12" cy="12" r="3"></circle>
        `;
      }
    });
  }
}

// Initialisiere beim Laden
document.addEventListener("DOMContentLoaded", () => {
  initializeProfile();
});
