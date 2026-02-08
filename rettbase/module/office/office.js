// office.js
// Office-Modul für interne Kommunikation

import { db } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
  query,
  where,
  orderBy,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, email, ... }

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const backBtn = document.getElementById("backBtn");
const mainContent = document.getElementById("mainContent");

// ---------------------------------------------------------
// Initialisierung
// ---------------------------------------------------------

window.addEventListener("DOMContentLoaded", () => {
  // Warte auf Auth-Daten vom Parent (Dashboard)
  waitForAuthData()
    .then((data) => {
      userAuthData = data;
      console.log(`✅ Office-Modul - Auth-Daten empfangen: Role ${data.role}, Company ${data.companyId}`);
      initializeOffice();
    })
    .catch((err) => {
      console.error("Office-Modul konnte Auth-Daten nicht empfangen:", err);
    });
});

// ---------------------------------------------------------
// Auth-Handshake
// ---------------------------------------------------------

function waitForAuthData() {
  return new Promise((resolve) => {
    // Sende "Ready" Signal an Parent
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: "IFRAME_READY" }, "*");
    }

    // Warte auf AUTH_DATA Nachricht vom Parent
    const messageHandler = (event) => {
      if (event.data && event.data.type === "AUTH_DATA") {
        window.removeEventListener("message", messageHandler);
        resolve(event.data.data);
      }
    };

    window.addEventListener("message", messageHandler);
  });
}

// ---------------------------------------------------------
// Hauptfunktionen
// ---------------------------------------------------------

function initializeOffice() {
  if (!userAuthData || !userAuthData.companyId) {
    console.error("Keine Auth-Daten verfügbar");
    return;
  }

  // Back-Button Event Listener
  if (backBtn) {
    backBtn.addEventListener("click", () => {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: "NAVIGATE_TO_HOME" }, "*");
      }
    });
  }

  // Lade Office-Inhalt
  loadOfficeContent();
}

function loadOfficeContent() {
  if (!mainContent) return;

  mainContent.innerHTML = `
    <div class="container">
      <h2>Office-Modul</h2>
      <p>Willkommen im Office-Modul!</p>
      <p>Benutzer: ${userAuthData.email || userAuthData.uid}</p>
      <p>Firma: ${userAuthData.companyId}</p>
      <p>Rolle: ${userAuthData.role}</p>
    </div>
  `;
}

// ---------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------

function getCompanyId() {
  return userAuthData?.companyId || null;
}

function getUserId() {
  return userAuthData?.uid || null;
}
