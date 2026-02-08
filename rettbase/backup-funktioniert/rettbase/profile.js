// profile.js

import { db, auth } from "./firebase-config.js";
import { getAuthData } from "./auth.js";
import { doc, getDoc, updateDoc, setDoc, addDoc, collection, query, where, getDocs } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import { onAuthStateChanged, updateEmail, updatePassword, reauthenticateWithCredential, EmailAuthProvider } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";
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
 * Lädt den Mitarbeiter-Datensatz aus der Datenbank (Mitarbeiterverwaltung Collection)
 */
async function loadMitarbeiterData() {
  // Stelle sicher, dass wir eine Email haben (aus Firebase Auth, falls nicht in userAuthData)
  const userEmail = userAuthData?.email || (auth.currentUser ? auth.currentUser.email : null);
  
  console.log("🔍 loadMitarbeiterData - Prüfe Daten:", {
    "userAuthData vorhanden": !!userAuthData,
    "userAuthData.email": userAuthData?.email,
    "userAuthData.companyId": userAuthData?.companyId,
    "userAuthData.uid": userAuthData?.uid,
    "auth.currentUser.email": auth.currentUser?.email,
    "userEmail (final)": userEmail
  });
  
  if (!userAuthData || !userAuthData.companyId || !userEmail) {
    console.error("❌ Keine Auth-Daten verfügbar - Details:", {
      "userAuthData vorhanden": !!userAuthData,
      "companyId vorhanden": !!userAuthData?.companyId,
      "userEmail vorhanden": !!userEmail,
      userAuthData: JSON.stringify(userAuthData, null, 2),
      currentUserEmail: auth.currentUser?.email
    });
    return null;
  }

  try {
    // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Suche Mitarbeiter anhand der Email-Adresse
    // Collection: kunden/{companyId}/mitarbeiter
    const mitarbeiterRef = collection(db, "kunden", userAuthData.companyId, "mitarbeiter");
    const mitarbeiterQuery = query(mitarbeiterRef, where("email", "==", userEmail));
    const mitarbeiterSnapshot = await getDocs(mitarbeiterQuery);

    if (mitarbeiterSnapshot.empty) {
      console.warn("Kein Mitarbeiter-Datensatz gefunden für Email:", userEmail);
      return null;
    }

    const mitarbeiterDoc = mitarbeiterSnapshot.docs[0];
    currentMitarbeiterId = mitarbeiterDoc.id;
    currentMitarbeiterData = mitarbeiterDoc.data();
    
    console.log("✅ Mitarbeiter-Datensatz geladen:", {
      id: currentMitarbeiterId,
      email: currentMitarbeiterData.email
    });
    
    return currentMitarbeiterData;
  } catch (error) {
    console.error("Fehler beim Laden der Mitarbeiter-Daten:", error);
    return null;
  }
}

/**
 * Befüllt das Formular mit den Mitarbeiter-Daten
 */
function populateForm(mitarbeiterData) {
  if (!mitarbeiterData) return;

  // Personalnummer (readonly)
  if (personalnummerInput) personalnummerInput.value = mitarbeiterData.personalnummer || "";

  if (vornameInput) vornameInput.value = mitarbeiterData.vorname || "";
  if (nachnameInput) nachnameInput.value = mitarbeiterData.nachname || "";
  
  // Geburtsdatum: Konvertiere von verschiedenen Formaten zu YYYY-MM-DD
  if (mitarbeiterData.geburtsdatum) {
    let geburtsdatum = mitarbeiterData.geburtsdatum;
    // Wenn es ein Timestamp ist, konvertiere zu Date
    if (geburtsdatumInput) {
      if (geburtsdatum.toDate) {
        const date = geburtsdatum.toDate();
        geburtsdatumInput.value = date.toISOString().split("T")[0];
      } else if (typeof geburtsdatum === "string") {
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
      }
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
      // Nur wenn userAuthData.email auch keine Pseudo-Email ist
      emailToShow = userAuthData.email;
    }
    emailInput.value = emailToShow;
  }
  
  if (strasseInput) strasseInput.value = mitarbeiterData.strasse || mitarbeiterData.straße || "";
  if (hausnummerInput) hausnummerInput.value = mitarbeiterData.hausnummer || mitarbeiterData.hausNummer || mitarbeiterData["haus-nr"] || "";
  if (ortInput) ortInput.value = mitarbeiterData.ort || "";
  if (plzInput) plzInput.value = mitarbeiterData.plz || mitarbeiterData.PLZ || "";
  if (telefonInput) telefonInput.value = mitarbeiterData.telefon || mitarbeiterData.telefonnummer || "";

  // Passwort-Felder leeren
  if (currentPasswordInput) currentPasswordInput.value = "";
  if (newPasswordInput) newPasswordInput.value = "";
  if (confirmPasswordInput) confirmPasswordInput.value = "";
}

