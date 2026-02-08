// notfallprotokoll-ssd.js – Notfallprotokoll Schulsanitätsdienst
// - Auth-Handshake über das Dashboard
// - Formular für Notfallprotokolle
// - Datenbankstruktur: kunden/{companyId}/notfallprotokolle/{protokollId}

import { db } from "../../../firebase-config.js";
import {
  collection,
  doc,
  addDoc,
  getDocs,
  query,
  orderBy,
  limit,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände & Konstanten
// ---------------------------------------------------------

let userAuthData = null;
let nextProtokollNr = 1;

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const backBtn = document.getElementById("backBtn");
const notfallprotokollForm = document.getElementById("notfallprotokollForm");
const notfallprotokollMessage = document.getElementById("notfallprotokollMessage");
const protokollNrInput = document.getElementById("protokollNr");
const resetBtn = document.getElementById("resetBtn");

// ---------------------------------------------------------
// Initialisierung
// ---------------------------------------------------------

document.addEventListener('DOMContentLoaded', async () => {
  await waitForAuthData();
  initializeModule();
});

// ---------------------------------------------------------
// Auth-Handshake: Daten vom Parent (Dashboard) empfangen
// ---------------------------------------------------------

function waitForAuthData() {
  return new Promise((resolve) => {
    const storedAuthData = sessionStorage.getItem('userAuthData');
    if (storedAuthData) {
      userAuthData = JSON.parse(storedAuthData);
      console.log("✅ Auth-Daten aus sessionStorage geladen:", userAuthData);
      resolve();
      return;
    }

    window.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'AUTH_DATA') {
        userAuthData = event.data.data || event.data.authData;
        if (userAuthData) {
          sessionStorage.setItem('userAuthData', JSON.stringify(userAuthData));
          console.log("✅ Auth-Daten vom Dashboard empfangen:", userAuthData);
          resolve();
        } else {
          console.error("❌ Auth-Daten-Struktur unerwartet:", event.data);
        }
      }
    });

    if (window.parent !== window) {
      window.parent.postMessage({ type: 'REQUEST_AUTH_DATA' }, '*');
    } else {
      console.warn("⚠️ Modul wird nicht in einem iFrame ausgeführt. Auth-Daten müssen manuell gesetzt werden.");
      userAuthData = {
        uid: "mock-uid",
        companyId: "ssd-kkg",
        role: "admin",
        email: "mock@example.com",
        displayName: "Mock User"
      };
      sessionStorage.setItem('userAuthData', JSON.stringify(userAuthData));
      resolve();
    }
  });
}

// ---------------------------------------------------------
// Modul-Initialisierung nach Auth
// ---------------------------------------------------------

async function initializeModule() {
  console.log("🚀 Notfallprotokoll SSD initialisiert.");

  if (!userAuthData || !userAuthData.companyId) {
    console.error("❌ Keine companyId verfügbar!");
    notfallprotokollMessage.textContent = "Fehler: Keine Berechtigung verfügbar.";
    notfallprotokollMessage.className = "message error";
    return;
  }

  // Back-Button
  if (backBtn) {
    backBtn.addEventListener("click", () => {
      const frame = window.parent?.document.getElementById("contentFrame");
      if (frame) {
        frame.src = "../../home.html";
      } else if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: "NAVIGATE", target: "../../home.html" }, "*");
      } else {
        window.location.href = "../../home.html";
      }
    });
  }

  // Setze aktuelles Datum und Uhrzeit
  const now = new Date();
  const today = now.toISOString().split('T')[0];
  const time = now.toTimeString().slice(0, 5);
  
  const datumInput = document.getElementById("datumEinsatz");
  const uhrzeitInput = document.getElementById("uhrzeitEinsatz");
  if (datumInput) datumInput.value = today;
  if (uhrzeitInput) uhrzeitInput.value = time;

  // Lade nächste Protokollnummer
  await loadNextProtokollNr();

  setupEventListeners();
}

// ---------------------------------------------------------
// EVENT LISTENER SETUP
// ---------------------------------------------------------

function setupEventListeners() {
  notfallprotokollForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    await handleSaveProtokoll();
  });

  resetBtn?.addEventListener("click", () => {
    resetForm();
  });

  // Körperdiagramm Interaktivität
  setupBodyDiagramListeners();
}

// ---------------------------------------------------------
// Firestore Collection Helper
// ---------------------------------------------------------

function getNotfallprotokolleCollection() {
  if (!userAuthData || !userAuthData.companyId) {
    console.error("❌ Keine companyId verfügbar für getNotfallprotokolleCollection");
    return null;
  }
  return collection(db, "kunden", userAuthData.companyId, "notfallprotokolle");
}

// ---------------------------------------------------------
// Nächste Protokollnummer laden
// ---------------------------------------------------------

async function loadNextProtokollNr() {
  try {
    const protokolleRef = getNotfallprotokolleCollection();
    if (!protokolleRef) return;

    const q = query(protokolleRef, orderBy("protokollNr", "desc"), limit(1));
    const snapshot = await getDocs(q);

    if (!snapshot.empty) {
      const lastProtokoll = snapshot.docs[0].data();
      nextProtokollNr = (lastProtokoll.protokollNr || 0) + 1;
    } else {
      nextProtokollNr = 1;
    }

    if (protokollNrInput) {
      protokollNrInput.value = nextProtokollNr.toString().padStart(4, '0');
    }

    console.log(`✅ Nächste Protokollnummer: ${nextProtokollNr}`);
  } catch (error) {
    console.error("❌ Fehler beim Laden der Protokollnummer:", error);
    if (protokollNrInput) {
      protokollNrInput.value = "0001";
    }
  }
}

// ---------------------------------------------------------
// Protokoll speichern
// ---------------------------------------------------------

