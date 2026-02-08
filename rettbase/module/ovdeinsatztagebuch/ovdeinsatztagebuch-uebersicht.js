// ovdeinsatztagebuch-uebersicht.js – OVD Einsatztagebuch Übersicht
// - Liste aller Einsatztagebücher eines Monats
// - Nach Tagen geordnet (01-31)

import { db } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  orderBy,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, ... }

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const mainContent = document.getElementById("mainContent");
const backBtn = document.getElementById("backBtn");
const monthSelect = document.getElementById("monthSelect");
const yearSelect = document.getElementById("yearSelect");
const loadBtn = document.getElementById("loadBtn");
const uebersichtList = document.getElementById("uebersichtList");

// ---------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------

/**
 * Formatiert eine Tag-ID zu DD.MM.YYYY
 */
function formatDayId(day, month, year) {
  const dayStr = String(day).padStart(2, '0');
  const monthStr = String(month).padStart(2, '0');
  return `${dayStr}.${monthStr}.${year}`;
}

/**
 * Parst DD.MM.YYYY zu { day, month, year }
 */
function parseDayId(dayId) {
  const [day, month, year] = dayId.split('.');
  return {
    day: parseInt(day, 10),
    month: parseInt(month, 10),
    year: parseInt(year, 10)
  };
}

/**
 * Gibt die Anzahl der Tage eines Monats zurück
 */
function getDaysInMonth(month, year) {
  return new Date(year, month, 0).getDate();
}

/**
 * Formatiert Datum zu lesbarem Format
 */
function formatDateDisplay(day, month, year) {
  const dayStr = String(day).padStart(2, '0');
  const monthNames = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
  ];
  return `${dayStr}. ${monthNames[month - 1]} ${year}`;
}

/**
 * Auth-Handshake: Daten vom Parent (Dashboard) empfangen
 */
function waitForAuthData() {
  return new Promise((resolve) => {
    if (window.parent) {
      window.parent.postMessage({ type: "IFRAME_READY" }, "*");
    }

    window.addEventListener("message", function handler(event) {
      if (event.data && event.data.type === "AUTH_DATA") {
        window.removeEventListener("message", handler);
        resolve(event.data.data);
      }
    });
  });
}

/**
 * Prüft, ob ein Tagebuch Einträge hat
 */
async function hasEintraege(dayId) {
  try {
    const eintraegeRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege");
    const eintraegeSnapshot = await getDocs(eintraegeRef);
    return !eintraegeSnapshot.empty;
  } catch (error) {
    console.error(`Fehler beim Prüfen der Einträge für ${dayId}:`, error);
    return false;
  }
}

/**
 * Lädt alle Tagebücher für einen Monat (nur solche mit Einträgen)
 */
async function loadTagebuecherForMonth(month, year) {
  try {
    const tageRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage");
    const snapshot = await getDocs(tageRef);
    
    const tagebuecher = [];
    const daysInMonth = getDaysInMonth(month, year);
    
    // Erstelle Array für alle Tage des Monats (01-31/30)
    const monthTagebuecher = new Array(daysInMonth).fill(null);
    
    // Sammle alle Tagebuch-IDs für diesen Monat
    const dayIds = [];
    snapshot.forEach((docSnap) => {
      const dayId = docSnap.id;
      const data = docSnap.data();
      
      // Parse dayId (DD.MM.YYYY)
      const parsed = parseDayId(dayId);
      
      // Prüfe, ob dieser Tag zum ausgewählten Monat/Jahr gehört
      if (parsed.month === month && parsed.year === year) {
        dayIds.push({
          dayId: dayId,
          parsed: parsed,
          data: data
        });
      }
    });
    
    // Prüfe für jeden Tag, ob er Einträge hat
    for (const dayInfo of dayIds) {
      const hasEntries = await hasEintraege(dayInfo.dayId);
      if (hasEntries) {
        monthTagebuecher[dayInfo.parsed.day - 1] = {
          id: dayInfo.dayId,
          day: dayInfo.parsed.day,
          month: dayInfo.parsed.month,
          year: dayInfo.parsed.year,
          datum: dayInfo.data.datum || dayInfo.dayId,
          closed: dayInfo.data.closed || false,
          createdAt: dayInfo.data.createdAt,
          createdBy: dayInfo.data.createdBy,
          createdByName: dayInfo.data.createdByName || "Unbekannt"
        };
      }
    }
    
    return monthTagebuecher;
  } catch (error) {
    console.error("Fehler beim Laden der Tagebücher:", error);
    throw error;
  }
}

/**
 * Konvertiert DD.MM.YYYY zu YYYY-MM-DD (für date input)
 */
function convertDayIdToDateInput(dayId) {
  const [day, month, year] = dayId.split('.');
  return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
}