/**
 * Speichert die Formular-Daten in der Datenbank
 * Erstellt einen neuen Mitarbeiter-Datensatz, falls noch keiner existiert
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
    const user = auth.currentUser;
    if (!user) {
      console.error("Kein eingeloggter Benutzer");
      return false;
    }

    const newEmail = formData.email.trim();
    if (!newEmail) {
      alert("Bitte geben Sie eine E-Mail-Adresse ein.");
      return false;
    }

    const oldEmail = user.email;

    // 🔥 WICHTIG: E-Mail-Änderungen in Firebase Auth werden nicht mehr unterstützt
    // (benötigt E-Mail-Verifizierung, die nicht konfiguriert ist)
    // Die E-Mail wird nur in Firestore aktualisiert, nicht in Firebase Auth
    // Firebase Auth verwendet weiterhin die ursprüngliche E-Mail (oder Pseudo-Email)
    
    // Hinweis: Wenn der Benutzer seine E-Mail ändern möchte, muss dies über einen Admin erfolgen
    if (newEmail && newEmail !== oldEmail) {
      console.log("ℹ️ E-Mail-Änderung erkannt - wird nur in Firestore gespeichert, nicht in Firebase Auth");
      console.log("ℹ️ Firebase Auth E-Mail bleibt:", oldEmail);
    }

    // 2.5. Update Passwort, nur wenn alle drei Felder ausgefüllt sind
    const hasCurrentPassword = formData.currentPassword && formData.currentPassword.trim().length > 0;
    const hasNewPassword = formData.newPassword && formData.newPassword.trim().length > 0;
    const hasConfirmPassword = formData.confirmPassword && formData.confirmPassword.trim().length > 0;
    
    if (hasCurrentPassword && hasNewPassword && hasConfirmPassword) {
      try {
        // Re-Authentifizierung erforderlich für Passwort-Änderung
        const credential = EmailAuthProvider.credential(user.email, formData.currentPassword);
        await reauthenticateWithCredential(user, credential);
        
        // Passwort aktualisieren
        await updatePassword(user, formData.newPassword);
        console.log("✅ Passwort erfolgreich aktualisiert");
        
        // Passwort-Felder leeren nach erfolgreicher Änderung
        if (currentPasswordInput) currentPasswordInput.value = "";
        if (newPasswordInput) newPasswordInput.value = "";
        if (confirmPasswordInput) confirmPasswordInput.value = "";
      } catch (error) {
        console.error("Fehler beim Aktualisieren des Passworts:", error);
        if (error.code === 'auth/wrong-password') {
          alert("Das aktuelle Passwort ist falsch.");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        } else if (error.code === 'auth/weak-password') {
          alert("Das neue Passwort ist zu schwach (mindestens 6 Zeichen).");
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        } else {
          alert("Fehler beim Ändern des Passworts: " + error.message);
          saveBtn.disabled = false;
          saveBtn.textContent = "Speichern";
          return false;
        }
      }
    } else {
      // Keine Passwort-Änderung gewünscht - Passwort bleibt unverändert
      console.log("ℹ️ Passwort wird nicht geändert (Felder leer oder unvollständig)");
    }

    // 3. Prüfe ob Mitarbeiter-Datensatz existiert, sonst erstelle neuen beim Speichern
    let mitarbeiterDocId = currentMitarbeiterId;
    
    if (!mitarbeiterDocId) {
      // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Suche nach bestehendem Mitarbeiter-Datensatz
      // Versuche zuerst über UID (falls vorhanden), dann über E-Mail
      const mitarbeiterRef = collection(db, "kunden", userAuthData.companyId, "mitarbeiter");
      
      // Versuche zuerst über UID zu finden (wenn uid-Feld vorhanden)
      let mitarbeiterDocIdByUid = null;
      if (userAuthData.uid) {
        try {
          const mitarbeiterDocByUid = doc(db, "kunden", userAuthData.companyId, "mitarbeiter", userAuthData.uid);
          const mitarbeiterSnapByUid = await getDoc(mitarbeiterDocByUid);
          if (mitarbeiterSnapByUid.exists()) {
            mitarbeiterDocIdByUid = mitarbeiterSnapByUid.id;
          }
        } catch (e) {
          console.warn("⚠️ Fehler beim Suchen über UID:", e);
        }
      }
      
      if (mitarbeiterDocIdByUid) {
        mitarbeiterDocId = mitarbeiterDocIdByUid;
        currentMitarbeiterId = mitarbeiterDocId;
        console.log("✅ Existierender Mitarbeiter-Datensatz über UID gefunden:", mitarbeiterDocId);
      } else {
        // Falls nicht über UID gefunden, suche über E-Mail
        let mitarbeiterQuery = query(mitarbeiterRef, where("email", "==", oldEmail));
        let mitarbeiterSnapshot = await getDocs(mitarbeiterQuery);
        
        // Falls nicht gefunden, suche mit neuer Email
        if (mitarbeiterSnapshot.empty && newEmail !== oldEmail) {
          mitarbeiterQuery = query(mitarbeiterRef, where("email", "==", newEmail));
          mitarbeiterSnapshot = await getDocs(mitarbeiterQuery);
        }
        
        if (!mitarbeiterSnapshot.empty) {
          // Existierender Datensatz gefunden
          mitarbeiterDocId = mitarbeiterSnapshot.docs[0].id;
          currentMitarbeiterId = mitarbeiterDocId;
          console.log("✅ Existierender Mitarbeiter-Datensatz über E-Mail gefunden:", mitarbeiterDocId);
        } else {
          // Kein Datensatz gefunden - erstelle neuen beim Speichern
          // Verwende UID als Dokument-ID, falls vorhanden, sonst generiere neue
          mitarbeiterDocId = userAuthData.uid || doc(collection(db, "kunden", userAuthData.companyId, "mitarbeiter")).id;
          currentMitarbeiterId = mitarbeiterDocId;
          console.log("🆕 Erstelle neuen Mitarbeiter-Datensatz beim Speichern:", mitarbeiterDocId);
        }
      }
    }

    // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Update mitarbeiter Dokument
    const mitarbeiterRef = doc(db, "kunden", userAuthData.companyId, "mitarbeiter", mitarbeiterDocId);
    
    // Konvertiere Datum zu Timestamp
    let geburtsdatum = null;
    if (formData.geburtsdatum) {
      geburtsdatum = new Date(formData.geburtsdatum);
    }

    // Hole bestehende Daten, um Personalnummer zu behalten
    const existingSnap = await getDoc(mitarbeiterRef);
    const existingData = existingSnap.exists() ? existingSnap.data() : {};
    
    // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Erstelle vollständiges Mitarbeiter-Datenobjekt
    const mitarbeiterData = {
      personalnummer: existingData.personalnummer || formData.personalnummer || "", // Personalnummer bleibt unverändert
      vorname: formData.vorname || "",
      nachname: formData.nachname || "",
      name: `${formData.vorname || ""} ${formData.nachname || ""}`.trim() || newEmail, // Vollständiger Name
      geburtsdatum: geburtsdatum || null,
      email: newEmail, // Login-E-Mail wird hier gespeichert
      strasse: formData.strasse || "",
      hausnummer: formData.hausnummer || "",
      ort: formData.ort || "",
      plz: formData.plz || "",
      telefon: formData.telefon || "",
      // WICHTIG: Setze uid, falls vorhanden, und active
      uid: userAuthData.uid || existingData.uid || null,
      active: existingData.active !== undefined ? existingData.active : true, // Standard: aktiv
      // Rolle beibehalten, falls vorhanden
      role: existingData.role || userAuthData.role || "user"
    };

    // Speichere/Update Datensatz in der Mitarbeiterverwaltung Collection
    if (existingSnap.exists()) {
      // Update bestehenden Datensatz
      await updateDoc(mitarbeiterRef, mitarbeiterData);
      console.log("✅ Profil erfolgreich in Mitarbeiterverwaltung aktualisiert");
    } else {
      // Erstelle neuen Datensatz (wenn beim Laden keiner gefunden wurde)
      await setDoc(mitarbeiterRef, mitarbeiterData);
      console.log("✅ Neuer Mitarbeiter-Datensatz in Mitarbeiterverwaltung erstellt");
    }
    
    // 6. Aktualisiere userAuthData.email für weitere Verwendung
    if (newEmail && newEmail !== oldEmail) {
      userAuthData.email = newEmail;
    }
    
    // 7. Aktualisiere currentMitarbeiterData für zukünftige Verwendung
    currentMitarbeiterData = mitarbeiterData;
    
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

    // getAuthData() gibt keine email zurück, also müssen wir sie immer aus Firebase Auth holen
    let userEmail = null;
    
    // Versuche zuerst auth.currentUser
    if (auth.currentUser && auth.currentUser.email) {
      userEmail = auth.currentUser.email;
      console.log("📧 Email aus auth.currentUser geholt:", userEmail);
    } else {
      // Warte auf auth state, falls noch nicht geladen
      await new Promise((resolve) => {
        const unsubscribe = onAuthStateChanged(auth, (user) => {
          unsubscribe();
          if (user && user.email) {
            userEmail = user.email;
            console.log("📧 Email aus onAuthStateChanged geholt:", userEmail);
          }
          resolve();
        });
        // Timeout nach 2 Sekunden
        setTimeout(() => {
          unsubscribe();
          resolve();
        }, 2000);
      });
    }
    
    // Füge Email zu userAuthData hinzu, falls vorhanden
    if (userEmail) {
      userAuthData.email = userEmail;
    }
    
    // Logge zur Debugging mit allen Details
    console.log("🔍 Finale Auth-Daten:", {
      "userAuthData": JSON.stringify(userAuthData, null, 2),
      "email (final)": userEmail,
      "companyId": userAuthData?.companyId,
      "uid": userAuthData?.uid,
      "auth.currentUser.email": auth.currentUser?.email,
      "auth.currentUser vorhanden": !!auth.currentUser
    });

    // Lade Mitarbeiter-Daten
    const mitarbeiterData = await loadMitarbeiterData();
    if (mitarbeiterData) {
      populateForm(mitarbeiterData);
    } else {
      console.warn("Keine Mitarbeiter-Daten gefunden");
      // Befülle zumindest die E-Mail - nur wenn es keine Pseudo-Email ist
      if (emailInput && userEmail && !userEmail.endsWith(".rettbase.de")) {
        emailInput.value = userEmail;
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
      saveBtn.disabled = true;
      saveBtn.textContent = "Speichere...";

      const formData = {
        personalnummer: personalnummerInput.value.trim(),
        vorname: vornameInput.value.trim(),
        nachname: nachnameInput.value.trim(),
        geburtsdatum: geburtsdatumInput.value || null,
        email: emailInput.value.trim(),
        strasse: strasseInput.value.trim(),
        hausnummer: hausnummerInput.value.trim(),
        ort: ortInput.value.trim(),
        plz: plzInput.value.trim(),
        telefon: telefonInput.value.trim(),
        currentPassword: currentPasswordInput.value,
        newPassword: newPasswordInput.value,
        confirmPassword: confirmPasswordInput.value
      };

      // Validierung: Wenn Passwort geändert werden soll, müssen alle drei Felder ausgefüllt sein
      // Wenn nur einige Felder ausgefüllt sind, ist das ein Fehler
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
      geburtsdatumInput.value = "";
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



