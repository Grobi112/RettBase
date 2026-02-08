// fahrzeuge.js – Fahrzeugverwaltung
// - Auth-Handshake über das Dashboard
// - CRUD-Operationen für Fahrzeuge

import { db } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  query,
  orderBy,
  onSnapshot,
  updateDoc,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände & Konstanten
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, ... }
let allFahrzeuge = []; // Liste aller Fahrzeuge

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const fahrzeugList = document.getElementById("fahrzeugList");
const fahrzeugSearch = document.getElementById("fahrzeugSearch");
const createFahrzeugBtn = document.getElementById("createFahrzeugBtn");
const backBtn = document.getElementById("backBtn");

// Modal-Elemente
const createModal = document.getElementById("createModal");
const editModal = document.getElementById("editModal");
const createFahrzeugForm = document.getElementById("createFahrzeugForm");
const editFahrzeugForm = document.getElementById("editFahrzeugForm");
const fahrzeugMessage = document.getElementById("fahrzeugMessage");
const editFahrzeugMessage = document.getElementById("editFahrzeugMessage");
const closeCreateModalBtn = document.getElementById("closeCreateModal");
const closeCreateModalXBtn = document.getElementById("closeCreateModalX");
const closeEditModalBtn = document.getElementById("closeEditModal");
const closeEditModalXBtn = document.getElementById("closeEditModalX");

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
    // Prüfe, ob Daten bereits im sessionStorage sind
    const storedAuthData = sessionStorage.getItem('userAuthData');
    if (storedAuthData) {
      userAuthData = JSON.parse(storedAuthData);
      console.log("✅ Auth-Daten aus sessionStorage geladen:", userAuthData);
      resolve();
      return;
    }

    // Wenn nicht im sessionStorage, warte auf Nachricht vom Parent
    window.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'AUTH_DATA') {
        userAuthData = event.data.authData;
        sessionStorage.setItem('userAuthData', JSON.stringify(userAuthData));
        console.log("✅ Auth-Daten vom Dashboard empfangen:", userAuthData);
        resolve();
      }
    });

    // Sende eine Nachricht an das Parent-Fenster, um Auth-Daten anzufordern
    if (window.parent !== window) {
      window.parent.postMessage({ type: 'REQUEST_AUTH_DATA' }, '*');
    } else {
      console.warn("⚠️ Modul wird nicht in einem iFrame ausgeführt. Auth-Daten müssen manuell gesetzt werden.");
      userAuthData = {
        uid: "mock-uid",
        companyId: "demo",
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
  console.log("🚀 Fahrzeugverwaltung initialisiert.");

  if (!userAuthData || !userAuthData.companyId) {
    console.error("❌ Keine companyId verfügbar!");
    fahrzeugList.innerHTML = '<div class="error-message">Fehler: Keine Berechtigung verfügbar.</div>';
    return;
  }

  // Zurück-Button
  if (backBtn) {
    backBtn.addEventListener("click", () => {
      const frame = window.parent?.document.getElementById("contentFrame");
      if (frame) {
        frame.src = "../../home.html";
      } else {
        window.location.href = "../../home.html";
      }
    });
  }

  // Event Listener
  setupEventListeners();

  // Lade Fahrzeuge
  await loadFahrzeuge();
}

// ---------------------------------------------------------
// Event Listener Setup
// ---------------------------------------------------------

function setupEventListeners() {
  // Create Button
  createFahrzeugBtn?.addEventListener("click", () => {
    createModal.classList.add("active");
    createFahrzeugForm.reset();
    fahrzeugMessage.textContent = "";
    fahrzeugMessage.className = "message";
  });

  // Close Modal Buttons
  closeCreateModalBtn?.addEventListener("click", closeCreateModal);
  closeCreateModalXBtn?.addEventListener("click", closeCreateModal);
  closeEditModalBtn?.addEventListener("click", closeEditModal);
  closeEditModalXBtn?.addEventListener("click", closeEditModal);

  // Modal Overlay Click (außerhalb schließen)
  createModal?.addEventListener("click", (e) => {
    if (e.target === createModal) {
      closeCreateModal();
    }
  });
  editModal?.addEventListener("click", (e) => {
    if (e.target === editModal) {
      closeEditModal();
    }
  });

  // Form Submit Handler
  createFahrzeugForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    await handleCreateFahrzeug();
  });
  editFahrzeugForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    await handleEditFahrzeug();
  });

  // Suchfeld
  fahrzeugSearch?.addEventListener("input", (e) => {
    renderFahrzeugList(e.target.value.trim());
  });
}