async function handleSaveProtokoll() {
  const formData = new FormData(notfallprotokollForm);

  // Validierung
  const schilderung = formData.get("schilderung")?.trim();
  const beschwerden = formData.get("beschwerden")?.trim();

  if (!schilderung) {
    notfallprotokollMessage.textContent = "Bitte geben Sie eine Schilderung des Unfalls oder der Erkrankung ein.";
    notfallprotokollMessage.className = "message error";
    return;
  }

  if (!beschwerden) {
    notfallprotokollMessage.textContent = "Bitte geben Sie die Beschwerden des Erkrankten/Verletzten ein.";
    notfallprotokollMessage.className = "message error";
    return;
  }

  try {
    // Sammle alle Formulardaten
    const protokollData = {
      protokollNr: parseInt(protokollNrInput.value) || nextProtokollNr,
      
      // Erkrankter/Verletzter
      patient: {
        vorname: formData.get("vornamePatient")?.trim() || null,
        name: formData.get("namePatient")?.trim() || null,
        geburtsdatum: formData.get("geburtsdatumPatient") || null,
        klasse: formData.get("klassePatient")?.trim() || null,
      },

      // Schulsanitäter/Ersthelfer
      helfer: {
        helfer1: {
          vorname: formData.get("vornameHelfer1")?.trim() || null,
          name: formData.get("nameHelfer1")?.trim() || null,
        },
        helfer2: {
          vorname: formData.get("vornameHelfer2")?.trim() || null,
          name: formData.get("nameHelfer2")?.trim() || null,
        },
        datum: formData.get("datumEinsatz") || null,
        uhrzeit: formData.get("uhrzeitEinsatz") || null,
        einsatzort: formData.get("einsatzort")?.trim() || null,
      },

      // Weitere Angaben
      weitereAngaben: {
        art: Array.from(formData.getAll("art")),
        artErkrankung: formData.get("artErkrankung")?.trim() || null,
        unfallOrt: formData.get("unfallOrt")?.trim() || null,
        aktivitaet: Array.from(formData.getAll("aktivitaet")),
        schilderung: schilderung,
      },

      // Erstbefund
      erstbefund: {
        schmerzen: formData.get("schmerzen") || null,
        atmung: formData.get("atmung") || null,
        puls: formData.get("puls")?.trim() || null,
        blutdruck: formData.get("blutdruck")?.trim() || null,
        verletzung: Array.from(formData.getAll("verletzung")),
        beschwerden: beschwerden,
        koerperteile: getMarkedBodyParts(), // Aus dem Körperdiagramm
      },

      // Getroffene Maßnahmen
      massnahmen: Array.from(formData.getAll("massnahme")),
      sonstigesMassnahme: formData.get("sonstigesMassnahme")?.trim() || null,

      // Metadaten
      erstelltVon: userAuthData.uid,
      erstelltVonName: userAuthData.displayName || userAuthData.email,
      createdAt: serverTimestamp(),
    };

    const protokolleRef = getNotfallprotokolleCollection();
    if (!protokolleRef) throw new Error("Notfallprotokolle Collection nicht verfügbar.");

    await addDoc(protokolleRef, protokollData);

    notfallprotokollMessage.textContent = "Protokoll erfolgreich gespeichert.";
    notfallprotokollMessage.className = "message success";

    // Lade nächste Protokollnummer
    await loadNextProtokollNr();

    // Formular zurücksetzen (nach kurzer Verzögerung)
    setTimeout(() => {
      resetForm();
      notfallprotokollMessage.textContent = "";
      notfallprotokollMessage.className = "message";
    }, 2000);

  } catch (error) {
    console.error("❌ Fehler beim Speichern des Protokolls:", error);
    notfallprotokollMessage.textContent = `Fehler: ${error.message}`;
    notfallprotokollMessage.className = "message error";
  }
}

// ---------------------------------------------------------
// Formular zurücksetzen
// ---------------------------------------------------------

function resetForm() {
  notfallprotokollForm.reset();
  
  // Setze Datum und Uhrzeit neu
  const now = new Date();
  const today = now.toISOString().split('T')[0];
  const time = now.toTimeString().slice(0, 5);
  
  const datumInput = document.getElementById("datumEinsatz");
  const uhrzeitInput = document.getElementById("uhrzeitEinsatz");
  if (datumInput) datumInput.value = today;
  if (uhrzeitInput) uhrzeitInput.value = time;

  // Entferne Markierungen im Körperdiagramm
  clearBodyDiagram();
}

// ---------------------------------------------------------
// Körperdiagramm Interaktivität
// ---------------------------------------------------------

function setupBodyDiagramListeners() {
  const bodySvg = document.querySelector('.body-svg');
  if (!bodySvg) return;

  const bodyParts = bodySvg.querySelectorAll('circle, rect, line');
  
  bodyParts.forEach(part => {
    part.addEventListener('click', () => {
      part.classList.toggle('body-part-marked');
    });
  });
}

function getMarkedBodyParts() {
  const markedParts = [];
  const bodySvg = document.querySelector('.body-svg');
  if (!bodySvg) return markedParts;

  const marked = bodySvg.querySelectorAll('.body-part-marked');
  marked.forEach(part => {
    const parent = part.closest('g');
    const view = parent?.classList.contains('body-front') ? 'vorne' : 'hinten';
    markedParts.push({
      element: part.tagName,
      view: view,
    });
  });

  return markedParts;
}

function clearBodyDiagram() {
  const bodySvg = document.querySelector('.body-svg');
  if (!bodySvg) return;

  const marked = bodySvg.querySelectorAll('.body-part-marked');
  marked.forEach(part => {
    part.classList.remove('body-part-marked');
  });
}