/**
 * Öffnet ein Tagebuch für einen bestimmten Tag
 */
function openTagebuch(dayId) {
  const frame = window.parent?.document.getElementById("contentFrame");
  if (frame) {
    // Navigiere zum Hauptmodul mit Datum als URL-Parameter
    const dateParam = convertDayIdToDateInput(dayId);
    frame.src = `/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html?date=${encodeURIComponent(dateParam)}`;
  } else {
    const dateParam = convertDayIdToDateInput(dayId);
    window.location.href = `/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html?date=${encodeURIComponent(dateParam)}`;
  }
}

/**
 * Rendert die Liste der Tagebücher (nur vorhandene Tagebücher)
 */
function renderTagebuecherList(tagebuecher) {
  if (!tagebuecher || tagebuecher.length === 0) {
    uebersichtList.innerHTML = '<div class="empty-message">Keine Tagebücher für diesen Monat gefunden.</div>';
    return;
  }
  
  // Filtere nur vorhandene Tagebücher
  const vorhandeneTagebuecher = tagebuecher.filter(tb => tb !== null);
  
  if (vorhandeneTagebuecher.length === 0) {
    uebersichtList.innerHTML = '<div class="empty-message">Keine Tagebücher für diesen Monat gefunden.</div>';
    return;
  }
  
  uebersichtList.innerHTML = '';
  
  vorhandeneTagebuecher.forEach((tagebuch) => {
    // Tag existiert
    const item = document.createElement('div');
    item.className = 'uebersicht-item clickable';
    item.dataset.dayId = tagebuch.id;
    
    item.innerHTML = `
      <div class="uebersicht-item-date">${formatDateDisplay(tagebuch.day, tagebuch.month, tagebuch.year)}</div>
      <div class="uebersicht-item-info">Tagebuch vorhanden</div>
      <div class="uebersicht-item-icon">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
          <circle cx="12" cy="12" r="3"></circle>
        </svg>
      </div>
    `;
    
    // Click-Handler für gesamte Zeile
    item.addEventListener('click', () => {
      openTagebuch(tagebuch.id);
    });
    
    uebersichtList.appendChild(item);
  });
}

/**
 * Lädt und zeigt die Tagebücher für den ausgewählten Monat/Jahr
 */
async function loadAndDisplayTagebuecher() {
  const month = parseInt(monthSelect.value, 10);
  const year = parseInt(yearSelect.value, 10);
  
  if (!month || !year) {
    uebersichtList.innerHTML = '<div class="error-message">Bitte Monat und Jahr auswählen.</div>';
    return;
  }
  
  uebersichtList.innerHTML = '<div class="loading-message">Lade Tagebücher...</div>';
  
  try {
    const tagebuecher = await loadTagebuecherForMonth(month, year);
    renderTagebuecherList(tagebuecher);
  } catch (error) {
    console.error("Fehler beim Laden:", error);
    uebersichtList.innerHTML = `<div class="error-message">Fehler beim Laden der Tagebücher: ${error.message}</div>`;
  }
}

/**
 * Initialisiert die Anwendung
 */
async function initializeApp() {
  try {
    // Zurück-Button Event Listener
    if (backBtn) {
      backBtn.addEventListener("click", () => {
        const frame = window.parent?.document.getElementById("contentFrame");
        if (frame) {
          frame.src = "/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html";
        } else {
          window.location.href = "/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html";
        }
      });
    }
    
    userAuthData = await waitForAuthData();
    console.log(`✅ OVD Einsatztagebuch Übersicht - Auth-Daten empfangen: Role ${userAuthData.role}, Company ${userAuthData.companyId}`);
    
    // Setze aktuellen Monat und Jahr als Standard
    const now = new Date();
    monthSelect.value = now.getMonth() + 1;
    yearSelect.value = now.getFullYear();
    
    // Event Listener für Laden-Button
    if (loadBtn) {
      loadBtn.addEventListener("click", loadAndDisplayTagebuecher);
    }
    
    // Event Listener für Enter-Taste in Jahr-Eingabe
    if (yearSelect) {
      yearSelect.addEventListener("keypress", (e) => {
        if (e.key === 'Enter') {
          loadAndDisplayTagebuecher();
        }
      });
    }
    
    console.log("✅ OVD Einsatztagebuch Übersicht Modul initialisiert");
  } catch (error) {
    console.error("❌ Fehler bei der Initialisierung:", error);
    if (mainContent) {
      mainContent.innerHTML = '<div class="error-message">Fehler beim Laden des Moduls.</div>';
    }
  }
}

// Starte Initialisierung
window.addEventListener("DOMContentLoaded", initializeApp);

// Sende IFRAME_READY sofort, falls Parent bereits bereit ist
if (window.parent) {
  window.parent.postMessage({ type: "IFRAME_READY" }, "*");
}