function closeCreateModal() {
  createModal.classList.remove("active");
  createFahrzeugForm.reset();
  fahrzeugMessage.textContent = "";
  fahrzeugMessage.className = "message";
}

function closeEditModal() {
  editModal.classList.remove("active");
  editFahrzeugForm.reset();
  editFahrzeugMessage.textContent = "";
  editFahrzeugMessage.className = "message";
}

// ---------------------------------------------------------
// Firestore Collection Helper
// ---------------------------------------------------------

function getFahrzeugeCollection() {
  return collection(db, "kunden", userAuthData.companyId, "fahrzeuge");
}

// ---------------------------------------------------------
// CRUD-Operationen
// ---------------------------------------------------------

async function loadFahrzeuge() {
  if (!userAuthData || !userAuthData.companyId) {
    console.error("❌ Keine companyId verfügbar, kann Fahrzeuge nicht laden.");
    return;
  }
  try {
    const fahrzeugeRef = getFahrzeugeCollection();
    const q = query(fahrzeugeRef, orderBy("rufname", "asc"));
    const snapshot = await getDocs(q);
    allFahrzeuge = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    console.log(`✅ ${allFahrzeuge.length} Fahrzeuge geladen.`);
    renderFahrzeugList();
  } catch (error) {
    console.error("❌ Fehler beim Laden der Fahrzeuge:", error);
    fahrzeugList.innerHTML = '<p class="error-message">Fehler beim Laden der Fahrzeuge.</p>';
  }
}

async function handleCreateFahrzeug() {
  if (!userAuthData || !userAuthData.companyId) {
    fahrzeugMessage.textContent = "Fehler: Keine Berechtigung verfügbar.";
    fahrzeugMessage.className = "message error";
    return;
  }

  try {
    const formData = new FormData(createFahrzeugForm);
    const fahrzeugData = {
      rufname: formData.get("rufname") || null,
      fahrzeugtyp: formData.get("fahrzeugtyp") || null,
      wache: formData.get("wache") || null,
      aktiv: formData.get("aktiv") === "true",
      kennzeichen: formData.get("kennzeichen") || null,
      hersteller: formData.get("hersteller") || null,
      modell: formData.get("modell") || null,
      baujahr: formData.get("baujahr") ? parseInt(formData.get("baujahr")) : null,
      indienststellung: formData.get("indienststellung") || null,
      traeger: formData.get("traeger") || null,
      kostenstelle: formData.get("kostenstelle") || null,
      gruppe: formData.get("gruppe") || null,
      kraftstoff: formData.get("kraftstoff") || null,
      antrieb: formData.get("antrieb") || null,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    };

    // Entferne null-Werte für saubere Datenstruktur
    Object.keys(fahrzeugData).forEach(key => {
      if (fahrzeugData[key] === null) {
        delete fahrzeugData[key];
      }
    });

    const fahrzeugeRef = getFahrzeugeCollection();
    const newDocRef = doc(fahrzeugeRef);
    await setDoc(newDocRef, fahrzeugData);

    fahrzeugMessage.textContent = "Fahrzeug erfolgreich hinzugefügt.";
    fahrzeugMessage.className = "message success";

    setTimeout(() => {
      closeCreateModal();
      loadFahrzeuge();
    }, 1000);
  } catch (error) {
    console.error("❌ Fehler beim Hinzufügen des Fahrzeugs:", error);
    fahrzeugMessage.textContent = "Fehler beim Hinzufügen des Fahrzeugs. Details siehe Konsole.";
    fahrzeugMessage.className = "message error";
  }
}

async function handleEditFahrzeug() {
  if (!userAuthData || !userAuthData.companyId) {
    editFahrzeugMessage.textContent = "Fehler: Keine Berechtigung verfügbar.";
    editFahrzeugMessage.className = "message error";
    return;
  }

  try {
    const fahrzeugId = document.getElementById("editFahrzeugId").value;
    if (!fahrzeugId) {
      editFahrzeugMessage.textContent = "Fehler: Keine Fahrzeug-ID gefunden.";
      editFahrzeugMessage.className = "message error";
      return;
    }

    const formData = new FormData(editFahrzeugForm);
    const fahrzeugData = {
      rufname: formData.get("rufname") || null,
      fahrzeugtyp: formData.get("fahrzeugtyp") || null,
      wache: formData.get("wache") || null,
      aktiv: formData.get("aktiv") === "true",
      kennzeichen: formData.get("kennzeichen") || null,
      hersteller: formData.get("hersteller") || null,
      modell: formData.get("modell") || null,
      baujahr: formData.get("baujahr") ? parseInt(formData.get("baujahr")) : null,
      indienststellung: formData.get("indienststellung") || null,
      traeger: formData.get("traeger") || null,
      kostenstelle: formData.get("kostenstelle") || null,
      gruppe: formData.get("gruppe") || null,
      kraftstoff: formData.get("kraftstoff") || null,
      antrieb: formData.get("antrieb") || null,
      updatedAt: serverTimestamp(),
    };

    // Entferne null-Werte für saubere Datenstruktur
    Object.keys(fahrzeugData).forEach(key => {
      if (fahrzeugData[key] === null) {
        delete fahrzeugData[key];
      }
    });

    const fahrzeugRef = doc(getFahrzeugeCollection(), fahrzeugId);
    await updateDoc(fahrzeugRef, fahrzeugData);

    editFahrzeugMessage.textContent = "Fahrzeug erfolgreich aktualisiert.";
    editFahrzeugMessage.className = "message success";

    setTimeout(() => {
      closeEditModal();
      loadFahrzeuge();
    }, 1000);
  } catch (error) {
    console.error("❌ Fehler beim Aktualisieren des Fahrzeugs:", error);
    editFahrzeugMessage.textContent = "Fehler beim Aktualisieren des Fahrzeugs. Details siehe Konsole.";
    editFahrzeugMessage.className = "message error";
  }
}

async function handleDeleteFahrzeug(fahrzeugId) {
  if (!confirm("Möchten Sie dieses Fahrzeug wirklich löschen?")) {
    return;
  }

  if (!userAuthData || !userAuthData.companyId) {
    alert("Fehler: Keine Berechtigung verfügbar.");
    return;
  }

  try {
    const fahrzeugRef = doc(getFahrzeugeCollection(), fahrzeugId);
    await deleteDoc(fahrzeugRef);
    console.log(`✅ Fahrzeug ${fahrzeugId} gelöscht.`);
    await loadFahrzeuge();
  } catch (error) {
    console.error("❌ Fehler beim Löschen des Fahrzeugs:", error);
    alert("Fehler beim Löschen des Fahrzeugs. Details siehe Konsole.");
  }
}

function openEditModal(fahrzeug) {
  document.getElementById("editFahrzeugId").value = fahrzeug.id;
  document.getElementById("editRufname").value = fahrzeug.rufname || "";
  document.getElementById("editFahrzeugtyp").value = fahrzeug.fahrzeugtyp || "";
  document.getElementById("editWache").value = fahrzeug.wache || "";
  document.getElementById("editAktiv").value = fahrzeug.aktiv === true ? "true" : "false";
  document.getElementById("editKennzeichen").value = fahrzeug.kennzeichen || "";
  document.getElementById("editHersteller").value = fahrzeug.hersteller || "";
  document.getElementById("editModell").value = fahrzeug.modell || "";
  document.getElementById("editBaujahr").value = fahrzeug.baujahr || "";
  document.getElementById("editIndienststellung").value = fahrzeug.indienststellung || "";
  document.getElementById("editTraeger").value = fahrzeug.traeger || "";
  document.getElementById("editKostenstelle").value = fahrzeug.kostenstelle || "";
  document.getElementById("editGruppe").value = fahrzeug.gruppe || "";
  document.getElementById("editKraftstoff").value = fahrzeug.kraftstoff || "";
  document.getElementById("editAntrieb").value = fahrzeug.antrieb || "";

  editFahrzeugMessage.textContent = "";
  editFahrzeugMessage.className = "message";
  editModal.classList.add("active");
}

// ---------------------------------------------------------
// Rendering
// ---------------------------------------------------------

function renderFahrzeugList(searchTerm = "") {
  if (!fahrzeugList) return;

  let filteredFahrzeuge = allFahrzeuge;

  if (searchTerm) {
    const searchLower = searchTerm.toLowerCase();
    filteredFahrzeuge = allFahrzeuge.filter(fahrzeug => {
      const rufname = (fahrzeug.rufname || "").toLowerCase();
      const fahrzeugtyp = (fahrzeug.fahrzeugtyp || "").toLowerCase();
      const kennzeichen = (fahrzeug.kennzeichen || "").toLowerCase();
      const wache = (fahrzeug.wache || "").toLowerCase();
      return rufname.includes(searchLower) ||
             fahrzeugtyp.includes(searchLower) ||
             kennzeichen.includes(searchLower) ||
             wache.includes(searchLower);
    });
  }

  if (filteredFahrzeuge.length === 0) {
    fahrzeugList.innerHTML = '<p>Keine Fahrzeuge gefunden.</p>';
    return;
  }

  fahrzeugList.innerHTML = filteredFahrzeuge.map(fahrzeug => {
    const details = [];
    if (fahrzeug.fahrzeugtyp) details.push(`Typ: ${fahrzeug.fahrzeugtyp}`);
    if (fahrzeug.kennzeichen) details.push(`Kennzeichen: ${fahrzeug.kennzeichen}`);
    if (fahrzeug.wache) details.push(`Wache: ${fahrzeug.wache}`);
    const aktivStatus = fahrzeug.aktiv === true ? "Aktiv" : "Inaktiv";
    details.push(`Status: ${aktivStatus}`);

    return `
      <div class="fahrzeug-item clickable-item" data-id="${fahrzeug.id}">
        <div class="fahrzeug-info">
          <div class="fahrzeug-name">${fahrzeug.rufname || "Unbenannt"}</div>
          <div class="fahrzeug-details">
            ${details.map(d => `<span class="fahrzeug-detail-item">${d}</span>`).join("")}
          </div>
        </div>
        <div class="fahrzeug-actions">
          <button class="btn-icon delete" onclick="event.stopPropagation(); handleDeleteFahrzeug('${fahrzeug.id}')" title="Löschen">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <polyline points="3 6 5 6 21 6"></polyline>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            </svg>
          </button>
        </div>
      </div>
    `;
  }).join("");

  // Event Listener für Klick auf Fahrzeug-Item (Bearbeiten)
  fahrzeugList.querySelectorAll(".fahrzeug-item").forEach(item => {
    item.addEventListener("click", (e) => {
      // Ignoriere Klicks auf Buttons
      if (e.target.closest(".btn-icon")) {
        return;
      }
      const fahrzeugId = item.dataset.id;
      const fahrzeug = allFahrzeuge.find(f => f.id === fahrzeugId);
      if (fahrzeug) {
        openEditModal(fahrzeug);
      }
    });
  });
}

// Globale Funktionen für onclick-Handler
window.handleDeleteFahrzeug = handleDeleteFahrzeug;

