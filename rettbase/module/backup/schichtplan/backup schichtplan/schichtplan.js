// schichtplan.js – Neuaufbau mit Bereitschaften
// - Auth-Handshake über das Dashboard
// - Kalender oben
// - Tages-Popup mit Gesamtübersicht aller Standorte
// - Schichten pro Standort mit 2 Personal-Slots
// - Personal-Auswahl über Popup
// - Bereitschaften je Tag: Top-Grid im Popup + Zählung im Kalender ("X offen / Y Bereitschaft(en)")

import { db } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  deleteDoc,
  addDoc,
  query,
  orderBy,
  onSnapshot,
  collectionGroup,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände & Konstanten
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, ... }

const QUALIFIKATIONEN = ["RH", "RS", "RA", "NFS"];

let allStandorte = [];
let allSchichten = [];
let allMitarbeiter = [];
let allBereitschaftsTypen = [];

// Firestore-Listener für Live-Updates (werden beim Monatswechsel entfernt)
let activeCalendarListeners = [];

// Entfernt alle aktiven Kalender-Listener
function cleanupCalendarListeners() {
  activeCalendarListeners.forEach(unsubscribe => {
    try {
      unsubscribe();
    } catch (e) {
      console.warn("Fehler beim Entfernen eines Kalender-Listeners:", e);
    }
  });
  activeCalendarListeners = [];
}

// Richtet Firestore-Listener für alle Tage des aktuellen Monats ein
function setupCalendarListeners(year, month) {
  // Entferne alte Listener
  cleanupCalendarListeners();
  
  if (!allStandorte || allStandorte.length === 0) {
    console.warn("⚠️ Kann keine Listener einrichten: allStandorte noch nicht geladen");
    return;
  }
  
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const companyId = getCompanyId();
  const activeStandorte = allStandorte.filter(s => s && s.id && s.active !== false);
  
  console.log(`📡 Richte Live-Listener für ${daysInMonth} Tage im Monat ${month + 1}/${year} ein...`);
  console.log(`   Aktive Standorte: ${activeStandorte.length}`);
  
  let listenerCount = 0;
  
  // Für jeden Tag des Monats
  for (let day = 1; day <= daysInMonth; day++) {
    // Firestore-Dokument-IDs sind im Display-Format (DD.MM.YYYY) gespeichert
    const date = new Date(year, month, day);
    const dayIdDisplay = formatDayId(date);
    
    // Für jeden Standort einen Listener einrichten
    for (const standort of activeStandorte) {
      try {
        // Listener für Schichten dieses Tages (verwendet Display-Format DD.MM.YYYY, da Firestore-Dokument-IDs in diesem Format gespeichert sind)
        const shiftsCollection = getShiftsCollection(standort.id, dayIdDisplay);
        const unsubscribeShifts = onSnapshot(
          shiftsCollection,
          (snapshot) => {
            // Bei Änderungen: Tag im Kalender aktualisieren (verwendet Display-Format)
            console.log(`🔄 Live-Update: Schichten für Tag ${dayIdDisplay}, Standort ${standort.name} geändert (${snapshot.size} Schichten)`);
            loadCalendarDayShifts(dayIdDisplay).catch(e => 
              console.error(`Fehler beim Live-Update für Tag ${dayIdDisplay}:`, e)
            );
            
            // Wenn das Day-Popup für diesen Tag geöffnet ist, aktualisiere es auch
            // Nur aktualisieren, wenn das Popup tatsächlich sichtbar ist (nicht nur currentDayId gesetzt)
            if (currentDayId === dayIdDisplay && dayPopupForm && dayPopupForm.style.display === "block") {
              showCalendarDayDetails(dayIdDisplay).catch(e =>
                console.error(`Fehler beim Live-Update des Day-Popups für Tag ${dayIdDisplay}:`, e)
              );
            }
          },
          (error) => {
            console.error(`❌ Fehler im Listener für Schichten (Tag ${dayIdDisplay}, Standort ${standort.id}):`, error);
          }
        );
        
        activeCalendarListeners.push(unsubscribeShifts);
        listenerCount++;
        
        // Listener für Bereitschaften dieses Tages (verwendet Display-Format DD.MM.YYYY, da Firestore-Dokument-IDs in diesem Format gespeichert sind)
        const bereitschaftenCollection = getBereitschaftenCollection(standort.id, dayIdDisplay);
        const unsubscribeBereitschaften = onSnapshot(
          bereitschaftenCollection,
          (snapshot) => {
            // Bei Änderungen: Tag im Kalender aktualisieren (verwendet Display-Format)
            console.log(`🔄 Live-Update: Bereitschaften für Tag ${dayIdDisplay}, Standort ${standort.name} geändert (${snapshot.size} Bereitschaften)`);
            loadCalendarDayShifts(dayIdDisplay).catch(e => 
              console.error(`Fehler beim Live-Update für Tag ${dayIdDisplay}:`, e)
            );
            
            // Wenn das Day-Popup für diesen Tag geöffnet ist, aktualisiere es auch
            // Nur aktualisieren, wenn das Popup tatsächlich sichtbar ist (nicht nur currentDayId gesetzt)
            if (currentDayId === dayIdDisplay && dayPopupForm && dayPopupForm.style.display === "block") {
              showCalendarDayDetails(dayIdDisplay).catch(e =>
                console.error(`Fehler beim Live-Update des Day-Popups für Tag ${dayIdDisplay}:`, e)
              );
            }
          },
          (error) => {
            console.error(`❌ Fehler im Listener für Bereitschaften (Tag ${dayIdDisplay}, Standort ${standort.id}):`, error);
          }
        );
        
        activeCalendarListeners.push(unsubscribeBereitschaften);
        listenerCount++;
      } catch (e) {
        console.error(`❌ Fehler beim Einrichten des Listeners für Tag ${dayIdDisplay}, Standort ${standort.id}:`, e);
      }
    }
  }
  
  console.log(`✅ ${listenerCount} Live-Listener eingerichtet (${activeCalendarListeners.length} in Liste)`);
}

let currentDayId = null; // aktuell im Popup angezeigter Tag
// Hinweis: frühere visuelle Auswahl im Kalender (selectedCalendarDayElement)
// wurde entfernt, damit nur noch die Rot/Grün-Belegung sichtbar ist.

// DOM-Elemente
const calendarContainer = document.getElementById("calendarContainer");
const daysArea = document.getElementById("daysArea");

// SVG-Icons - Feather Icons Trash (professionelles, klassisches Papierkorb-Icon)
// Icon-Farbe wird dynamisch basierend auf Hintergrundfarbe gesetzt
function getTrashIconSVG(backgroundColor = "#ffffff") {
  // Helligkeit des Hintergrunds berechnen
  const rgb = hexToRgb(backgroundColor);
  if (!rgb) return getTrashIconSVGWithColor("currentColor"); // Fallback
  
  // Relative Luminanz berechnen (für WCAG-Kontrast)
  const luminance = (0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b) / 255;
  
  // Bei hellem Hintergrund (luminance > 0.5) schwarzes Icon, sonst weißes
  const iconColor = luminance > 0.5 ? "#000000" : "#ffffff";
  
  return getTrashIconSVGWithColor(iconColor);
}

function getTrashIconSVGWithColor(color) {
  return `<svg class="icon-trash-svg" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true" focusable="false" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"></path><path d="M10 11v6"></path><path d="M14 11v6"></path><path d="M9 6V3h6v3"></path></svg>`;
}

function hexToRgb(hex) {
  // Entferne # falls vorhanden
  hex = hex.replace("#", "");
  // Kurze Hex (#fff) zu langer Hex (#ffffff) konvertieren
  if (hex.length === 3) {
    hex = hex.split("").map(c => c + c).join("");
  }
  const result = /^([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result ? {
    r: parseInt(result[1], 16),
    g: parseInt(result[2], 16),
    b: parseInt(result[3], 16)
  } : null;
}

// Standard-Icon (für Fälle ohne Hintergrund-Info)
const TRASH_ICON_SVG = getTrashIconSVGWithColor("currentColor");

// Aktuell im Kalender angezeigter Monat/Jahr
let calendarCurrentDate = new Date();

// Frühere Kalender-Auswahl-Logik entfernt, damit nur noch Rot/Grün-Hintergrund wirkt.

// Tages-Popup
const dayPopupOverlay = document.getElementById("dayPopupOverlay");
const dayPopupForm = document.getElementById("dayPopupForm");
const dayPopupTitle = document.getElementById("dayPopupTitle");
const dayOverviewContent = document.getElementById("dayOverviewContent");
const dayBereitschaftenTop = document.getElementById("dayBereitschaftenTop");

// Personal-Popup
const personnelPopupOverlay = document.getElementById("personnelPopupOverlay");
const personnelPopupForm = document.getElementById("personnelPopupForm");
const personnelMitarbeiterSearch = document.getElementById("personnelMitarbeiterSearch");
const personnelMitarbeiterSelect = document.getElementById("personnelMitarbeiterSelect");
const personnelColor = document.getElementById("personnelColor");
const personnelColorLabel = document.getElementById("personnelColorLabel");
const savePersonnelBtn = document.getElementById("savePersonnelBtn");
const bereitschaftsTypLabel = document.getElementById("bereitschaftsTypLabel");
const bereitschaftsTypSelect = document.getElementById("bereitschaftsTypSelect");

// Button im Tages-Popup zum Anlegen einer Bereitschaft
const addBereitschaftForDayBtn = document.getElementById("addBereitschaftForDayBtn");

// Settings-Popups (nur zum Schließen/Öffnen)
const settingsBtn = document.getElementById("settingsBtn");
const settingsPopupOverlay = document.getElementById("settingsPopupOverlay");
const settingsPopupForm = document.getElementById("settingsPopupForm");

// ---------------------------------------------------------
// Hilfsfunktionen Firestore Pfade
// ---------------------------------------------------------

function getCompanyId() {
  if (!userAuthData || !userAuthData.companyId) {
    throw new Error("Keine CompanyId im Auth-Kontext verfügbar");
  }
  return userAuthData.companyId;
}

function getStandorteCollection() {
  const companyId = getCompanyId();
  return collection(db, "kunden", companyId, "schichtplanStandorte");
}

function getSchichtenDefinitionCollection() {
  const companyId = getCompanyId();
  return collection(db, "kunden", companyId, "schichtplanSchichten");
}

function getMitarbeiterCollection() {
  const companyId = getCompanyId();
  return collection(db, "kunden", companyId, "schichtplanMitarbeiter");
}

function getBereitschaftsTypenCollection() {
  const companyId = getCompanyId();
  // Einzel-Collection, für collectionGroup "schichtplanBereitschaftsTypen"
  return collection(db, "kunden", companyId, "schichtplanBereitschaftsTypen");
}

// Hilfsfunktion: Lesbaren Schichtnamen für Tages-Schichten ermitteln
function getShiftDisplayName(standortId, shiftId, data) {
  // 1) Direkt im Tages-Dokument hinterlegt?
  if (data && data.shiftName) {
    return data.shiftName;
  }
  // 2) Versuch, über Stammdaten zuordnen (id oder name)
  const def =
    (allSchichten || []).find(
      (s) => {
        const sStandortId = s.standortId;
        const standortIdStr = String(standortId);
        let matchesStandort = false;
        
        if (sStandortId === undefined || sStandortId === null) {
          matchesStandort = false;
        } else if (typeof sStandortId === 'object' && sStandortId.id) {
          matchesStandort = String(sStandortId.id) === standortIdStr;
        } else {
          matchesStandort = String(sStandortId) === standortIdStr;
        }
        
        return matchesStandort && (s.id === shiftId || s.name === shiftId);
      }
    ) || null;
  if (def && def.name) {
    return def.name;
  }
  // 3) Fallback: lieber leer als kryptische ID anzeigen
  return "";
}

// Tag / Schichten / Bereitschaften pro Tag
function getDayDocRef(standortId, dayId) {
  const companyId = getCompanyId();
  return doc(db, "kunden", companyId, "schichtplan", standortId, "tage", dayId);
}

function getShiftsCollection(standortId, dayId) {
  const companyId = getCompanyId();
  return collection(db, "kunden", companyId, "schichtplan", standortId, "tage", dayId, "schichten");
}

function getBereitschaftenCollection(standortId, dayId) {
  const companyId = getCompanyId();
  return collection(db, "kunden", companyId, "schichtplan", standortId, "tage", dayId, "bereitschaften");
}

// ---------------------------------------------------------
// Auth-Handshake mit dem Dashboard (Parent-Frame)
// ---------------------------------------------------------

function waitForAuthData() {
  return new Promise((resolve) => {
    // 1. IFRAME_READY an Parent senden
    if (window.parent) {
      window.parent.postMessage({ type: "IFRAME_READY" }, "*");
      console.log("➡️ Schichtplan: IFRAME_READY gesendet");
    }

    // 2. Auf AUTH_DATA warten
    function handler(event) {
      if (event.data && event.data.type === "AUTH_DATA") {
        window.removeEventListener("message", handler);
        console.log("⬅️ Schichtplan: AUTH_DATA empfangen");
        resolve(event.data.data); // { role, companyId, uid }
      }
    }

    window.addEventListener("message", handler);
  });
}

// ---------------------------------------------------------
// Cleanup: Automatisches Löschen von Daten älter als 12 Monate
// ---------------------------------------------------------

async function cleanupOldData() {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    // Berechne Datum vor 12 Monaten (vom aktuellen Datum)
    const cutoffDate = new Date(today);
    cutoffDate.setMonth(cutoffDate.getMonth() - 12);
    cutoffDate.setHours(0, 0, 0, 0);
    
    const cutoffDateStr = `${cutoffDate.getFullYear()}-${String(cutoffDate.getMonth() + 1).padStart(2, "0")}-${String(cutoffDate.getDate()).padStart(2, "0")}`;
    
    console.log(`🧹 Starte Cleanup für Daten älter als 12 Monate (vor ${cutoffDateStr})`);
    
    const companyId = getCompanyId();
    let totalDeletedDays = 0;
    let totalDeletedShifts = 0;
    let totalDeletedBereitschaften = 0;
    
    // Lade alle Standorte (inkl. gelöschter, da diese auch historische Daten haben können)
    const standorteSnap = await getDocs(getStandorteCollection());
    
    for (const standortDoc of standorteSnap.docs) {
      const standortId = standortDoc.id;
      
      try {
        // Lade alle Tage für diesen Standort
        const tageCollection = collection(db, "kunden", companyId, "schichtplan", standortId, "tage");
        const tageSnapshot = await getDocs(tageCollection);
        
        for (const tagDoc of tageSnapshot.docs) {
          const dayId = tagDoc.id;
          
          // Parse dayId zu Datum
          const dayDate = parseDayId(dayId);
          if (!dayDate || isNaN(dayDate.getTime())) {
            console.warn(`⚠️ Konnte Datum nicht parsen: ${dayId}, überspringe`);
            continue;
          }
          
          dayDate.setHours(0, 0, 0, 0);
          
          // Prüfe ob Tag älter als 12 Monate ist
          if (dayDate < cutoffDate) {
            console.log(`🗑️ Lösche alten Tag: ${dayId} (${dayDate.toISOString().split('T')[0]}) für Standort ${standortId}`);
            
            // Lösche alle Schichten dieses Tages
            const schichtenCollection = getShiftsCollection(standortId, dayId);
            const schichtenSnapshot = await getDocs(schichtenCollection);
            let deletedShifts = 0;
            for (const schichtDoc of schichtenSnapshot.docs) {
              await deleteDoc(schichtDoc.ref);
              deletedShifts++;
            }
            
            // Lösche alle Bereitschaften dieses Tages
            const bereitschaftenCollection = getBereitschaftenCollection(standortId, dayId);
            const bereitschaftenSnapshot = await getDocs(bereitschaftenCollection);
            let deletedBereitschaften = 0;
            for (const bereitschaftDoc of bereitschaftenSnapshot.docs) {
              await deleteDoc(bereitschaftDoc.ref);
              deletedBereitschaften++;
            }
            
            // Lösche das Tage-Dokument selbst
            await deleteDoc(tagDoc.ref);
            
            totalDeletedDays++;
            totalDeletedShifts += deletedShifts;
            totalDeletedBereitschaften += deletedBereitschaften;
            
            console.log(`   → ${deletedShifts} Schichten, ${deletedBereitschaften} Bereitschaften gelöscht`);
          }
        }
      } catch (e) {
        console.error(`❌ Fehler beim Cleanup für Standort ${standortId}:`, e);
        // Weiter mit nächstem Standort
      }
    }
    
    console.log(`✅ Cleanup abgeschlossen: ${totalDeletedDays} Tage, ${totalDeletedShifts} Schichten, ${totalDeletedBereitschaften} Bereitschaften gelöscht`);
  } catch (e) {
    console.error("❌ Fehler beim Cleanup alter Daten:", e);
  }
}

async function initializeApp() {
  console.log(
    `✅ Initialisiere Schichtplan für Company: ${userAuthData.companyId}, Role: ${userAuthData.role}`
  );

  try {
    await Promise.all([loadStandorte(), loadSchichten(), loadMitarbeiter(), loadBereitschaftsTypen()]);
  } catch (e) {
    console.error("❌ Fehler beim Laden der Stammdaten:", e);
  }
  
  // Cleanup alter Daten (älter als 12 Monate) im Hintergrund ausführen
  // Nicht await, damit die App nicht blockiert wird
  cleanupOldData().catch(e => console.error("❌ Fehler beim Cleanup:", e));

  await renderCalendar();
  setupSettingsHandlers();
}

// ---------------------------------------------------------
// Laden von Stammdaten
// ---------------------------------------------------------

// Alle Standorte inkl. gelöschter (für historische Daten)
let allStandorteIncludingDeleted = [];

async function loadStandorte() {
  try {
    // Lade ALLE Standorte aus Firestore (inklusive gelöschter)
    const snap = await getDocs(getStandorteCollection());
    
    // WICHTIG: Speichere ALLE Standorte inklusive gelöschter für historische Daten
    // Auch gelöschte Standorte (deleted: true) müssen erhalten bleiben für vergangene Tage!
    const loadedStandorte = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    
    // Schritt 1: Entferne Duplikate basierend auf der ID (falls vorhanden)
    const seenIds = new Set();
    const uniqueById = loadedStandorte.filter(standort => {
      if (!standort || !standort.id) return false;
      if (seenIds.has(standort.id)) {
        console.warn(`⚠️ Duplikat-ID beim Laden entfernt: ${standort.name} (ID: ${standort.id})`);
        return false;
      }
      seenIds.add(standort.id);
      return true;
    });
    
    // Schritt 2: Entferne Duplikate basierend auf dem Namen (behält nur einen pro Namen)
    allStandorteIncludingDeleted = removeDuplicateStandorteByName(uniqueById);
    
    console.log(`📦 Alle Standorte geladen (nach ID-Deduplizierung: ${uniqueById.length}, nach Namen-Deduplizierung: ${allStandorteIncludingDeleted.length})`);
    console.log(`📋 Standorte-Details:`, allStandorteIncludingDeleted.map(s => `${s.name} (${s.id})`).join(", "));
    
    // Filtere nur aktive Standorte für normale Anzeige (gelöschte werden nicht mehr in der Liste angezeigt)
    allStandorte = allStandorteIncludingDeleted.filter((s) => s.active !== false && s.deleted !== true);
    
    console.log(`✅ Aktive Standorte: ${allStandorte.length}`);
    console.log(`🗑️ Gelöschte Standorte (für Historie behalten): ${allStandorteIncludingDeleted.length - allStandorte.length}`);
    
    // Manuelle Sortierung nach order, dann nach name
    allStandorte.sort((a, b) => {
      const orderA = a.order !== undefined ? a.order : 9999;
      const orderB = b.order !== undefined ? b.order : 9999;
      if (orderA !== orderB) return orderA - orderB;
      // Falls order gleich ist, alphabetisch nach Name
      const nameA = (a.name || "").toLowerCase();
      const nameB = (b.name || "").toLowerCase();
      return nameA.localeCompare(nameB);
    });
    
    // Sortiere auch allStandorteIncludingDeleted für Konsistenz
    allStandorteIncludingDeleted.sort((a, b) => {
      const orderA = a.order !== undefined ? a.order : 9999;
      const orderB = b.order !== undefined ? b.order : 9999;
      if (orderA !== orderB) return orderA - orderB;
      const nameA = (a.name || "").toLowerCase();
      const nameB = (b.name || "").toLowerCase();
      return nameA.localeCompare(nameB);
    });
    
    console.log("📍 Aktive Standorte:", allStandorte.map((s) => s.name).join(", "));
  } catch (e) {
    console.error("❌ Fehler beim Laden der Standorte:", e);
  }
}

// Hilfsfunktion: Parse Datum aus verschiedenen Formaten (ISO: "2025-12-10" oder DE: "10.12.2025")
function parseDayId(dayId) {
  // Versuche ISO-Format zuerst (YYYY-MM-DD)
  if (dayId.includes("-")) {
    const parts = dayId.split("-");
    if (parts.length === 3) {
      const year = parseInt(parts[0], 10);
      const month = parseInt(parts[1], 10);
      const day = parseInt(parts[2], 10);
      if (!isNaN(year) && !isNaN(month) && !isNaN(day)) {
        return new Date(year, month - 1, day);
      }
    }
  }
  
  // Versuche deutsches Format (DD.MM.YYYY)
  if (dayId.includes(".")) {
    const parts = dayId.split(".");
    if (parts.length === 3) {
      const day = parseInt(parts[0], 10);
      const month = parseInt(parts[1], 10);
      const year = parseInt(parts[2], 10);
      if (!isNaN(year) && !isNaN(month) && !isNaN(day)) {
        return new Date(year, month - 1, day);
      }
    }
  }
  
  return null;
}

// Hilfsfunktion: Entfernt Duplikate aus einem Array von Standorten basierend auf der ID
function removeDuplicateStandorte(standorte) {
  const seen = new Set();
  return standorte.filter(standort => {
    if (!standort || !standort.id) return false;
    if (seen.has(standort.id)) {
      console.warn(`⚠️ Duplikat-ID gefunden und entfernt: ${standort.name} (ID: ${standort.id})`);
      return false;
    }
    seen.add(standort.id);
    return true;
  });
}

// Hilfsfunktion: Entfernt Duplikate basierend auf dem Namen (behält nur einen Standort pro Namen)
// Bevorzugt aktive Standorte, dann den neuesten (basierend auf deletedAt oder ID)
function removeDuplicateStandorteByName(standorte) {
  const standorteByName = new Map();
  
  standorte.forEach(standort => {
    if (!standort || !standort.name) return;
    
    const nameKey = standort.name.trim().toLowerCase();
    const existing = standorteByName.get(nameKey);
    
    if (!existing) {
      // Erster Standort mit diesem Namen
      standorteByName.set(nameKey, standort);
    } else {
      // Duplikat nach Namen gefunden - entscheide welcher behalten wird
      // Bevorzuge: 1. Aktive über gelöschte, 2. Neueste deletedAt, 3. Aktuellen behalten
      const existingIsActive = existing.active !== false && existing.deleted !== true;
      const currentIsActive = standort.active !== false && standort.deleted !== true;
      
      if (currentIsActive && !existingIsActive) {
        // Aktueller ist aktiv, bestehender nicht -> ersetze
        console.warn(`⚠️ Duplikat-Name entfernt (aktiver behalten): ${standort.name} - ID ${existing.id} wird entfernt, ID ${standort.id} bleibt`);
        standorteByName.set(nameKey, standort);
      } else if (!currentIsActive && existingIsActive) {
        // Bestehender ist aktiv, aktueller nicht -> behalte bestehenden
        console.warn(`⚠️ Duplikat-Name entfernt (aktiver behalten): ${standort.name} - ID ${standort.id} wird entfernt, ID ${existing.id} bleibt`);
      } else {
        // Beide aktiv oder beide gelöscht - behalte den mit der neueren deletedAt oder den ersten
        const existingDeletedAt = existing.deletedAt || '';
        const currentDeletedAt = standort.deletedAt || '';
        
        if (currentDeletedAt > existingDeletedAt) {
          // Aktueller ist neuer
          console.warn(`⚠️ Duplikat-Name entfernt (neuerer behalten): ${standort.name} - ID ${existing.id} wird entfernt, ID ${standort.id} bleibt`);
          standorteByName.set(nameKey, standort);
        } else {
          // Bestehender ist neuer oder gleich alt
          console.warn(`⚠️ Duplikat-Name entfernt (neuerer behalten): ${standort.name} - ID ${standort.id} wird entfernt, ID ${existing.id} bleibt`);
        }
      }
    }
  });
  
  return Array.from(standorteByName.values());
}

// Hilfsfunktion: Gibt Standorte für einen bestimmten Tag zurück (inkl. gelöschter für vergangene Tage)
function getStandorteForDay(dayId) {
  try {
    // Fallback: Wenn allStandorteIncludingDeleted noch nicht geladen ist, verwende allStandorte
    if (!allStandorteIncludingDeleted || allStandorteIncludingDeleted.length === 0) {
      return removeDuplicateStandorte(allStandorte || []);
    }
    
    // Parse Tag-String zu Datum (unterstützt verschiedene Formate)
    const dayDate = parseDayId(dayId);
    if (!dayDate || isNaN(dayDate.getTime())) {
      console.error(`❌ Ungültiges Datum in getStandorteForDay: ${dayId}`);
      return removeDuplicateStandorte(allStandorte || []);
    }
    
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    dayDate.setHours(0, 0, 0, 0);
    
    // Wenn Tag in der Vergangenheit liegt (vor heute), zeige ALLE Standorte inkl. gelöschter
    // Das ermöglicht, historische Schichten anzuzeigen, auch wenn der Standort später gelöscht wurde
    if (dayDate < today) {
      // Für vergangene Tage: Alle Standorte zurückgeben (inkl. gelöschter), aber ohne Duplikate
      return removeDuplicateStandorte(allStandorteIncludingDeleted);
    }
    
    // Für zukünftige Tage nur aktive Standorte (nicht gelöschte), ohne Duplikate
    return removeDuplicateStandorte(allStandorte || []);
  } catch (e) {
    console.error(`❌ Fehler in getStandorteForDay für ${dayId}:`, e);
    return removeDuplicateStandorte(allStandorte || []);
  }
}

async function loadSchichten() {
  try {
    // Lade alle Schichten (auch ohne order-Feld)
    const snap = await getDocs(getSchichtenDefinitionCollection());
    allSchichten = snap.docs.map((d) => {
      const data = d.data();
      // Normalisiere standortId: Falls es ein Referenz-Objekt ist, extrahiere die ID
      if (data.standortId && typeof data.standortId === 'object' && data.standortId.id) {
        data.standortId = data.standortId.id;
      }
      // Trim für Leerzeichen
      if (typeof data.standortId === 'string') {
        data.standortId = data.standortId.trim();
      }
      return { id: d.id, ...data };
    });
    
    // Sortiere nach order (falls vorhanden), sonst nach name
    allSchichten.sort((a, b) => {
      const orderA = a.order !== undefined ? a.order : 999999;
      const orderB = b.order !== undefined ? b.order : 999999;
      if (orderA !== orderB) return orderA - orderB;
      return (a.name || "").localeCompare(b.name || "");
    });
    
    console.log("📋 Schicht-Typen geladen:", allSchichten.map((s) => `${s.name} (Standort: ${s.standortId}, ID: ${s.id}, order: ${s.order || 'kein'})`).join(", "));
    console.log("📋 Gesamtanzahl Schichten:", allSchichten.length);
    
    // Debug: Zeige alle Schichten für RW-Holzwickede und RW-Fröndenberg (case-insensitive)
    const holzwickedeSchichten = allSchichten.filter(s => {
      const sId = String(s.standortId || '').toLowerCase();
      return sId.includes('holzwickede') || sId === 'rw-holzwickede';
    });
    const froendenbergSchichten = allSchichten.filter(s => {
      const sId = String(s.standortId || '').toLowerCase();
      return sId.includes('fröndenberg') || sId.includes('froendenberg') || sId === 'rw-fröndenberg';
    });
    const ktwWacheSchichten = allSchichten.filter(s => {
      const sId = String(s.standortId || '').toLowerCase();
      return sId.includes('ktw') || sId === 'ktw-wache';
    });
    
    console.log(`🏢 KTW-Wache Schichten (${ktwWacheSchichten.length} gefunden - funktioniert):`, ktwWacheSchichten.map(s => `${s.name} (standortId: "${s.standortId}", ID: ${s.id})`));
    
    if (holzwickedeSchichten.length > 0) {
      console.log(`🏢 RW-Holzwickede Schichten (${holzwickedeSchichten.length} gefunden):`, holzwickedeSchichten.map(s => `${s.name} (standortId: "${s.standortId}", ID: ${s.id})`));
    } else {
      console.warn("⚠️ KEINE Schichten für RW-Holzwickede gefunden!");
    }
    if (froendenbergSchichten.length > 0) {
      console.log(`🏢 RW-Fröndenberg Schichten (${froendenbergSchichten.length} gefunden):`, froendenbergSchichten.map(s => `${s.name} (standortId: "${s.standortId}", ID: ${s.id})`));
    } else {
      console.warn("⚠️ KEINE Schichten für RW-Fröndenberg gefunden!");
    }
    
    // Finde die Standort-IDs für Vergleich
    const holzwickedeStandort = allStandorte.find(s => s.name && s.name.toLowerCase().includes('holzwickede'));
    const froendenbergStandort = allStandorte.find(s => s.name && s.name.toLowerCase().includes('fröndenberg'));
    const ktwWacheStandort = allStandorte.find(s => s.name && s.name.toLowerCase().includes('ktw'));
    
    console.log(`🏢 Standort-IDs Vergleich:`);
    console.log(`   KTW-Wache: ID="${ktwWacheStandort?.id}", Name="${ktwWacheStandort?.name}"`);
    console.log(`   RW-Holzwickede: ID="${holzwickedeStandort?.id}", Name="${holzwickedeStandort?.name}"`);
    console.log(`   RW-Fröndenberg: ID="${froendenbergStandort?.id}", Name="${froendenbergStandort?.name}"`);
  } catch (e) {
    console.error("❌ Fehler beim Laden der Schichten:", e);
  }
}

async function loadMitarbeiter() {
  try {
    const snap = await getDocs(query(getMitarbeiterCollection(), orderBy("nachname", "asc")));
    allMitarbeiter = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    console.log("👥 Mitarbeiter geladen:", allMitarbeiter.length);
  } catch (e) {
    console.error("❌ Fehler beim Laden der Mitarbeiter:", e);
  }
}

async function loadBereitschaftsTypen() {
  try {
    const snap = await getDocs(query(getBereitschaftsTypenCollection(), orderBy("name", "asc")));
    allBereitschaftsTypen = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    console.log(
      "📋 Bereitschafts-Typen geladen:",
      allBereitschaftsTypen.map((b) => b.name).join(", ")
    );
  } catch (e) {
    console.error("❌ Fehler beim Laden der Bereitschafts-Typen:", e);
  }
}

// Aktualisiere Mitarbeiter-Daten in allen Schichten und Bereitschaften (Live-Aktualisierung)
async function updateMitarbeiterInAllShifts(mitarbeiterId, updatedMitarbeiterData) {
  try {
    console.log(`🔄 Aktualisiere Mitarbeiter ${mitarbeiterId} in allen Schichten und Bereitschaften...`);
    
    const updatedName = `${updatedMitarbeiterData.vorname || ""} ${updatedMitarbeiterData.nachname || ""}`.trim();
    const updatedQualis = QUALIFIKATIONEN.filter((q) => (updatedMitarbeiterData.qualifikation || []).includes(q));
    
    // Aktualisiere alle Standorte (nur aktive Standorte)
    for (const standort of allStandorte) {
      if (standort.active === false) continue;
      
      // Hole alle Tage des aktuellen und nächsten Monats (für Performance)
      const now = new Date();
      const currentMonth = now.getMonth();
      const currentYear = now.getFullYear();
      
      // Aktualisiere aktuellen und nächsten Monat
      for (let monthOffset = 0; monthOffset <= 1; monthOffset++) {
        const targetMonth = currentMonth + monthOffset;
        const targetYear = targetMonth > 11 ? currentYear + 1 : currentYear;
        const daysInMonth = new Date(targetYear, targetMonth + 1, 0).getDate();
        
        for (let day = 1; day <= daysInMonth; day++) {
          const dayId = `${targetYear}-${String(targetMonth + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
          
          try {
            // Aktualisiere Schichten
            const shiftsCol = getShiftsCollection(standort.id, dayId);
            const shiftsSnap = await getDocs(shiftsCol);
            
            const shiftUpdates = [];
            shiftsSnap.forEach((shiftDoc) => {
              const shiftData = shiftDoc.data();
              let needsUpdate = false;
              const updateData = {};
              
              // Prüfe personal1
              if (shiftData.personal1?.mitarbeiterId === mitarbeiterId) {
                updateData.personal1 = {
                  ...shiftData.personal1,
                  name: updatedName,
                  qualifikationen: updatedQualis,
                };
                needsUpdate = true;
              }
              
              // Prüfe personal2
              if (shiftData.personal2?.mitarbeiterId === mitarbeiterId) {
                updateData.personal2 = {
                  ...shiftData.personal2,
                  name: updatedName,
                  qualifikationen: updatedQualis,
                };
                needsUpdate = true;
              }
              
              if (needsUpdate) {
                shiftUpdates.push({
                  ref: doc(shiftsCol, shiftDoc.id),
                  data: updateData,
                });
              }
            });
            
            // Führe Updates aus
            await Promise.all(shiftUpdates.map(({ ref, data }) => setDoc(ref, data, { merge: true })));
            
            // Aktualisiere Bereitschaften
            const bereitschaftenCol = getBereitschaftenCollection(standort.id, dayId);
            const bereitschaftenSnap = await getDocs(bereitschaftenCol);
            
            const bereitschaftUpdates = [];
            bereitschaftenSnap.forEach((bereitschaftDoc) => {
              const bereitschaftData = bereitschaftDoc.data();
              if (bereitschaftData.mitarbeiterId === mitarbeiterId) {
                bereitschaftUpdates.push({
                  ref: doc(bereitschaftenCol, bereitschaftDoc.id),
                  data: {
                    ...bereitschaftData,
                    name: updatedName,
                    qualifikationen: updatedQualis,
                  },
                });
              }
            });
            
            await Promise.all(bereitschaftUpdates.map(({ ref, data }) => setDoc(ref, data, { merge: true })));
            
          } catch (dayError) {
            console.warn(`⚠️ Fehler beim Aktualisieren von Tag ${dayId} für Standort ${standort.id}:`, dayError);
          }
        }
      }
    }
    
    console.log(`✅ Mitarbeiter ${mitarbeiterId} erfolgreich in allen Schichten und Bereitschaften aktualisiert`);
  } catch (e) {
    console.error(`❌ Fehler beim Aktualisieren von Mitarbeiter ${mitarbeiterId} in Schichten:`, e);
  }
}

// ---------------------------------------------------------
// Kalender
// ---------------------------------------------------------

function formatDayId(date) {
  const day = String(date.getDate()).padStart(2, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const year = date.getFullYear();
  return `${day}.${month}.${year}`;
}

// Konvertiert dayId von Display-Format (DD.MM.YYYY) zu ISO-Format (YYYY-MM-DD) oder umgekehrt
function convertDayIdFormat(dayId, targetFormat = 'iso') {
  // Wenn bereits im Zielformat, direkt zurückgeben
  if (targetFormat === 'iso' && dayId.includes('-') && !dayId.includes('.')) {
    return dayId;
  }
  if (targetFormat === 'display' && dayId.includes('.') && !dayId.includes('-')) {
    return dayId;
  }
  
  // Parse dayId
  const dayDate = parseDayId(dayId);
  if (!dayDate || isNaN(dayDate.getTime())) {
    console.warn(`⚠️ Konnte dayId nicht parsen: ${dayId}`);
    return dayId; // Fallback: Original zurückgeben
  }
  
  // Zu Zielformat konvertieren
  const year = dayDate.getFullYear();
  const month = String(dayDate.getMonth() + 1).padStart(2, "0");
  const day = String(dayDate.getDate()).padStart(2, "0");
  
  if (targetFormat === 'iso') {
    return `${year}-${month}-${day}`;
  } else {
    return `${day}.${month}.${year}`;
  }
}

function getMonthName(monthIndex) {
  const months = [
    "Januar",
    "Februar",
    "März",
    "April",
    "Mai",
    "Juni",
    "Juli",
    "August",
    "September",
    "Oktober",
    "November",
    "Dezember",
  ];
  return months[monthIndex];
}

async function renderCalendar() {
  if (!calendarContainer) return;

  calendarContainer.innerHTML = '<div class="info-card">Lade Kalender...</div>';

  try {
    const today = new Date();
    const currentMonth = calendarCurrentDate.getMonth();
    const currentYear = calendarCurrentDate.getFullYear();

    const firstDay = new Date(currentYear, currentMonth, 1);
    const lastDay = new Date(currentYear, currentMonth + 1, 0);
    const daysInMonth = lastDay.getDate();

    // In JS: Sonntag = 0, Montag = 1 ... Wir wollen Mo-So, also verschieben
    let startingDayOfWeek = firstDay.getDay() - 1; // Montag = 0
    if (startingDayOfWeek < 0) startingDayOfWeek = 6;

    let html = `
      <div class="calendar-header-controls">
        <button id="prevMonthBtn" class="btn-small">← Vorheriger Monat</button>
        <h3>${getMonthName(currentMonth)} ${currentYear}</h3>
        <button id="nextMonthBtn" class="btn-small">Nächster Monat →</button>
      </div>
      <div class="calendar-grid">
        <div class="calendar-weekday">Mo</div>
        <div class="calendar-weekday">Di</div>
        <div class="calendar-weekday">Mi</div>
        <div class="calendar-weekday">Do</div>
        <div class="calendar-weekday">Fr</div>
        <div class="calendar-weekday">Sa</div>
        <div class="calendar-weekday">So</div>
    `;

    // Leere Zellen vor dem 1.
    for (let i = 0; i < startingDayOfWeek; i++) {
      html += '<div class="calendar-day empty"></div>';
    }

    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(currentYear, currentMonth, day);
      const dayId = formatDayId(date);
      const isToday =
        day === today.getDate() &&
        currentMonth === today.getMonth() &&
        currentYear === today.getFullYear();

      html += `
        <div class="calendar-day ${isToday ? "today" : ""}" data-day="${dayId}" onclick="showCalendarDayDetails('${dayId}')">
          <div class="calendar-day-number">${day}</div>
          <div class="calendar-day-shifts" id="shifts-${dayId}"></div>
        </div>
      `;
    }

    html += "</div>";
    calendarContainer.innerHTML = html;

    // WICHTIG: Warte kurz, damit das DOM vollständig gerendert ist
    await new Promise(resolve => setTimeout(resolve, 0));

    // Navigation für Vormonat / Folgemonat
    const prevMonthBtn = document.getElementById("prevMonthBtn");
    const nextMonthBtn = document.getElementById("nextMonthBtn");

    if (prevMonthBtn) {
      prevMonthBtn.addEventListener("click", async () => {
        // Einen Monat zurück
        const year = calendarCurrentDate.getFullYear();
        const month = calendarCurrentDate.getMonth();
        calendarCurrentDate = new Date(year, month - 1, 1);
        await renderCalendar();
      });
    }

    if (nextMonthBtn) {
      nextMonthBtn.addEventListener("click", async () => {
        // Einen Monat vor
        const year = calendarCurrentDate.getFullYear();
        const month = calendarCurrentDate.getMonth();
        calendarCurrentDate = new Date(year, month + 1, 1);
        await renderCalendar();
      });
    }

    // Richte Live-Listener für diesen Monat ein (muss nach dem Rendern passieren, damit allStandorte geladen ist)
    if (allStandorte && allStandorte.length > 0) {
      setupCalendarListeners(currentYear, currentMonth);
    }
    
    // Für jeden Tag offene Schichten / Bereitschaften laden (parallel, für bessere Performance)
    // WICHTIG: Stelle sicher, dass die DOM-Elemente vorhanden sind, bevor wir sie modifizieren
    const loadPromises = [];
    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(currentYear, currentMonth, day);
      const dayId = formatDayId(date);
      const containerId = `shifts-${dayId}`;
      
      // Prüfe, ob das Container-Element existiert
      const container = document.getElementById(containerId);
      if (container) {
        loadPromises.push(loadCalendarDayShifts(dayId));
      } else {
        console.warn(`⚠️ Container ${containerId} nicht gefunden für Tag ${dayId}`);
      }
    }
    
    if (loadPromises.length > 0) {
      await Promise.all(loadPromises);
      console.log(`✅ ${loadPromises.length} Tage im Kalender geladen`);
    }
  } catch (e) {
    console.error("Fehler beim Laden des Kalenders:", e);
    calendarContainer.innerHTML =
      '<div class="info-card" style="color: red;">Fehler beim Laden des Kalenders.</div>';
  }
}

async function loadCalendarDayShifts(dayId) {
  try {
    // dayId kommt im Display-Format (DD.MM.YYYY) vom Kalender
    // Firestore-Dokument-IDs sind ebenfalls im Format DD.MM.YYYY gespeichert
    const dayIdDisplay = dayId; // dayId ist bereits im Display-Format
    
    const shiftsContainer = document.getElementById(`shifts-${dayIdDisplay}`);
    if (!shiftsContainer) {
      console.warn(`⚠️ Container für Tag ${dayIdDisplay} nicht gefunden (ID: shifts-${dayIdDisplay})`);
      return;
    }

    // Debug: Log für Tag
    const dayIdForLog = dayIdDisplay;
    console.log(`📅 Lade Schichten für Tag: ${dayIdForLog}`);

    // Alle Standorte parallel durchlaufen und Schichten/Bereitschaften für diesen Tag zählen
    const standortResults = await Promise.all(
      allStandorte
        .filter((standort) => standort.active !== false)
        .map(async (standort) => {
          let standortOpenShifts = 0;
          let standortBereitschaften = 0;
          let standortHasShifts = false;
          
          try {
            // Lade Schichten direkt aus der Collection (auch wenn Tage-Dokument nicht existiert, für historische Daten)
            // WICHTIG: Verwende dayIdDisplay (DD.MM.YYYY), da die Firestore-Dokument-IDs in diesem Format gespeichert sind
            const shiftsCol = getShiftsCollection(standort.id, dayIdDisplay);
            const shiftsSnap = await getDocs(shiftsCol);

            if (!shiftsSnap.empty) {
              standortHasShifts = true;
              console.log(`  📋 ${standort.name}: ${shiftsSnap.size} Schicht(en) gefunden`);

              shiftsSnap.forEach((docSnap) => {
                const data = docSnap.data();
                const hasPersonal1 = !!data.personal1;
                const hasPersonal2 = !!data.personal2;
                const fullyManned = hasPersonal1 && hasPersonal2;
                
                if (!fullyManned) {
                  standortOpenShifts++;
                  console.log(`  ⚠️ Offene Schicht in ${standort.name} (personal1: ${hasPersonal1}, personal2: ${hasPersonal2})`);
                } else {
                  console.log(`  ✅ Voll besetzte Schicht in ${standort.name}`);
                }
              });
            }

            // Bereitschaften zählen (auch ohne Tage-Dokument)
            // WICHTIG: Verwende dayIdDisplay (DD.MM.YYYY), da die Firestore-Dokument-IDs in diesem Format gespeichert sind
            const bereitschaftenCol = getBereitschaftenCollection(standort.id, dayIdDisplay);
            const bereitsSnap = await getDocs(bereitschaftenCol);
            if (!bereitsSnap.empty) {
              standortBereitschaften = bereitsSnap.size;
              console.log(`  📋 ${standort.name}: ${standortBereitschaften} Bereitschaft(en) gefunden`);
            }
          } catch (err) {
            console.error(`❌ Fehler beim Laden für Standort ${standort.name}:`, err);
          }
          
          return {
            openShifts: standortOpenShifts,
            bereitschaften: standortBereitschaften,
            hasShifts: standortHasShifts
          };
        })
    );
    
    // Aggregiere Ergebnisse
    const openShifts = standortResults.reduce((sum, r) => sum + r.openShifts, 0);
    const bereitschaftenCount = standortResults.reduce((sum, r) => sum + r.bereitschaften, 0);
    // WICHTIG: Nur Schichten werden in die Farblogik einbezogen, Bereitschaften nicht
    const hadAnyShifts = standortResults.some(r => r.hasShifts);
    
    console.log(`📊 Tag ${dayIdDisplay}: ${openShifts} offene Schichten, ${bereitschaftenCount} Bereitschaften, hadAnyShifts: ${hadAnyShifts}`);

    // Finde das Day-Element (parent des shiftsContainer)
    const dayElement = shiftsContainer.closest(".calendar-day");
    
    if (!dayElement) {
      console.error(`❌ Day-Element für Tag ${dayIdDisplay} NICHT GEFUNDEN!`);
      console.error(`   shiftsContainer:`, shiftsContainer);
      console.error(`   shiftsContainer.parentElement:`, shiftsContainer.parentElement);
      return;
    }
    
    console.log(`🔍 Day-Element gefunden für ${dayIdDisplay}:`, dayElement);
    console.log(`🔍 Aktuelle Klassen vor Update:`, dayElement.className);
    console.log(`🔍 Aktueller backgroundColor vor Update:`, window.getComputedStyle(dayElement).backgroundColor);
    
    // Entferne alte Farbklassen
    dayElement.classList.remove("day-all-manned", "day-open-shifts");
    
    // Setze neue Farbklassen und inline-styles basierend auf den Daten
    // WICHTIG: Nur Schichten werden in die Farblogik einbezogen, Bereitschaften nicht
    if (openShifts > 0) {
      // ROT: Es gibt offene (nicht vollständig belegte) Schichten
      dayElement.classList.add("day-open-shifts");
      // Direkt die Eigenschaften setzen (inline-styles haben höchste Priorität)
      dayElement.style.backgroundColor = "#ffe0e0";
      dayElement.style.background = "#ffe0e0";
      dayElement.style.borderColor = "#b91c1c";
      console.log(`🔴 Tag ${dayIdDisplay}: ROT gesetzt (${openShifts} offene Schichten)`);
      console.log(`🔴 Inline style backgroundColor:`, dayElement.style.backgroundColor);
      console.log(`🔴 Inline style background:`, dayElement.style.background);
    } else if (hadAnyShifts) {
      // GRÜN: Alle Schichten vollständig besetzt
      dayElement.classList.add("day-all-manned");
      // Direkt die Eigenschaften setzen (inline-styles haben höchste Priorität)
      dayElement.style.backgroundColor = "#a8f3a8";
      dayElement.style.background = "#a8f3a8";
      dayElement.style.borderColor = "#a8f3a8";
      console.log(`🟢 Tag ${dayIdDisplay}: GRÜN gesetzt (alle Schichten vollständig besetzt)`);
      console.log(`🟢 Inline style backgroundColor:`, dayElement.style.backgroundColor);
      console.log(`🟢 Inline style background:`, dayElement.style.background);
    } else {
      // WEISS: Keine Schichten vorhanden (auch wenn Bereitschaften vorhanden sind)
      dayElement.style.backgroundColor = "white";
      dayElement.style.background = "white";
      dayElement.style.borderColor = "";
      console.log(`⚪ Tag ${dayIdDisplay}: Keine Markierung (weiß - keine Schichten, ${bereitschaftenCount} Bereitschaften werden ignoriert)`);
    }
    
    // Erstelle Info-HTML
    let infoHTML = "";
    if (openShifts > 0 || bereitschaftenCount > 0) {
      const lines = [];
      if (openShifts > 0) {
        lines.push(`<span class="calendar-shift-open">${openShifts} offen</span>`);
      }
      if (bereitschaftenCount > 0) {
        lines.push(`<span class="calendar-shift-bereitschaft">${bereitschaftenCount} Bereitschaft(en)</span>`);
      }
      infoHTML = `<div class="calendar-shift-info">${lines.join("")}</div>`;
    }
    
    // Setze innerHTML ZUERST
    shiftsContainer.innerHTML = infoHTML;
    
    // WICHTIG: Setze die Farben NACH dem innerHTML, damit sie nicht überschrieben werden
    // Erneut das Element holen, falls es durch innerHTML geändert wurde
    const dayElementAfter = shiftsContainer.closest(".calendar-day");
    if (dayElementAfter && dayElementAfter === dayElement) {
      // Setze die Farben nochmal, nachdem innerHTML gesetzt wurde
      if (openShifts > 0) {
        dayElementAfter.classList.add("day-open-shifts");
        dayElementAfter.style.backgroundColor = "#ffe0e0";
        dayElementAfter.style.background = "#ffe0e0";
        dayElementAfter.style.borderColor = "#b91c1c";
      } else if (hadAnyShifts) {
        dayElementAfter.classList.add("day-all-manned");
        dayElementAfter.style.backgroundColor = "#a8f3a8";
        dayElementAfter.style.background = "#a8f3a8";
        dayElementAfter.style.borderColor = "#a8f3a8";
      }
      
      // Finale Bestätigung
      const computedBg = window.getComputedStyle(dayElementAfter).backgroundColor;
      console.log(`✅ Tag ${dayIdDisplay} - Klassen: "${dayElementAfter.className}"`);
      console.log(`✅ Tag ${dayIdDisplay} - Computed backgroundColor: ${computedBg}`);
      console.log(`✅ Tag ${dayIdDisplay} - Inline backgroundColor: ${dayElementAfter.style.backgroundColor}`);
    }
  } catch (e) {
    console.error(`❌ Fehler beim Laden der Schichten für ${dayIdDisplay}:`, e);
    console.error(`❌ Fehler-Stack:`, e.stack);
  }
}

// ---------------------------------------------------------
// Tages-Popup
// ---------------------------------------------------------

window.showCalendarDayDetails = async function (dayId) {
  if (!dayPopupOverlay || !dayPopupForm || !dayOverviewContent || !dayBereitschaftenTop || !dayPopupTitle)
    return;

  const wasAlreadyOpen = dayPopupForm.style.display === "block";

  currentDayId = dayId;
  dayPopupTitle.textContent = `Tag-Übersicht: ${dayId}`;

  // Popup sofort öffnen (wenn es noch nicht offen ist), damit kein "Springen" entsteht
  if (!wasAlreadyOpen) {
    dayPopupOverlay.style.display = "block";
    dayPopupForm.style.display = "block";
  }

  // Loading-State nur kurz anzeigen, wenn Popup bereits offen war
  if (wasAlreadyOpen) {
    dayOverviewContent.style.opacity = "0.5";
  }
  dayOverviewContent.innerHTML = '<div class="info-card">Lade Gesamtübersicht...</div>';
  dayBereitschaftenTop.innerHTML = "";

  try {
    // Übersicht aller Standorte rendern
    let html = `
      <div class="calendar-header-controls">
        <h3>Gesamtübersicht: ${dayId}</h3>
        <div></div>
        <div></div>
      </div>
      <div class="calendar-day-overview">
    `;

    // Verwende getStandorteForDay um gelöschte Standorte für vergangene Tage zu inkludieren
    let standorteForDay = [];
    try {
      standorteForDay = getStandorteForDay(dayId);
      // Zusätzliche Duplikatsprüfung vor dem Rendern
      standorteForDay = removeDuplicateStandorte(standorteForDay);
      console.log(`📊 Standorte für Tag ${dayId}:`, standorteForDay.map(s => `${s.name} (${s.id})`).join(", "));
    } catch (e) {
      console.error("❌ Fehler in getStandorteForDay:", e);
      standorteForDay = removeDuplicateStandorte(allStandorte || []);
    }
    
    if (!standorteForDay || standorteForDay.length === 0) {
      html += '<div class="info-card">Keine Standorte konfiguriert.</div>';
    } else {
      
      // Verwende Set, um sicherzustellen, dass jeder Standort nur einmal gerendert wird
      const renderedStandortIds = new Set();
      for (const standort of standorteForDay) {
        if (!standort || !standort.id) continue; // Sicherheitscheck
        
        // Prüfe, ob dieser Standort bereits gerendert wurde
        if (renderedStandortIds.has(standort.id)) {
          console.warn(`⚠️ Überspringe bereits gerenderten Standort: ${standort.name} (${standort.id})`);
          continue;
        }
        renderedStandortIds.add(standort.id);
        
        try {
          // Prüfe ob Standort gelöscht wurde (deleted: true) ODER inaktiv ist (active: false)
          const isDeleted = standort.deleted === true || standort.active === false;
          
          // Parse Tag-Datum (unterstützt verschiedene Formate)
          const dayDate = parseDayId(dayId);
          if (!dayDate || isNaN(dayDate.getTime())) {
            console.error(`❌ Ungültiges Datum: ${dayId}`);
            continue;
          }
          
          const today = new Date();
          today.setHours(0, 0, 0, 0);
          dayDate.setHours(0, 0, 0, 0);
          const isPastDay = dayDate < today;
          
          // Für gelöschte Standorte ODER vergangene Tage: Kein "+ Schicht" Button
          const showAddButton = !isDeleted && !isPastDay;
          
          html += `
            <div class="overview-standort-card">
              <div class="standort-header-row">
                <h4 class="standort-header">${standort.name || standort.id}</h4>
                ${showAddButton ? `<button class="btn-small" onclick="createShiftForDay('${standort.id}','${dayId}')">+ Schicht</button>` : ""}
              </div>
              <div class="overview-shifts-list" id="overview-${standort.id}-${dayId}"></div>
            </div>
          `;
        } catch (e) {
          console.error(`❌ Fehler beim Rendern des Standorts ${standort.id}:`, e);
          // Weiter mit nächstem Standort
        }
      }
    }

    html += "</div>";
    dayOverviewContent.innerHTML = html;
    dayOverviewContent.style.opacity = "1"; // Opacity zurücksetzen

    // Alle Standorte parallel laden (nicht sequenziell), für schnelleres Rendering
    // Verwende die bereits berechnete standorteForDay Variable
    const loadPromises = [];
    for (const standort of standorteForDay) {
      const container = document.getElementById(`overview-${standort.id}-${dayId}`);
      if (container) {
        loadPromises.push(renderShiftsForStandortAndDay(standort.id, dayId, container));
      }
    }

    // Bereitschaften und Schichten parallel laden
    await Promise.all([...loadPromises, renderBereitschaftenTop(dayId)]);

    // Popup sicherstellen, dass es sichtbar ist
    dayPopupOverlay.style.display = "block";
    dayPopupForm.style.display = "block";
  } catch (e) {
    console.error("Fehler beim Laden der Tagesübersicht:", e);
    dayOverviewContent.innerHTML =
      '<div class="info-card" style="color: red;">Fehler beim Laden der Tagesübersicht.</div>';
    dayOverviewContent.style.opacity = "1";
  }
};

window.closeDayPopup = function () {
  // Speichere currentDayId, bevor wir es zurücksetzen
  const dayIdToUpdate = currentDayId;
  
  if (dayPopupOverlay) dayPopupOverlay.style.display = "none";
  if (dayPopupForm) dayPopupForm.style.display = "none";
  
  // currentDayId zurücksetzen, damit Live-Updates das Popup nicht wieder öffnen
  currentDayId = null;

  // Nach Schließen nur den betroffenen Tag im Kalender aktualisieren,
  // statt den kompletten Monat neu zu laden → deutlich schneller.
  if (dayIdToUpdate) {
    loadCalendarDayShifts(dayIdToUpdate).catch((e) =>
      console.error(
        "Fehler beim Aktualisieren des Kalendertages nach Popup-Schließen:",
        e
      )
    );
  }
};

async function renderShiftsForStandortAndDay(standortId, dayId, container) {
  container.innerHTML = "<div class='info-text'>Lade Schichten...</div>";
  try {
    // Versuche Schichten direkt aus der Collection zu laden, auch wenn das Tage-Dokument nicht existiert
    // (für historische Daten, wenn Standort gelöscht wurde)
    const shiftsCol = getShiftsCollection(standortId, dayId);
    const snap = await getDocs(shiftsCol);
    
    if (snap.empty) {
      container.innerHTML = "<div class='info-text'>Keine Schichten an diesem Tag.</div>";
      return;
    }
    
    // Prüfe ob Tage-Dokument existiert (optional, nur für Info)
    try {
      const dayRef = getDayDocRef(standortId, dayId);
      const daySnap = await getDoc(dayRef);
      if (!daySnap.exists()) {
        console.log(`⚠️ Tage-Dokument existiert nicht für ${standortId}/${dayId}, aber Schichten gefunden (historische Daten)`);
      }
    } catch (e) {
      // Ignoriere Fehler beim Prüfen des Tage-Dokuments
    }

    const rows = [];
    snap.forEach((docSnap) => {
      rows.push({ id: docSnap.id, data: docSnap.data() });
    });

    rows.sort((a, b) => (a.id || "").localeCompare(b.id || ""));

    container.innerHTML = "";
    rows.forEach((row) => {
      const el = renderShiftRowElement(dayId, standortId, row.id, row.data);
      container.appendChild(el);
    });
  } catch (e) {
    console.error("Fehler beim Laden der Schichten für Standort", standortId, dayId, e);
    container.innerHTML =
      "<div class='info-text' style='color:red;'>Fehler beim Laden der Schichten.</div>";
  }
}

function renderShiftRowElement(dayId, standortId, shiftId, data) {
  const row = document.createElement("div");
  const isSlot1Manned = !!data.personal1;
  const isSlot2Manned = !!data.personal2;
  let mannedClass = "unmanned";
  if (isSlot1Manned && isSlot2Manned) mannedClass = "fully-manned";
  else if (isSlot1Manned || isSlot2Manned) mannedClass = "partially-manned";

  row.className = `shift-row ${mannedClass}`;

  // Nur Schichten anzeigen, die für diesen Standort in der Stammdaten-Tabelle hinterlegt sind
  // String-Vergleich für standortId, um Typ-Probleme zu vermeiden
  // Prüfe auch, ob standortId als Referenz-Objekt gespeichert ist
  
  // Debug: Zeige alle Standorte und ihre IDs
  const standortInfo = allStandorte.find(s => s.id === standortId);
  console.log(`🔍 Standort-Info für ${standortId}:`, standortInfo ? { name: standortInfo.name, id: standortInfo.id } : 'NICHT GEFUNDEN');
  
  // Debug: Zeige ALLE Schichten mit ihren standortId-Werten (für Vergleich)
  console.log(`🔍 ALLE Schichten in Datenbank:`, allSchichten.map(s => ({ 
    name: s.name, 
    standortId: s.standortId, 
    standortIdType: typeof s.standortId,
    standortIdString: String(s.standortId),
    id: s.id,
    active: s.active 
  })));
  
  // Debug: Vergleiche mit KTW-Wache (funktioniert)
  const ktwWacheSchichten = allSchichten.filter(s => {
    const sId = String(s.standortId || '').trim().toLowerCase();
    return sId.includes('ktw') || sId === 'ktw-wache';
  });
  console.log(`🔍 KTW-Wache Schichten (funktioniert):`, ktwWacheSchichten.map(s => ({ name: s.name, standortId: s.standortId, id: s.id })));
  
  // Schritt-für-Schritt-Filterung mit detailliertem Logging
  const standortIdStr = String(standortId).trim().toLowerCase();
  console.log(`🔍 Filtere Schichten für Standort-ID: "${standortIdStr}"`);
  
  const shiftDefsForStandort = (allSchichten || []).filter(
    (s) => {
      const isActive = s.active !== false;
      if (!isActive) {
        console.log(`  ✗ Schicht "${s.name}" ist inaktiv`);
        return false;
      }
      
      // Prüfe verschiedene Formate der standortId
      const sStandortId = s.standortId;
      let matchesStandort = false;
      let sStandortIdStr = '';
      
      if (sStandortId === undefined || sStandortId === null) {
        console.log(`  ✗ Schicht "${s.name}" hat keine standortId`);
        matchesStandort = false;
      } else if (typeof sStandortId === 'object' && sStandortId.id) {
        // Falls standortId ein Referenz-Objekt ist
        sStandortIdStr = String(sStandortId.id).trim().toLowerCase();
        matchesStandort = sStandortIdStr === standortIdStr;
        if (matchesStandort) {
          console.log(`  ✓ Schicht "${s.name}" (ID: ${s.id}) passt - Objekt-ID: "${sStandortIdStr}" === "${standortIdStr}"`);
        } else {
          console.log(`  ✗ Schicht "${s.name}" passt nicht - Objekt-ID: "${sStandortIdStr}" !== "${standortIdStr}"`);
        }
      } else {
        // Normale String/ID-Vergleich (case-insensitive, mit trim für Leerzeichen)
        sStandortIdStr = String(sStandortId).trim().toLowerCase();
        matchesStandort = sStandortIdStr === standortIdStr;
        if (matchesStandort) {
          console.log(`  ✓ Schicht "${s.name}" (ID: ${s.id}) passt - String: "${sStandortIdStr}" === "${standortIdStr}"`);
        } else {
          console.log(`  ✗ Schicht "${s.name}" passt nicht - String: "${sStandortIdStr}" !== "${standortIdStr}"`);
        }
      }
      
      return matchesStandort;
    }
  );
  
  console.log(`📊 Ergebnis der Filterung: ${shiftDefsForStandort.length} Schicht(en) gefunden`);
  const currentShiftName = getShiftDisplayName(standortId, shiftId, data);

  // Debug: Log für alle gefundenen Schichten
  console.log(`🔍 Schichten für Standort ${standortId}:`, shiftDefsForStandort.map(s => ({ id: s.id, name: s.name, standortId: s.standortId })));
  console.log(`📊 Gesamtanzahl gefundener Schichten: ${shiftDefsForStandort.length}`);
  
  // Debug: Zeige alle Schichten mit dieser standortId (auch inaktiv)
  const allSchichtenForStandort = (allSchichten || []).filter(s => {
    const sStandortId = s.standortId;
    const standortIdStr = String(standortId).trim().toLowerCase();
    if (sStandortId === undefined || sStandortId === null) return false;
    const sStandortIdStr = typeof sStandortId === 'object' && sStandortId.id 
      ? String(sStandortId.id).trim().toLowerCase()
      : String(sStandortId).trim().toLowerCase();
    return sStandortIdStr === standortIdStr;
  });
  console.log(`🔍 ALLE Schichten für Standort ${standortId} (inkl. inaktive):`, allSchichtenForStandort.map(s => ({ id: s.id, name: s.name, active: s.active, standortId: s.standortId })));
  
  // WICHTIG: Wenn keine oder nur eine Schicht gefunden wurde, versuche Fallback-Filterung
  if (shiftDefsForStandort.length <= 1) {
    console.warn(`⚠️ WARNUNG: Nur ${shiftDefsForStandort.length} Schicht(en) für Standort ${standortId} gefunden!`);
    
    // Fallback: Versuche Schichten zu finden, die zum Standort-Namen passen
    const standortInfo = allStandorte.find(s => s.id === standortId);
    if (standortInfo && standortInfo.name) {
      console.log(`🔍 Versuche Fallback-Filterung für Standort-Name: "${standortInfo.name}"`);
      
      // Erstelle verschiedene Varianten des Standort-Namens für die Suche
      const standortNameLower = standortInfo.name.trim().toLowerCase();
      const standortNameVariants = [
        standortNameLower,
        standortNameLower.replace(/\s+/g, '-'),  // "RW Holzwickede" -> "rw-holzwickede"
        standortNameLower.replace(/\s+/g, ''),   // "RW Holzwickede" -> "rwholzwickede"
        standortNameLower.replace(/[^a-z0-9]/g, ''), // Nur Buchstaben/Zahlen
      ];
      
      const fallbackSchichten = (allSchichten || []).filter(
        (s) => {
          const isActive = s.active !== false;
          if (!isActive) return false;
          
          // Prüfe, ob die Schicht bereits gefunden wurde
          if (shiftDefsForStandort.find(existing => existing.id === s.id)) {
            return false; // Bereits gefunden, nicht nochmal hinzufügen
          }
          
          // Prüfe verschiedene Möglichkeiten
          const sStandortId = String(s.standortId || '').trim().toLowerCase();
          const standortIdLower = String(standortId).trim().toLowerCase();
          
          // Prüfe exakte Übereinstimmung (case-insensitive)
          if (sStandortId === standortIdLower) {
            console.log(`  ✓ Fallback (exakt): Schicht "${s.name}" passt (standortId: ${s.standortId})`);
            return true;
          }
          
          // Prüfe, ob eine der Varianten des Standort-Namens in der standortId enthalten ist
          const matchesByName = standortNameVariants.some(variant => 
            sStandortId.includes(variant) || variant.includes(sStandortId)
          );
          
          if (matchesByName) {
            console.log(`  ✓ Fallback (Name): Schicht "${s.name}" passt (standortId: ${s.standortId}, Name: ${standortInfo.name})`);
            return true;
          }
          
          return false;
        }
      );
      
      if (fallbackSchichten.length > 0) {
        console.log(`✅ Fallback gefunden: ${fallbackSchichten.length} zusätzliche Schichten`);
        // Füge die gefundenen Schichten hinzu
        fallbackSchichten.forEach(fallbackSchicht => {
          shiftDefsForStandort.push(fallbackSchicht);
          console.log(`  ➕ Fallback-Schicht hinzugefügt: ${fallbackSchicht.name} (standortId: ${fallbackSchicht.standortId})`);
        });
      }
    }
    
    console.log(`🔍 Alle Schichten mit ähnlicher standortId:`, allSchichten.filter(s => {
      const sId = String(s.standortId || '').trim();
      const targetId = String(standortId).trim();
      return sId.includes(targetId) || targetId.includes(sId) || sId.toLowerCase() === targetId.toLowerCase();
    }).map(s => ({ name: s.name, standortId: s.standortId, id: s.id })));
  }

  const selectEl = document.createElement("select");
  selectEl.className = "shift-select";
  
  // Sicherstellen, dass alle Schichten hinzugefügt werden (auch bei gleichen Namen)
  if (shiftDefsForStandort.length === 0) {
    console.error(`❌ FEHLER: Keine Schichten für Standort ${standortId} gefunden!`);
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "Keine Schichten verfügbar";
    opt.disabled = true;
    selectEl.appendChild(opt);
  } else {
    // Sortiere Schichten nach Name für konsistente Anzeige
    shiftDefsForStandort.sort((a, b) => {
      if (a.name !== b.name) {
        return (a.name || '').localeCompare(b.name || '');
      }
      return (a.id || '').localeCompare(b.id || '');
    });
    
    shiftDefsForStandort.forEach((def, index) => {
      const opt = document.createElement("option");
      // Verwende die ID als Wert, um Duplikate zu unterscheiden
      opt.value = def.id || `${def.name}_${index}`;
      // Wenn mehrere Schichten denselben Namen haben, füge die ID hinzu
      const sameNameCount = shiftDefsForStandort.filter(s => s.name === def.name).length;
      if (sameNameCount > 1) {
        opt.textContent = `${def.name} (${def.id})`;
      } else {
        opt.textContent = def.name;
      }
      opt.dataset.shiftDefId = def.id; // Zusätzliche Info für Debugging
      opt.dataset.shiftName = def.name; // Name für späteren Zugriff
      if (def.name === currentShiftName) opt.selected = true;
      selectEl.appendChild(opt);
      console.log(`  ➕ Option hinzugefügt: ${opt.textContent} (ID: ${def.id}, Wert: ${opt.value})`);
    });
  }
  
  // Debug: Log für alle hinzugefügten Optionen
  console.log(`✅ Dropdown-Optionen erstellt (${selectEl.options.length} Optionen):`, Array.from(selectEl.options).map((o, i) => `${i}: ${o.textContent} (${o.value})`));
  selectEl.addEventListener("change", async (e) => {
    const selectedOption = e.target.options[e.target.selectedIndex];
    const newName = selectedOption.textContent; // Verwende textContent statt value
    const selectedDefId = selectedOption.value;
    
    console.log(`🔄 Schicht geändert: ${currentShiftName} → ${newName} (ID: ${selectedDefId})`);
    
    if (!newName || newName === currentShiftName) return;

    // Nur den Schichtnamen im Tagesdokument aktualisieren, nicht mehr das Dokument umbenennen
    try {
      const ref = doc(getShiftsCollection(standortId, dayId), shiftId);
      await setDoc(ref, { shiftName: newName }, { merge: true });
      await showCalendarDayDetails(dayId);
    } catch (err) {
      console.error("Fehler beim Umbenennen der Schicht:", err);
      alert("Fehler beim Umbenennen der Schicht: " + err.message);
    }
  });

  const personnelContainer = document.createElement("div");
  personnelContainer.className = "personnel-slot";
  personnelContainer.innerHTML =
    renderPersonnelSlotHTML(dayId, standortId, shiftId, 1, data.personal1) +
    renderPersonnelSlotHTML(dayId, standortId, shiftId, 2, data.personal2);

  const deleteBtn = document.createElement("button");
  deleteBtn.className = "control-btn delete-shift-btn";
  deleteBtn.title = "Schicht löschen";
  // Shift-Delete-Button hat weißen Hintergrund → schwarzes Icon
  deleteBtn.innerHTML = getTrashIconSVG("#ffffff");
  deleteBtn.addEventListener("click", async () => {
    if (!confirm("Schicht wirklich löschen?")) return;
    try {
      const ref = doc(getShiftsCollection(standortId, dayId), shiftId);
      await deleteDoc(ref);
      await showCalendarDayDetails(dayId);
    } catch (e) {
      console.error("Fehler beim Löschen der Schicht:", e);
      alert("Fehler beim Löschen der Schicht: " + e.message);
    }
  });

  row.appendChild(selectEl);
  row.appendChild(personnelContainer);
  row.appendChild(deleteBtn);

  return row;
}

// Neue Schicht für einen Tag/Standort anlegen
window.createShiftForDay = async function (standortId, dayId) {
  try {
    if (!standortId || !dayId) return;

    // Sicherstellen, dass das Tages-Dokument existiert
    const dayRef = getDayDocRef(standortId, dayId);
    const daySnap = await getDoc(dayRef);
    if (!daySnap.exists()) {
      await setDoc(dayRef, { datum: dayId }, { merge: true });
    }

    const shiftsCol = getShiftsCollection(standortId, dayId);

    // Standard-Schichtnamen für diesen Standort wählen (erste hinterlegte Schicht)
    const defsForStandort = (allSchichten || []).filter(
      (s) => {
        const isActive = s.active !== false;
        const sStandortId = s.standortId;
        const standortIdStr = String(standortId);
        let matchesStandort = false;
        
        if (sStandortId === undefined || sStandortId === null) {
          matchesStandort = false;
        } else if (typeof sStandortId === 'object' && sStandortId.id) {
          matchesStandort = String(sStandortId.id) === standortIdStr;
        } else {
          matchesStandort = String(sStandortId) === standortIdStr;
        }
        
        return isActive && matchesStandort;
      }
    );
    const defaultShiftName = defsForStandort.length > 0 ? defsForStandort[0].name : "";

    // Neues Schicht-Dokument mit initialem Namen anlegen
    await addDoc(shiftsCol, {
      shiftName: defaultShiftName,
    });

    await showCalendarDayDetails(dayId);
  } catch (e) {
    console.error("Fehler beim Anlegen einer neuen Schicht:", e);
    alert("Fehler beim Anlegen einer neuen Schicht: " + e.message);
  }
};

function renderPersonnelSlotHTML(dayId, standortId, shiftId, slotIndex, personalData) {
  if (!personalData) {
    return `
      <div class="personnel-label unassigned" 
           onclick="openPersonnelPopup('${dayId}','${standortId}','${shiftId}',${slotIndex})">
        Personal ${slotIndex} eintragen
      </div>
    `;
  }

  const quals = personalData.qualifikationen && personalData.qualifikationen.length
    ? ` (${personalData.qualifikationen.join("/")})`
    : "";
  const bgColor = personalData.farbe || "#ffffff";

  return `
    <div class="personnel-label assigned"
         style="background-color: ${bgColor};"
         onclick="handlePersonnelSlotClick(event,'${dayId}','${standortId}','${shiftId}',${slotIndex},'${personalData.mitarbeiterId || ""}')"
         oncontextmenu="openMitarbeiterDatenblattFromSlot(event,'${dayId}','${standortId}','${shiftId}',${slotIndex},'${personalData.mitarbeiterId || ""}')"
         ontouchstart="personnelSlotTouchStart(event,'${dayId}','${standortId}','${shiftId}',${slotIndex},'${personalData.mitarbeiterId || ""}')"
         ontouchend="personnelSlotTouchEnd(event)"
         ontouchcancel="personnelSlotTouchEnd(event)"
         ontouchmove="personnelSlotTouchEnd(event)">
      <span class="personnel-name">
        ${personalData.name || "Unbekannt"}${quals}
      </span>
      <button class="personnel-delete-btn"
              title="Person aus Schicht entfernen"
              onclick="clearPersonnelSlot(event,'${dayId}','${standortId}','${shiftId}',${slotIndex})">${getTrashIconSVG(bgColor)}</button>
    </div>
  `;
}

// Handler für normalen Klick auf besetzten Slot (öffnet Mitarbeiterdatenblatt)
window.handlePersonnelSlotClick = function (event, dayId, standortId, shiftId, slotIndex, mitarbeiterId) {
  try {
    // Nicht öffnen, wenn auf den Lösch-Button geklickt wurde
    if (event.target.closest('.personnel-delete-btn')) {
      return;
    }
    // Mitarbeiterdatenblatt öffnen
    openMitarbeiterDatenblattFromSlot(event, dayId, standortId, shiftId, slotIndex, mitarbeiterId);
  } catch (e) {
    console.error("Fehler bei handlePersonnelSlotClick:", e);
  }
};

// Personal-Slot in einer Schicht löschen
window.clearPersonnelSlot = async function (event, dayId, standortId, shiftId, slotIndex) {
  try {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    if (!dayId || !standortId || !shiftId || !slotIndex) return;

    const shiftsCol = getShiftsCollection(standortId, dayId);
    const ref = doc(shiftsCol, shiftId);
    const field = slotIndex === 1 ? "personal1" : "personal2";

    await setDoc(ref, { [field]: null }, { merge: true });
    await showCalendarDayDetails(dayId);
  } catch (e) {
    console.error("Fehler beim Löschen des Personal-Slots:", e);
    alert("Fehler beim Löschen des Personal-Slots: " + e.message);
  }
};

// Rechtsklick: Mitarbeiter-Datenblatt öffnen (mit Farbauswahl für diesen Slot), Copy/Browser-Menü unterdrücken
window.openMitarbeiterDatenblattFromSlot = async function (
  event,
  dayId,
  standortId,
  shiftId,
  slotIndex,
  mitarbeiterId
) {
  console.log("🔍 openMitarbeiterDatenblattFromSlot aufgerufen:", {
    dayId,
    standortId,
    shiftId,
    slotIndex,
    mitarbeiterId,
  });

  if (event) {
    event.preventDefault();
    event.stopPropagation();
  }

  // Slot-Daten aus Firestore lesen
  try {
    const shiftsCol = getShiftsCollection(standortId, dayId);
    const ref = doc(shiftsCol, shiftId);
    const snap = await getDoc(ref);
    if (!snap.exists()) {
      console.error("❌ Schicht-Dokument existiert nicht:", shiftId);
      return;
    }

    const data = snap.data() || {};
    const field = slotIndex === 1 ? "personal1" : "personal2";
    const slotData = data[field] || {};

    // Mitarbeiter-ID aus Slot-Daten nehmen, falls nicht übergeben
    const actualMitarbeiterId = mitarbeiterId || slotData.mitarbeiterId || "";
    if (!actualMitarbeiterId) {
      alert("Fehler: Keine Mitarbeiter-ID gefunden.");
      console.error("❌ Keine Mitarbeiter-ID gefunden im Slot:", slotData);
      return;
    }

    const currentColor = slotData.farbe || "#ffffff";

    const overlay = document.getElementById("mitarbeiterDatenblattOverlay");
    const form = document.getElementById("mitarbeiterDatenblattForm");
    const content = document.getElementById("mitarbeiterDatenblattContent");

    if (!overlay) {
      console.error("❌ mitarbeiterDatenblattOverlay nicht gefunden");
      return;
    }
    if (!form) {
      console.error("❌ mitarbeiterDatenblattForm nicht gefunden");
      return;
    }
    if (!content) {
      console.error("❌ mitarbeiterDatenblattContent nicht gefunden");
      return;
    }

    const m = allMitarbeiter.find((mm) => mm.id === actualMitarbeiterId);
    if (!m) {
      alert("Mitarbeiter nicht gefunden.");
      console.error("❌ Mitarbeiter nicht gefunden:", actualMitarbeiterId);
      return;
    }

    console.log("✅ Öffne Mitarbeiter-Datenblatt für:", m.vorname, m.nachname);

    const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(" / ") : "";
    const fuehrerschein = m.fuehrerschein || "-";
    const telefon = m.telefonnummer || "-";
    // Telefonnummer als tel: Link formatieren (Leerzeichen entfernen für tel: Schema)
    const telLink = telefon && telefon !== "-" ? telefon.replace(/\s+/g, "") : "";
    const telefonDisplay = telLink
      ? `<a href="tel:${telLink}" style="color: var(--primary-color); text-decoration: underline;">${telefon}</a>`
      : "-";

    // Form-Kontext für Speichern speichern
    form.dataset.dayId = dayId;
    form.dataset.standortId = standortId;
    form.dataset.shiftId = shiftId;
    form.dataset.slotIndex = String(slotIndex);

    content.innerHTML = `
      <div class="mitarbeiter-datenblatt">
        <h3>${m.vorname || ""} ${m.nachname || ""}</h3>
        <p><strong>Qualifikationen:</strong> ${qualis || "-"}</p>
        <p><strong>Führerschein:</strong> ${fuehrerschein}</p>
        <p><strong>Telefon:</strong> ${telefonDisplay}</p>
        <hr style="margin: 20px 0; border: none; border-top: 1px solid var(--border-color);">
        <h4>Hintergrundfarbe für diesen Slot ändern</h4>
        <label for="slotColorSelect">Hintergrundfarbe:</label>
        <select id="slotColorSelect" style="width: 100%; padding: 8px; margin-bottom: 15px; border-radius: 6px; border: 1px solid var(--border-color);">
          <option value="#ffffff" ${currentColor === "#ffffff" ? "selected" : ""}>Weiß (Standard)</option>
          <option value="#ffef94" ${currentColor === "#ffef94" ? "selected" : ""}>Gelb (Bereitschaft / Hervorheben)</option>
        </select>
        <div class="form-actions">
          <button id="saveSlotColorBtn" style="padding: 10px 15px; background-color: var(--primary-color); color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;">Farbe speichern</button>
          <button onclick="closeMitarbeiterDatenblatt()" class="cancel-btn">Schließen</button>
        </div>
      </div>
    `;

    // Speichern-Button Handler
    const saveBtn = document.getElementById("saveSlotColorBtn");
    if (saveBtn) {
      saveBtn.addEventListener("click", async () => {
        const colorSelect = document.getElementById("slotColorSelect");
        if (!colorSelect) return;

        const newColor = colorSelect.value || "#ffffff";
        try {
          const updatedSlot = {
            ...slotData,
            farbe: newColor,
          };
          await setDoc(ref, { [field]: updatedSlot }, { merge: true });
          closeMitarbeiterDatenblatt();
          await showCalendarDayDetails(dayId);
        } catch (err) {
          console.error("Fehler beim Aktualisieren der Slot-Farbe:", err);
          alert("Fehler beim Aktualisieren der Slot-Farbe. Details siehe Konsole.");
        }
      });
    }

    overlay.style.display = "block";
    form.style.display = "block";
    console.log("✅ Popup sollte jetzt sichtbar sein");
  } catch (e) {
    console.error("❌ Fehler beim Öffnen des Mitarbeiter-Datenblatts vom Slot:", e);
    alert("Fehler beim Laden der Slot-Daten: " + e.message);
  }
};

// Long-Press auf Touch-Geräten: Mitarbeiter-Datenblatt öffnen, Copy unterdrücken
let personnelLongPressTimer = null;

window.personnelSlotTouchStart = function (event, dayId, standortId, shiftId, slotIndex, mitarbeiterId) {
  try {
    if (event) {
      // Nicht preventDefault, damit normaler Click auch funktioniert
      // Nur Copy-Menü unterdrücken
      if (event.target) {
        event.target.style.webkitTouchCallout = "none";
        event.target.style.webkitUserSelect = "none";
        event.target.style.userSelect = "none";
      }
    }
    // Long-Press Timer für Long-Press (nur wenn lange gedrückt wird)
    personnelLongPressTimer = window.setTimeout(() => {
      openMitarbeiterDatenblattFromSlot(event, dayId, standortId, shiftId, slotIndex, mitarbeiterId);
    }, 600);
  } catch (e) {
    console.error("Fehler bei personnelSlotTouchStart:", e);
  }
};

window.personnelSlotTouchEnd = function (event) {
  try {
    // Timer löschen, damit bei normalem Tap der Click-Event ausgelöst wird
    if (personnelLongPressTimer) {
      clearTimeout(personnelLongPressTimer);
      personnelLongPressTimer = null;
    }
    // Nicht preventDefault, damit normaler Click funktioniert
  } catch (e) {
    console.error("Fehler bei personnelSlotTouchEnd:", e);
  }
};

// Hintergrundfarbe eines belegten Personal-Slots ändern (Rechtsklick)
window.openPersonnelColorDialog = async function (
  event,
  dayId,
  standortId,
  shiftId,
  slotIndex,
  mitarbeiterId
) {
  try {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
    }
    if (!dayId || !standortId || !shiftId || !slotIndex) return;

    // Aktuellen Slot auslesen
    const shiftsCol = getShiftsCollection(standortId, dayId);
    const ref = doc(shiftsCol, shiftId);
    const snap = await getDoc(ref);
    if (!snap.exists()) return;

    const data = snap.data() || {};
    const field = slotIndex === 1 ? "personal1" : "personal2";
    const slotData = data[field];
    if (!slotData) return;

    const currentColor = slotData.farbe || "#ffffff";

    // Vorherigen Dialog entfernen
    const existing = document.getElementById("personnelColorDialog");
    if (existing) existing.remove();

    const dialog = document.createElement("div");
    dialog.id = "personnelColorDialog";
    dialog.className = "assign-bereitschaft-dialog";

    const title = document.createElement("h3");
    title.textContent = "Hintergrundfarbe ändern";

    const info = document.createElement("p");
    info.textContent = "Bitte eine Farbe für diesen Mitarbeiter wählen:";

    const select = document.createElement("select");
    const options = [
      { value: "#ffffff", label: "Weiß (Standard)" },
      { value: "#ffef94", label: "Gelb (Bereitschaft / Hervorheben)" },
    ];
    options.forEach((optDef) => {
      const opt = document.createElement("option");
      opt.value = optDef.value;
      opt.textContent = optDef.label;
      if (optDef.value === currentColor) opt.selected = true;
      select.appendChild(opt);
    });

    const actions = document.createElement("div");
    actions.className = "form-actions";

    const confirmBtn = document.createElement("button");
    confirmBtn.textContent = "Speichern";

    const cancelBtn = document.createElement("button");
    cancelBtn.textContent = "Abbrechen";
    cancelBtn.className = "cancel-btn";

    actions.appendChild(confirmBtn);
    actions.appendChild(cancelBtn);

    dialog.appendChild(title);
    dialog.appendChild(info);
    dialog.appendChild(select);
    dialog.appendChild(actions);

    if (dayPopupForm) {
      dayPopupForm.appendChild(dialog);
    } else {
      document.body.appendChild(dialog);
    }

    cancelBtn.addEventListener("click", () => {
      dialog.remove();
    });

    confirmBtn.addEventListener("click", async () => {
      const newColor = select.value || "#ffffff";
      try {
        const updatedSlot = {
          ...slotData,
          farbe: newColor,
        };
        await setDoc(ref, { [field]: updatedSlot }, { merge: true });
        dialog.remove();
        await showCalendarDayDetails(dayId);
      } catch (err) {
        console.error("Fehler beim Aktualisieren der Slot-Farbe:", err);
        alert("Fehler beim Aktualisieren der Slot-Farbe. Details siehe Konsole.");
      }
    });
  } catch (e) {
    console.error("Fehler beim Öffnen des Farb-Dialogs:", e);
  }
};

// ---------------------------------------------------------
// Doppelbelegungs-Prüfung und Warnung
// ---------------------------------------------------------

// Prüft, ob ein Mitarbeiter bereits an einem Tag eingeteilt ist
async function checkMitarbeiterAlreadyAssigned(dayId, mitarbeiterId, excludeStandortId = null, excludeShiftId = null, excludeSlotIndex = null) {
  try {
    const existingAssignments = [];

    for (const standort of allStandorte) {
      if (standort.active === false) continue;

      const dayRef = getDayDocRef(standort.id, dayId);
      const daySnap = await getDoc(dayRef);
      if (!daySnap.exists()) continue;

      const shiftsCol = getShiftsCollection(standort.id, dayId);
      const snap = await getDocs(shiftsCol);
      
      snap.forEach((docSnap) => {
        const data = docSnap.data() || {};
        
        // Prüfe personal1
        if (data.personal1 && data.personal1.mitarbeiterId === mitarbeiterId) {
          // Ignoriere, wenn es der gleiche Slot ist, der gerade bearbeitet wird
          if (!(standort.id === excludeStandortId && docSnap.id === excludeShiftId && excludeSlotIndex === 1)) {
            existingAssignments.push({
              standortName: standort.name,
              shiftName: getShiftDisplayName(standort.id, docSnap.id, data),
              slotIndex: 1,
            });
          }
        }
        
        // Prüfe personal2
        if (data.personal2 && data.personal2.mitarbeiterId === mitarbeiterId) {
          // Ignoriere, wenn es der gleiche Slot ist, der gerade bearbeitet wird
          if (!(standort.id === excludeStandortId && docSnap.id === excludeShiftId && excludeSlotIndex === 2)) {
            existingAssignments.push({
              standortName: standort.name,
              shiftName: getShiftDisplayName(standort.id, docSnap.id, data),
              slotIndex: 2,
            });
          }
        }
      });
    }

    return existingAssignments;
  } catch (e) {
    console.error("Fehler beim Prüfen auf Doppelbelegung:", e);
    return [];
  }
}

// Zeigt eine Warnung an, wenn ein Mitarbeiter bereits eingeteilt ist
// Gibt true zurück, wenn der Benutzer trotzdem einteilen möchte, false bei Abbruch
async function showDoubleAssignmentWarning(mitarbeiterName, existingAssignments) {
  return new Promise((resolve) => {
    // Vorherigen Dialog und Overlay entfernen
    const existing = document.getElementById("doubleAssignmentWarning");
    if (existing) existing.remove();
    const existingOverlay = document.getElementById("doubleAssignmentWarningOverlay");
    if (existingOverlay) existingOverlay.remove();

    const dialog = document.createElement("div");
    dialog.id = "doubleAssignmentWarning";
    dialog.className = "assign-bereitschaft-dialog";
    dialog.style.zIndex = "10000";
    dialog.style.position = "fixed";
    dialog.style.top = "50%";
    dialog.style.left = "50%";
    dialog.style.transform = "translate(-50%, -50%)";
    dialog.style.background = "white";
    dialog.style.padding = "30px";
    dialog.style.borderRadius = "12px";
    dialog.style.boxShadow = "0 4px 20px rgba(0,0,0,0.3)";
    dialog.style.maxWidth = "500px";
    dialog.style.width = "90%";

    const title = document.createElement("h3");
    title.textContent = "⚠️ Doppelbelegung erkannt";
    title.style.marginTop = "0";
    title.style.color = "#dc2626";

    const info = document.createElement("p");
    info.style.marginBottom = "15px";
    info.innerHTML = `<strong>${mitarbeiterName}</strong> ist bereits an diesem Tag eingeteilt:`;

    const list = document.createElement("ul");
    list.style.marginBottom = "20px";
    list.style.paddingLeft = "20px";
    existingAssignments.forEach((assignment) => {
      const li = document.createElement("li");
      li.textContent = `${assignment.standortName} – ${assignment.shiftName} – Personal ${assignment.slotIndex}`;
      list.appendChild(li);
    });

    const question = document.createElement("p");
    question.style.marginBottom = "20px";
    question.style.fontWeight = "600";
    question.textContent = "Möchten Sie den Mitarbeiter trotzdem einteilen?";

    const actions = document.createElement("div");
    actions.className = "form-actions";
    actions.style.display = "flex";
    actions.style.gap = "10px";
    actions.style.justifyContent = "flex-end";

    const confirmBtn = document.createElement("button");
    confirmBtn.textContent = "Mitarbeiter trotzdem einteilen";
    confirmBtn.style.padding = "10px 20px";
    confirmBtn.style.background = "#dc2626";
    confirmBtn.style.color = "white";
    confirmBtn.style.border = "none";
    confirmBtn.style.borderRadius = "8px";
    confirmBtn.style.cursor = "pointer";
    confirmBtn.style.fontWeight = "600";

    const cancelBtn = document.createElement("button");
    cancelBtn.textContent = "Abbruch";
    cancelBtn.className = "cancel-btn";
    cancelBtn.style.padding = "10px 20px";
    cancelBtn.style.background = "#64748b";
    cancelBtn.style.color = "white";
    cancelBtn.style.border = "none";
    cancelBtn.style.borderRadius = "8px";
    cancelBtn.style.cursor = "pointer";
    cancelBtn.style.fontWeight = "600";

    actions.appendChild(cancelBtn);
    actions.appendChild(confirmBtn);

    dialog.appendChild(title);
    dialog.appendChild(info);
    dialog.appendChild(list);
    dialog.appendChild(question);
    dialog.appendChild(actions);

    // Overlay erstellen
    const overlay = document.createElement("div");
    overlay.id = "doubleAssignmentWarningOverlay";
    overlay.style.position = "fixed";
    overlay.style.top = "0";
    overlay.style.left = "0";
    overlay.style.width = "100%";
    overlay.style.height = "100%";
    overlay.style.background = "rgba(0, 0, 0, 0.5)";
    overlay.style.zIndex = "9999";

    document.body.appendChild(overlay);
    document.body.appendChild(dialog);

    cancelBtn.addEventListener("click", () => {
      dialog.remove();
      overlay.remove();
      resolve(false);
    });

    confirmBtn.addEventListener("click", () => {
      dialog.remove();
      overlay.remove();
      resolve(true);
    });

    // Overlay-Klick schließt auch (Abbruch)
    overlay.addEventListener("click", () => {
      dialog.remove();
      overlay.remove();
      resolve(false);
    });
  });
}

// ---------------------------------------------------------
// Bereitschaften-Top-Grid (aus Firestore)
// ---------------------------------------------------------

async function renderBereitschaftenTop(dayId) {
  if (!dayBereitschaftenTop) return;

  dayBereitschaftenTop.innerHTML = "<div class='info-text'>Lade Bereitschaften...</div>";

  try {
    const bereitschaften = [];
    
    // Verwende getStandorteForDay um auch gelöschte Standorte für vergangene Tage zu berücksichtigen
    const standorteForDay = getStandorteForDay(dayId);

    for (const standort of standorteForDay) {
      if (!standort || !standort.id) continue; // Sicherheitscheck
      
      // Für vergangene Tage auch gelöschte Standorte berücksichtigen
      try {
        const dayDate = parseDayId(dayId);
        if (!dayDate || isNaN(dayDate.getTime())) {
          console.error(`❌ Ungültiges Datum in renderBereitschaftenTop: ${dayId}`);
          continue;
        }
        
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        dayDate.setHours(0, 0, 0, 0);
        const isPastDay = dayDate < today;
        
        // Für zukünftige Tage nur aktive Standorte, für vergangene auch gelöschte
        if (!isPastDay && (standort.active === false || standort.deleted === true)) continue;
      } catch (e) {
        console.error(`❌ Fehler beim Parsen des Datums für Standort ${standort.id}:`, e);
        continue;
      }

      try {
        const bereitschaftenCol = getBereitschaftenCollection(standort.id, dayId);
        const snap = await getDocs(bereitschaftenCol);

        snap.forEach((docSnap) => {
          const data = docSnap.data() || {};
          bereitschaften.push({
            id: docSnap.id,
            standortId: standort.id,
            standortName: standort.name,
            ...data,
          });
        });
      } catch (e) {
        console.error(`❌ Fehler beim Laden der Bereitschaften für Standort ${standort.id}:`, e);
        // Weiter mit nächstem Standort
      }
    }

    if (bereitschaften.length === 0) {
      dayBereitschaftenTop.innerHTML =
        "<div class='info-text'>Keine Bereitschaften für diesen Tag hinterlegt.</div>";
      return;
    }

    const grid = document.createElement("div");
    grid.className = "bereitschaften-top-grid";

    bereitschaften.forEach((b) => {
      let name = b.name || "Unbekannt";

      // Qualifikationen und Führerschein bestimmen
      let qualis = [];
      if (Array.isArray(b.qualifikationen)) {
        qualis = b.qualifikationen;
      } else if (Array.isArray(b.qualifikation)) {
        qualis = b.qualifikation;
      }

      let fuehrerschein = b.fuehrerschein || "";

      // Falls im Bereitschafts-Dokument nichts steht, versuche aus Mitarbeiter-Stammdaten zu lesen
      if ((!qualis.length || !fuehrerschein) && b.mitarbeiterId) {
        const ma = allMitarbeiter.find((m) => m.id === b.mitarbeiterId);
        if (ma) {
          if (!qualis.length) {
            if (Array.isArray(ma.qualifikationen)) {
              qualis = ma.qualifikationen;
            } else if (Array.isArray(ma.qualifikation)) {
              qualis = ma.qualifikation;
            }
          }
          if (!fuehrerschein && ma.fuehrerschein) {
            fuehrerschein = ma.fuehrerschein;
          }
        }
      }

      let details = "";
      const qualText = qualis && qualis.length ? qualis.join("/") : "";
      if (qualText && fuehrerschein) {
        details = ` (${qualText} mit ${fuehrerschein})`;
      } else if (qualText) {
        details = ` (${qualText})`;
      } else if (fuehrerschein) {
        details = ` (mit ${fuehrerschein})`;
      }

      const item = document.createElement("div");
      item.className = "bereitschaft-top-item";
      item.dataset.bereitschaftId = b.id;
      item.dataset.standortId = b.standortId;
      item.dataset.mitarbeiterId = b.mitarbeiterId || "";
      item.dataset.name = name;

      const nameSpan = document.createElement("div");
      nameSpan.className = "bereitschaft-name";
      nameSpan.textContent = name + details;

      item.appendChild(nameSpan);
      // Bereitschafts-Typ mit anzeigen (zweite Zeile, falls vorhanden)
      if (b.bereitschaftsTypId) {
        const typ = allBereitschaftsTypen.find((t) => t.id === b.bereitschaftsTypId);
        if (typ && typ.name) {
          const typSpan = document.createElement("div");
          typSpan.className = "bereitschaft-typ-top";
          typSpan.textContent = typ.name;
          item.appendChild(typSpan);
        }
      }

      // Lösch-Button für Bereitschaft im Tages-Popup (oben im Grid)
      const deleteBtn = document.createElement("button");
      deleteBtn.className = "bereitschaft-top-delete";
      deleteBtn.title = "Bereitschaft löschen";
      // Bereitschaften haben grauen Hintergrund (#f3f4f6) → schwarzes Icon
      deleteBtn.innerHTML = getTrashIconSVG("#f3f4f6");
      deleteBtn.addEventListener("click", async (ev) => {
        ev.stopPropagation();
        ev.preventDefault();
        if (!confirm("Diese Bereitschaft wirklich löschen?")) return;
        try {
          const bereitsCol = getBereitschaftenCollection(b.standortId, dayId);
          await deleteDoc(doc(bereitsCol, b.id));
          await renderBereitschaftenTop(dayId);
        } catch (err) {
          console.error("Fehler beim Löschen der Bereitschaft:", err);
          alert("Fehler beim Löschen der Bereitschaft: " + err.message);
        }
      });
      item.appendChild(deleteBtn);

      // Linksklick: Mitarbeiter-Datenblatt mit Schichtzuweisung öffnen
      item.addEventListener("click", (ev) => {
        // Nicht öffnen, wenn auf den Lösch-Button geklickt wurde
        if (ev.target === deleteBtn || ev.target.closest('.bereitschaft-top-delete')) {
          return;
        }
        openMitarbeiterDatenblattFromBereitschaft(dayId, b);
      });

      // Rechtsklick / Long-Press: ebenfalls Mitarbeiter-Datenblatt mit Schichtzuweisung öffnen
      item.addEventListener("contextmenu", (ev) => {
        ev.preventDefault();
        openMitarbeiterDatenblattFromBereitschaft(dayId, b);
      });

      let longPressTimer = null;
      item.addEventListener("touchstart", (ev) => {
        // Nicht preventDefault, damit normaler Click auch funktioniert
        // Nur Copy-Menü unterdrücken
        if (ev.target) {
          ev.target.style.webkitTouchCallout = "none";
          ev.target.style.webkitUserSelect = "none";
          ev.target.style.userSelect = "none";
        }
        // Long-Press Timer für Long-Press (nur wenn lange gedrückt wird)
        longPressTimer = window.setTimeout(() => {
          openMitarbeiterDatenblattFromBereitschaft(dayId, b);
        }, 600);
      });
      ["touchend", "touchcancel", "touchmove"].forEach((evt) => {
        item.addEventListener(evt, (ev) => {
          // Timer löschen, damit bei normalem Tap der Click-Event ausgelöst wird
          if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
          }
          // Nicht preventDefault, damit normaler Click funktioniert
        });
      });

      grid.appendChild(item);
    });

    dayBereitschaftenTop.innerHTML = "";
    dayBereitschaftenTop.appendChild(grid);
  } catch (e) {
    console.error("Fehler beim Laden der Bereitschaften für das Top-Grid:", e);
    dayBereitschaftenTop.innerHTML =
      "<div class='info-text' style='color:red;'>Fehler beim Laden der Bereitschaften.</div>";
  }
}

// Bereitschafts-Popup für aktuellen Tag öffnen
if (addBereitschaftForDayBtn) {
  addBereitschaftForDayBtn.addEventListener("click", async () => {
    if (!currentDayId) {
      alert("Bitte zuerst einen Tag im Kalender auswählen.");
      return;
    }
    if (!personnelPopupOverlay || !personnelPopupForm) return;

    personnelPopupForm.dataset.mode = "bereitschaft";
    personnelPopupForm.dataset.dayId = currentDayId;
    personnelPopupForm.dataset.standortId = "";
    personnelPopupForm.dataset.shiftId = "";
    personnelPopupForm.dataset.slotIndex = "";

    fillMitarbeiterSelect();
    
    // Custom Liste zurücksetzen (Falls vorhanden)
    const personnelMitarbeiterList = document.getElementById("personnelMitarbeiterList");
    if (personnelMitarbeiterList) {
      personnelMitarbeiterList.querySelectorAll(".personnel-mitarbeiter-list-item").forEach(el => {
        el.classList.remove("selected");
      });
    }

    if (personnelMitarbeiterSearch) personnelMitarbeiterSearch.value = "";
    if (personnelColor) personnelColor.value = "#ffffff";

    // Farb-Auswahl im Bereitschaftsmodus ausblenden (irrelevant für Bereitschaften)
    if (personnelColorLabel) personnelColorLabel.style.display = "none";
    if (personnelColor) personnelColor.style.display = "none";

    // Bereitschafts-Typ-Select befüllen und anzeigen
    if (bereitschaftsTypSelect && bereitschaftsTypLabel) {
      try {
        bereitschaftsTypSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
        const snap = await getDocs(query(getBereitschaftsTypenCollection(), orderBy("name", "asc")));
        snap.forEach((docSnap) => {
          const data = docSnap.data() || {};
          const opt = document.createElement("option");
          opt.value = docSnap.id;
          opt.textContent = data.name || docSnap.id;
          bereitschaftsTypSelect.appendChild(opt);
        });
        bereitschaftsTypLabel.style.display = "block";
        bereitschaftsTypSelect.style.display = "block";
      } catch (e) {
        console.error("Fehler beim Laden der Bereitschafts-Typen:", e);
        alert("Fehler beim Laden der Bereitschafts-Typen. Details siehe Konsole.");
      }
    }

    personnelPopupOverlay.style.display = "block";
    personnelPopupForm.style.display = "block";
  });
}

// ---------------------------------------------------------
// Personal-Popup
// ---------------------------------------------------------

window.openPersonnelPopup = function (dayId, standortId, shiftId, slotIndex) {
  if (!personnelPopupOverlay || !personnelPopupForm) return;

  personnelPopupForm.dataset.mode = "shift";
  personnelPopupForm.dataset.dayId = dayId;
  personnelPopupForm.dataset.standortId = standortId;
  personnelPopupForm.dataset.shiftId = shiftId;
  personnelPopupForm.dataset.slotIndex = String(slotIndex);

  // Mitarbeiter-Liste füllen
  fillMitarbeiterSelect();
  
  // Custom Liste zurücksetzen (Falls vorhanden)
  const personnelMitarbeiterList = document.getElementById("personnelMitarbeiterList");
  if (personnelMitarbeiterList) {
    personnelMitarbeiterList.querySelectorAll(".personnel-mitarbeiter-list-item").forEach(el => {
      el.classList.remove("selected");
    });
  }

  if (personnelMitarbeiterSearch) personnelMitarbeiterSearch.value = "";
  if (personnelColor) personnelColor.value = "#ffffff";

  // Farb-Auswahl im normalen Schichtmodus anzeigen
  if (personnelColorLabel) personnelColorLabel.style.display = "block";
  if (personnelColor) personnelColor.style.display = "block";

  // Bereitschafts-Typ-UI im normalen Modus ausblenden
  if (bereitschaftsTypLabel) bereitschaftsTypLabel.style.display = "none";
  if (bereitschaftsTypSelect) {
    bereitschaftsTypSelect.style.display = "none";
    bereitschaftsTypSelect.value = "";
  }

  personnelPopupOverlay.style.display = "block";
  personnelPopupForm.style.display = "block";
};

window.closePersonnelPopup = function () {
  if (personnelPopupOverlay) personnelPopupOverlay.style.display = "none";
  if (personnelPopupForm) personnelPopupForm.style.display = "none";
};

function fillMitarbeiterSelect() {
  if (!personnelMitarbeiterSelect) return;
  if (!allMitarbeiter || !Array.isArray(allMitarbeiter)) {
    console.warn("⚠️ allMitarbeiter noch nicht geladen");
    return;
  }
  
  try {
    const personnelMitarbeiterList = document.getElementById("personnelMitarbeiterList");

    // Verstecktes Select für Validierung behalten
    personnelMitarbeiterSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';

    // Mitarbeiter für Filterung sammeln
    const mitarbeiterArray = allMitarbeiter.filter((m) => m.active !== false);

    mitarbeiterArray.forEach((m) => {
      const opt = document.createElement("option");
      opt.value = m.id;
      // Anzeige: Name + Qualifikation + Führerschein
      let qualis = [];
      if (Array.isArray(m.qualifikationen)) {
        qualis = m.qualifikationen;
      } else if (Array.isArray(m.qualifikation)) {
        qualis = m.qualifikation;
      }
      const qualText = qualis.length ? qualis.join("/") : "";
      const fs = m.fuehrerschein || "";
      let details = "";
      if (qualText && fs) {
        details = ` (${qualText} mit ${fs})`;
      } else if (qualText) {
        details = ` (${qualText})`;
      } else if (fs) {
        details = ` (mit ${fs})`;
      }
      opt.textContent = `${m.nachname}, ${m.vorname}${details}`;
      personnelMitarbeiterSelect.appendChild(opt);
    });

    // Custom Liste immer rendern (wird auf Desktop versteckt, auf Mobile angezeigt)
    if (personnelMitarbeiterList) {
      renderMitarbeiterList(mitarbeiterArray, "");
      
      // Auf Desktop: Select zeigen, Liste verstecken
      // Auf Mobile: Select verstecken, Liste zeigen (wird durch CSS gemacht)
      const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || window.innerWidth <= 1200;
      if (!isMobile) {
        personnelMitarbeiterSelect.style.display = "block";
        personnelMitarbeiterList.style.display = "none";
      } else {
        personnelMitarbeiterSelect.style.display = "none";
        personnelMitarbeiterList.style.display = "block";
      }
    }

    // Suchfeld verbindet sich mit der Liste
    if (personnelMitarbeiterSearch) {
      personnelMitarbeiterSearch.oninput = () => {
        const term = personnelMitarbeiterSearch.value.toLowerCase();
        const personnelMitarbeiterList = document.getElementById("personnelMitarbeiterList");
        
        // Verstecktes Select aktualisieren
        personnelMitarbeiterSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
        const filtered = allMitarbeiter
          .filter((m) => m.active !== false)
          .filter((m) =>
            !term ||
            m.nachname.toLowerCase().includes(term) ||
            m.vorname.toLowerCase().includes(term)
          );
        
        filtered.forEach((m) => {
          const opt = document.createElement("option");
          opt.value = m.id;
          // Anzeige: Name + Qualifikation + Führerschein (wie oben)
          let qualis = [];
          if (Array.isArray(m.qualifikationen)) {
            qualis = m.qualifikationen;
          } else if (Array.isArray(m.qualifikation)) {
            qualis = m.qualifikation;
          }
          const qualText = qualis.length ? qualis.join("/") : "";
          const fs = m.fuehrerschein || "";
          let details = "";
          if (qualText && fs) {
            details = ` (${qualText} mit ${fs})`;
          } else if (qualText) {
            details = ` (${qualText})`;
          } else if (fs) {
            details = ` (mit ${fs})`;
          }
          opt.textContent = `${m.nachname}, ${m.vorname}${details}`;
          personnelMitarbeiterSelect.appendChild(opt);
        });
        
        // Custom Liste aktualisieren
        if (personnelMitarbeiterList) {
          renderMitarbeiterList(filtered, term);
        }
      };
    }
  } catch (e) {
    console.error("❌ Fehler in fillMitarbeiterSelect:", e);
  }
}

// Custom Liste für Mitarbeiter rendern (für mobile Geräte)
function renderMitarbeiterList(mitarbeiterArray, searchTerm) {
  const personnelMitarbeiterList = document.getElementById("personnelMitarbeiterList");
  if (!personnelMitarbeiterList) return;
  
  personnelMitarbeiterList.innerHTML = "";
  
  mitarbeiterArray.forEach((m) => {
    const item = document.createElement("div");
    item.className = "personnel-mitarbeiter-list-item";
    item.dataset.mitarbeiterId = m.id;
    
    // Anzeige: Name + Qualifikation + Führerschein
    let qualis = [];
    if (Array.isArray(m.qualifikationen)) {
      qualis = m.qualifikationen;
    } else if (Array.isArray(m.qualifikation)) {
      qualis = m.qualifikation;
    }
    const qualText = qualis.length ? qualis.join("/") : "";
    const fs = m.fuehrerschein || "";
    let details = "";
    if (qualText && fs) {
      details = ` (${qualText} mit ${fs})`;
    } else if (qualText) {
      details = ` (${qualText})`;
    } else if (fs) {
      details = ` (mit ${fs})`;
    }
    
    item.textContent = `${m.nachname}, ${m.vorname}${details}`;
    
    item.addEventListener("click", () => {
      // Entferne vorherige Auswahl
      personnelMitarbeiterList.querySelectorAll(".personnel-mitarbeiter-list-item").forEach(el => {
        el.classList.remove("selected");
      });
      // Markiere als ausgewählt
      item.classList.add("selected");
      // Aktualisiere verstecktes Select
      personnelMitarbeiterSelect.value = m.id;
    });
    
    personnelMitarbeiterList.appendChild(item);
  });
}

if (savePersonnelBtn) {
  savePersonnelBtn.addEventListener("click", async () => {
    if (!personnelPopupForm) return;

    const mode = personnelPopupForm.dataset.mode || "shift";
    const dayId = personnelPopupForm.dataset.dayId;

    if (!personnelMitarbeiterSelect) {
      alert("Fehler: Mitarbeiter-Auswahl nicht gefunden.");
      return;
    }

    // Falls keine Auswahl im Select, prüfe ob in der Custom-Liste ausgewählt
    let mitarbeiterId = personnelMitarbeiterSelect.value;
    if (!mitarbeiterId) {
      const selectedItem = document.querySelector(".personnel-mitarbeiter-list-item.selected");
      if (selectedItem && selectedItem.dataset.mitarbeiterId) {
        mitarbeiterId = selectedItem.dataset.mitarbeiterId;
        personnelMitarbeiterSelect.value = mitarbeiterId; // Für Validierung
      }
    }

    if (!mitarbeiterId) {
      alert("Bitte wählen Sie einen Mitarbeiter aus.");
      return;
    }

    const mitarbeiter = allMitarbeiter.find((m) => m.id === mitarbeiterId);
    if (!mitarbeiter) {
      alert("Mitarbeiter nicht gefunden.");
      return;
    }

    const farbe = personnelColor ? personnelColor.value : "#ffffff";

    const qualis = QUALIFIKATIONEN.filter((q) => (mitarbeiter.qualifikation || []).includes(q));

    const personalData = {
      mitarbeiterId,
      name: `${mitarbeiter.vorname} ${mitarbeiter.nachname}`,
      qualifikationen: qualis,
      farbe,
    };

    try {
      if (mode === "bereitschaft") {
        // Bereitschaft für Tag anlegen (global für den Tag, Standorte werden später nur für den Pfad genutzt)
        if (!dayId) {
          alert("Fehler: Tag-Information fehlt.");
          return;
        }
        if (!bereitschaftsTypSelect) {
          alert("Fehler: Bereitschafts-Typ-Auswahl nicht gefunden.");
          return;
        }
        const typId = bereitschaftsTypSelect.value;
        if (!typId) {
          alert("Bitte einen Bereitschafts-Typ auswählen.");
          return;
        }

        // Einen beliebigen aktiven Standort als Container verwenden
        const standort =
          allStandorte.find((s) => s.active !== false) || (allStandorte.length ? allStandorte[0] : null);
        if (!standort) {
          alert("Es ist kein Standort konfiguriert. Bitte zuerst einen Standort anlegen.");
          return;
        }

        const col = getBereitschaftenCollection(standort.id, dayId);
        await addDoc(col, {
          mitarbeiterId,
          name: personalData.name,
          qualifikationen: personalData.qualifikationen,
          fuehrerschein: mitarbeiter.fuehrerschein || "",
          bereitschaftsTypId: typId,
        });

        closePersonnelPopup();
        await showCalendarDayDetails(dayId);
      } else {
        // Normaler Modus: Personal einem Schicht-Slot zuordnen
        const standortId = personnelPopupForm.dataset.standortId;
        const shiftId = personnelPopupForm.dataset.shiftId;
        const slotIndexStr = personnelPopupForm.dataset.slotIndex;

        if (!dayId || !standortId || !shiftId || !slotIndexStr) {
          alert("Fehler: Kontextinformationen fehlen.");
          return;
        }

        const slotIndex = parseInt(slotIndexStr, 10);

        // Prüfe auf Doppelbelegung
        const existingAssignments = await checkMitarbeiterAlreadyAssigned(dayId, mitarbeiterId, standortId, shiftId, slotIndex);
        if (existingAssignments.length > 0) {
          const shouldContinue = await showDoubleAssignmentWarning(personalData.name, existingAssignments);
          if (!shouldContinue) {
            return; // Abbruch
          }
        }

        const shiftsCol = getShiftsCollection(standortId, dayId);
        const ref = doc(shiftsCol, shiftId);
        const field = slotIndex === 1 ? "personal1" : "personal2";
        await setDoc(ref, { [field]: personalData }, { merge: true });

        console.log(
          `✅ Personal in Slot ${slotIndex} von Schicht ${shiftId} für Standort ${standortId} gespeichert.`
        );

        closePersonnelPopup();
        await showCalendarDayDetails(dayId); // Ansicht aktualisieren
      }
    } catch (e) {
      console.error("Fehler beim Speichern des Personals:", e);
      alert("Fehler beim Speichern des Personals: " + e.message);
    }
  });
}

// ---------------------------------------------------------
// Settings-Handler (nur Öffnen/Schließen der Settings)
// ---------------------------------------------------------

function setupSettingsHandlers() {
  if (!settingsBtn || !settingsPopupOverlay || !settingsPopupForm) return;

  // Tabs basierend auf Rolle anzeigen/ausblenden
  const isAdmin = userAuthData && (userAuthData.role === "admin" || userAuthData.role === "superadmin");
  
  const standorteTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="standorte"]');
  const schichtenTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="schichten"]');
  const bereitschaftenTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="bereitschaften"]');
  const standorteTabPane = settingsPopupForm.querySelector('#tab-standorte');
  const schichtenTabPane = settingsPopupForm.querySelector('#tab-schichten');
  const bereitschaftenTabPane = settingsPopupForm.querySelector('#tab-bereitschaften');
  
  if (!isAdmin) {
    // Für Nicht-Admins: Standorte, Schichten und Bereitschaften Tabs ausblenden
    if (standorteTabBtn) standorteTabBtn.style.display = "none";
    if (schichtenTabBtn) schichtenTabBtn.style.display = "none";
    if (bereitschaftenTabBtn) bereitschaftenTabBtn.style.display = "none";
    if (standorteTabPane) standorteTabPane.style.display = "none";
    if (schichtenTabPane) schichtenTabPane.style.display = "none";
    if (bereitschaftenTabPane) bereitschaftenTabPane.style.display = "none";
    
    // Ersten sichtbaren Tab aktivieren (Mitarbeiter)
    const mitarbeiterTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="mitarbeiter"]');
    const mitarbeiterTabPane = settingsPopupForm.querySelector('#tab-mitarbeiter');
    if (mitarbeiterTabBtn && mitarbeiterTabPane) {
      // Alle Tabs deaktivieren
      settingsPopupForm.querySelectorAll(".tab-btn").forEach(b => b.classList.remove("active"));
      settingsPopupForm.querySelectorAll(".tab-pane").forEach(p => p.classList.remove("active"));
      // Mitarbeiter Tab aktivieren
      mitarbeiterTabBtn.classList.add("active");
      mitarbeiterTabPane.classList.add("active");
    }
  } else {
    // Für Admins: Alle Tabs anzeigen
    if (standorteTabBtn) standorteTabBtn.style.display = "";
    if (schichtenTabBtn) schichtenTabBtn.style.display = "";
    if (bereitschaftenTabBtn) bereitschaftenTabBtn.style.display = "";
    if (standorteTabPane) standorteTabPane.style.display = "";
    if (schichtenTabPane) schichtenTabPane.style.display = "";
    if (bereitschaftenTabPane) bereitschaftenTabPane.style.display = "";
  }

  // Tabs
  const tabButtons = settingsPopupForm.querySelectorAll(".tab-btn");
  const tabPanes = settingsPopupForm.querySelectorAll(".tab-pane");

  tabButtons.forEach((btn) => {
    btn.addEventListener("click", () => {
      const target = btn.dataset.tab;

      tabButtons.forEach((b) => b.classList.remove("active"));
      tabPanes.forEach((p) => p.classList.remove("active"));

      btn.classList.add("active");
      const pane = settingsPopupForm.querySelector(`#tab-${target}`);
      if (pane) pane.classList.add("active");
    });
  });

  // Buttons / Listen
  const addStandortBtn = document.getElementById("addStandortBtn");
  const standorteList = document.getElementById("standorteList");

  const addSchichtBtn = document.getElementById("addSchichtBtn");
  const schichtenList = document.getElementById("schichtenList");

  const addMitarbeiterBtn = document.getElementById("addMitarbeiterBtn");
  const mitarbeiterList = document.getElementById("mitarbeiterList");

  const addBereitschaftsTypBtn = document.getElementById("addBereitschaftsTypBtn");
  const bereitschaftsTypenList = document.getElementById("bereitschaftsTypenList");

  // Form-Elemente
  const standortForm = document.getElementById("standortForm");
  const standortFormTitle = document.getElementById("standortFormTitle");
  const standortNameInput = document.getElementById("standortName");
  const saveStandortBtn = document.getElementById("saveStandortBtn");

  const schichtForm = document.getElementById("schichtForm");
  const schichtFormTitle = document.getElementById("schichtFormTitle");
  const schichtNameInput = document.getElementById("schichtName");
  const schichtStandortSelect = document.getElementById("schichtStandort");
  const saveSchichtBtn = document.getElementById("saveSchichtBtn");

  const mitarbeiterForm = document.getElementById("mitarbeiterForm");
  const mitarbeiterFormTitle = document.getElementById("mitarbeiterFormTitle");
  const mitarbeiterVornameInput = document.getElementById("mitarbeiterVorname");
  const mitarbeiterNachnameInput = document.getElementById("mitarbeiterNachname");
  const mitarbeiterQualifikationenContainer = document.getElementById("mitarbeiterQualifikationen");
  const mitarbeiterFuehrerscheinInput = document.getElementById("mitarbeiterFuehrerschein");
  const mitarbeiterTelefonInput = document.getElementById("mitarbeiterTelefon");
  const saveMitarbeiterBtn = document.getElementById("saveMitarbeiterBtn");

  const bereitschaftsTypForm = document.getElementById("bereitschaftsTypForm");
  const bereitschaftsTypFormTitle = document.getElementById("bereitschaftsTypFormTitle");
  const bereitschaftsTypNameInput = document.getElementById("bereitschaftsTypName");
  const bereitschaftsTypBeschreibungInput = document.getElementById("bereitschaftsTypBeschreibung");
  const saveBereitschaftsTypBtn = document.getElementById("saveBereitschaftsTypBtn");

  // Qualifikations-Checkboxen im Mitarbeiter-Formular (nur eine Auswahl möglich - Radio-Button-Verhalten)
  if (mitarbeiterQualifikationenContainer) {
    mitarbeiterQualifikationenContainer.innerHTML = "";
    QUALIFIKATIONEN.forEach((q) => {
      const label = document.createElement("label");
      label.className = "qualification-pill";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.value = q;
      checkbox.className = "qualification-checkbox";
      // Event-Listener: Wenn eine Checkbox aktiviert wird, deaktiviere alle anderen
      checkbox.addEventListener("change", (e) => {
        if (e.target.checked) {
          // Alle anderen Checkboxen deaktivieren
          mitarbeiterQualifikationenContainer
            .querySelectorAll("input.qualification-checkbox")
            .forEach((cb) => {
              if (cb !== e.target) {
                cb.checked = false;
              }
            });
        }
      });
      label.appendChild(checkbox);
      label.appendChild(document.createTextNode(" " + q));
      mitarbeiterQualifikationenContainer.appendChild(label);
    });
  }

  // Suchfeld Event-Listener für Mitarbeiter (verwende Event-Delegation über das Settings-Form)
  // Das funktioniert auch, wenn das Element beim Setup noch nicht sichtbar ist
  if (settingsPopupForm && mitarbeiterList) {
    settingsPopupForm.addEventListener("input", (e) => {
      // Prüfe, ob das Input-Event vom Mitarbeiter-Suchfeld stammt
      if (e.target && e.target.id === "mitarbeiterSearchInput") {
        const searchTerm = (e.target.value || "").trim();
        console.log(`🔍 Suche Mitarbeiter: "${searchTerm}"`);
        reloadMitarbeiterSettings(mitarbeiterList, searchTerm);
      }
    });
    console.log("✅ Mitarbeiter-Suchfeld Event-Listener registriert (Event-Delegation)");
  }

  // Einstellungs-Popup öffnen + Listen laden
  settingsBtn.addEventListener("click", async () => {
    settingsPopupOverlay.style.display = "block";
    // als Flex-Container anzeigen (Größe ist in CSS fix definiert)
    settingsPopupForm.style.display = "flex";

    // Tabs basierend auf Rolle anzeigen/ausblenden (beim Öffnen sicherstellen)
    const isAdmin = userAuthData && (userAuthData.role === "admin" || userAuthData.role === "superadmin");
    
    const standorteTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="standorte"]');
    const schichtenTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="schichten"]');
    const bereitschaftenTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="bereitschaften"]');
    const standorteTabPane = settingsPopupForm.querySelector('#tab-standorte');
    const schichtenTabPane = settingsPopupForm.querySelector('#tab-schichten');
    const bereitschaftenTabPane = settingsPopupForm.querySelector('#tab-bereitschaften');
    
    if (!isAdmin) {
      // Für Nicht-Admins: Standorte, Schichten und Bereitschaften Tabs ausblenden
      if (standorteTabBtn) standorteTabBtn.style.display = "none";
      if (schichtenTabBtn) schichtenTabBtn.style.display = "none";
      if (bereitschaftenTabBtn) bereitschaftenTabBtn.style.display = "none";
      if (standorteTabPane) standorteTabPane.style.display = "none";
      if (schichtenTabPane) schichtenTabPane.style.display = "none";
      if (bereitschaftenTabPane) bereitschaftenTabPane.style.display = "none";
      
      // Ersten sichtbaren Tab aktivieren (Mitarbeiter)
      const mitarbeiterTabBtn = settingsPopupForm.querySelector('.tab-btn[data-tab="mitarbeiter"]');
      const mitarbeiterTabPane = settingsPopupForm.querySelector('#tab-mitarbeiter');
      if (mitarbeiterTabBtn && mitarbeiterTabPane) {
        // Alle Tabs deaktivieren
        settingsPopupForm.querySelectorAll(".tab-btn").forEach(b => {
          if (b.style.display !== "none") b.classList.remove("active");
        });
        settingsPopupForm.querySelectorAll(".tab-pane").forEach(p => {
          if (p.style.display !== "none") p.classList.remove("active");
        });
        // Mitarbeiter Tab aktivieren
        mitarbeiterTabBtn.classList.add("active");
        mitarbeiterTabPane.classList.add("active");
      }
    } else {
      // Für Admins: Alle Tabs anzeigen
      if (standorteTabBtn) standorteTabBtn.style.display = "";
      if (schichtenTabBtn) schichtenTabBtn.style.display = "";
      if (bereitschaftenTabBtn) bereitschaftenTabBtn.style.display = "";
      if (standorteTabPane) standorteTabPane.style.display = "";
      if (schichtenTabPane) schichtenTabPane.style.display = "";
      if (bereitschaftenTabPane) bereitschaftenTabPane.style.display = "";
      
      // Standorte Tab als Standard aktivieren (falls noch nichts aktiv ist)
      const activeTab = settingsPopupForm.querySelector(".tab-btn.active");
      if (!activeTab && standorteTabBtn && standorteTabPane) {
        standorteTabBtn.classList.add("active");
        standorteTabPane.classList.add("active");
      }
    }

    // Suchfeld zurücksetzen beim Öffnen
    const searchInput = document.getElementById("mitarbeiterSearchInput");
    if (searchInput) {
      searchInput.value = "";
    }

    await Promise.all([
      reloadStandorteSettings(standorteList, schichtStandortSelect),
      reloadSchichtenSettings(schichtenList),
      reloadMitarbeiterSettings(mitarbeiterList, ""),
      reloadBereitschaftsTypenSettings(bereitschaftsTypenList),
    ]);
  });

  // Standort hinzufügen
  if (addStandortBtn && standortForm && standortNameInput && standortFormTitle && saveStandortBtn) {
    addStandortBtn.addEventListener("click", () => {
      standortForm.dataset.mode = "create";
      standortForm.dataset.id = "";
      standortFormTitle.textContent = "Standort hinzufügen";
      standortNameInput.value = "";
      const ov = document.getElementById("standortFormOverlay");
      if (ov) ov.style.display = "block";
      standortForm.style.display = "block";
    });

    saveStandortBtn.addEventListener("click", async () => {
      const name = (standortNameInput.value || "").trim();
      if (!name) {
        alert("Bitte einen Standortnamen eingeben.");
        return;
      }

      try {
        const mode = standortForm.dataset.mode || "create";
        const id = standortForm.dataset.id;

        if (mode === "edit" && id) {
          // Prüfe ob Name geändert wurde
          const oldStandort = allStandorte.find(s => s.id === id);
          const oldName = oldStandort?.name;
          
          if (oldName && oldName !== name) {
            // Name wurde geändert - aktualisiere nur zukünftige Schichten
            await updateStandortNameWithHistoryPreservation(id, oldName, name);
          }
          
          const ref = doc(getStandorteCollection(), id);
          await setDoc(ref, { name }, { merge: true });
          console.log(`✅ Standort "${name}" aktualisiert (ID: ${id})`);
        } else {
          // neuen Standort anlegen
          // Berechne order basierend auf Anzahl vorhandener Standorte
          const existingStandorte = await getDocs(getStandorteCollection());
          const maxOrder = existingStandorte.docs.reduce((max, d) => {
            const data = d.data();
            return Math.max(max, data.order || 0);
          }, 0);
          
          const docRef = await addDoc(getStandorteCollection(), {
            name,
            active: true,
            order: maxOrder + 1,
          });
          console.log(`✅ Neuer Standort "${name}" angelegt (ID: ${docRef.id}, order: ${maxOrder + 1})`);
        }

        await reloadStandorteSettings(standorteList, schichtStandortSelect);
        window.closeStandortForm();
        await loadStandorte(); // auch Stammdaten aktualisieren
      } catch (e) {
        console.error("❌ Fehler beim Speichern des Standorts:", e);
        alert("Fehler beim Speichern des Standorts: " + e.message);
      }
    });
  }

  // Schicht hinzufügen
  if (addSchichtBtn && schichtForm && schichtNameInput && schichtStandortSelect && schichtFormTitle && saveSchichtBtn) {
    addSchichtBtn.addEventListener("click", async () => {
      schichtForm.dataset.mode = "create";
      schichtForm.dataset.id = "";
      schichtFormTitle.textContent = "Schicht hinzufügen";
      schichtNameInput.value = "";

      // Standorte in das Dropdown laden
      await reloadStandorteSettings(null, schichtStandortSelect);

      const ov = document.getElementById("schichtFormOverlay");
      if (ov) ov.style.display = "block";
      schichtForm.style.display = "block";
    });

    saveSchichtBtn.addEventListener("click", async () => {
      const name = (schichtNameInput.value || "").trim();
      const standortId = schichtStandortSelect.value;
      if (!name || !standortId) {
        alert("Bitte Schichtname und Standort auswählen.");
        return;
      }

      console.log(`💾 Speichere Schicht: name="${name}", standortId="${standortId}"`);

      try {
        const mode = schichtForm.dataset.mode || "create";
        const id = schichtForm.dataset.id;

        // Bestimme die nächste order-Nummer für neue Schichten
        let orderValue = 0;
        if (mode === "create") {
          // Finde die höchste order-Nummer
          const maxOrder = allSchichten.reduce((max, s) => {
            const order = s.order || 0;
            return Math.max(max, order);
          }, 0);
          orderValue = maxOrder + 1;
        }

        const dataToSave = {
          name,
          standortId: standortId.trim(), // Trim für Konsistenz
          active: mode === "create" ? true : undefined, // Nur bei Erstellung setzen
          order: mode === "create" ? orderValue : undefined, // Order nur bei Erstellung setzen
        };

        console.log(`💾 Zu speichernde Daten:`, dataToSave);
        console.log(`💾 Firestore-Pfad: kunden/${getCompanyId()}/schichtplanSchichten`);

        if (mode === "edit" && id) {
          const ref = doc(getSchichtenDefinitionCollection(), id);
          console.log(`💾 Bearbeite Schicht mit ID: ${id}`);
          await setDoc(ref, { name, standortId: standortId.trim() }, { merge: true });
          console.log(`✅ Schicht erfolgreich aktualisiert`);
        } else {
          console.log(`💾 Erstelle neue Schicht mit order=${orderValue}`);
          const docRef = await addDoc(getSchichtenDefinitionCollection(), dataToSave);
          console.log(`✅ Schicht erfolgreich erstellt mit ID: ${docRef.id}`);
          console.log(`✅ Gespeicherte Daten:`, dataToSave);
          
          // Warte etwas länger, damit Firestore die Daten verarbeitet hat
          await new Promise(resolve => setTimeout(resolve, 500));
        }

        // Erst Stammdaten neu laden, dann Liste aktualisieren
        await loadSchichten(); // Stammdaten aktualisieren
        console.log(`✅ Stammdaten neu geladen - ${allSchichten.length} Schichten`);
        
        // Prüfe, ob die neue Schicht geladen wurde
        const newSchicht = allSchichten.find(s => 
          s.name === name && String(s.standortId).trim() === standortId.trim()
        );
        if (newSchicht) {
          console.log(`✅ Neue Schicht in Stammdaten gefunden: ${newSchicht.name} (ID: ${newSchicht.id})`);
        } else {
          console.warn(`⚠️ Neue Schicht nicht in Stammdaten gefunden! Gesucht: name="${name}", standortId="${standortId}"`);
        }
        
        await reloadSchichtenSettings(schichtenList);
        console.log(`✅ Schichten-Liste aktualisiert`);
        window.closeSchichtForm();
      } catch (e) {
        console.error("❌ Fehler beim Speichern der Schicht:", e);
        console.error("❌ Fehler-Details:", {
          message: e.message,
          code: e.code,
          stack: e.stack
        });
        alert("Fehler beim Speichern der Schicht: " + e.message);
      }
    });
  }

  // Mitarbeiter hinzufügen
  if (
    addMitarbeiterBtn &&
    mitarbeiterForm &&
    mitarbeiterVornameInput &&
    mitarbeiterNachnameInput &&
    mitarbeiterFormTitle &&
    saveMitarbeiterBtn
  ) {
    addMitarbeiterBtn.addEventListener("click", () => {
      mitarbeiterForm.dataset.mode = "create";
      mitarbeiterForm.dataset.id = "";
      mitarbeiterFormTitle.textContent = "Mitarbeiter hinzufügen";
      mitarbeiterVornameInput.value = "";
      mitarbeiterNachnameInput.value = "";
      if (mitarbeiterFuehrerscheinInput) mitarbeiterFuehrerscheinInput.value = "";
      if (mitarbeiterTelefonInput) mitarbeiterTelefonInput.value = "";

      if (mitarbeiterQualifikationenContainer) {
        // Alle Checkboxen zurücksetzen
        mitarbeiterQualifikationenContainer
          .querySelectorAll("input.qualification-checkbox")
          .forEach((cb) => (cb.checked = false));
      }

      const ov = document.getElementById("mitarbeiterFormOverlay");
      if (ov) ov.style.display = "block";
      mitarbeiterForm.style.display = "block";
    });

    saveMitarbeiterBtn.addEventListener("click", async () => {
      const vorname = (mitarbeiterVornameInput.value || "").trim();
      const nachname = (mitarbeiterNachnameInput.value || "").trim();
      if (!vorname || !nachname) {
        alert("Bitte Vor- und Nachnamen eingeben.");
        return;
      }

      // Prüfe auf Doppelte (nur bei Erstellung, nicht bei Bearbeitung)
      const mode = mitarbeiterForm.dataset.mode || "create";
      const id = mitarbeiterForm.dataset.id;
      
      if (mode === "create") {
        // Lade aktuelle Mitarbeiter, falls noch nicht geladen
        if (!allMitarbeiter || allMitarbeiter.length === 0) {
          await loadMitarbeiter();
        }
        
        // Prüfe, ob bereits ein Mitarbeiter mit gleichem Vor- und Nachnamen existiert
        const duplicate = allMitarbeiter.find(m => 
          m.vorname && m.nachname &&
          m.vorname.toLowerCase().trim() === vorname.toLowerCase() &&
          m.nachname.toLowerCase().trim() === nachname.toLowerCase()
        );
        
        if (duplicate) {
          alert(`Ein Mitarbeiter mit dem Namen "${vorname} ${nachname}" existiert bereits. Doppelte Einträge sind nicht erlaubt.`);
          return;
        }
      }

      // Nur eine Qualifikation möglich (Checkbox mit Radio-Button-Verhalten)
      const qualis = [];
      if (mitarbeiterQualifikationenContainer) {
        const selectedCheckbox = mitarbeiterQualifikationenContainer.querySelector("input.qualification-checkbox:checked");
        if (selectedCheckbox) {
          qualis.push(selectedCheckbox.value);
        }
      }

      const fuehrerschein = mitarbeiterFuehrerscheinInput
        ? mitarbeiterFuehrerscheinInput.value.trim()
        : "";
      const telefonnummer = mitarbeiterTelefonInput ? mitarbeiterTelefonInput.value.trim() : "";

      try {
        const payload = {
          vorname,
          nachname,
          qualifikation: qualis,
          fuehrerschein,
          telefonnummer,
          active: true,
        };

        if (mode === "edit" && id) {
          const ref = doc(getMitarbeiterCollection(), id);
          await setDoc(ref, payload, { merge: true });
          
          // Live-Aktualisierung: Aktualisiere alle Schichten und Bereitschaften, wo dieser Mitarbeiter zugewiesen ist
          await updateMitarbeiterInAllShifts(id, payload);
          
        } else {
          await addDoc(getMitarbeiterCollection(), payload);
        }

        // Suchfeld beibehalten beim Neuladen
        const searchInput = document.getElementById("mitarbeiterSearchInput");
        const searchTerm = searchInput ? searchInput.value : "";
        await reloadMitarbeiterSettings(mitarbeiterList, searchTerm);
        window.closeMitarbeiterForm();
        await loadMitarbeiter(); // Stammdaten aktualisieren
        
        // Kalender aktualisieren, damit die rote/grüne Anzeige der Tage aktualisiert wird
        // Aktualisiere alle Tage des aktuellen und nächsten Monats (die in updateMitarbeiterInAllShifts bearbeitet wurden)
        await renderCalendar();
      } catch (e) {
        console.error("Fehler beim Speichern des Mitarbeiters:", e);
        alert("Fehler beim Speichern des Mitarbeiters: " + e.message);
      }
    });
  }

  // Bereitschafts-Typ hinzufügen
  if (
    addBereitschaftsTypBtn &&
    bereitschaftsTypForm &&
    bereitschaftsTypNameInput &&
    bereitschaftsTypFormTitle &&
    saveBereitschaftsTypBtn
  ) {
    addBereitschaftsTypBtn.addEventListener("click", () => {
      bereitschaftsTypForm.dataset.mode = "create";
      bereitschaftsTypForm.dataset.id = "";
      bereitschaftsTypFormTitle.textContent = "Bereitschafts-Typ hinzufügen";
      bereitschaftsTypNameInput.value = "";
      if (bereitschaftsTypBeschreibungInput) bereitschaftsTypBeschreibungInput.value = "";

      const ov = document.getElementById("bereitschaftsTypFormOverlay");
      if (ov) ov.style.display = "block";
      bereitschaftsTypForm.style.display = "block";
    });

    saveBereitschaftsTypBtn.addEventListener("click", async () => {
      const name = (bereitschaftsTypNameInput.value || "").trim();
      const beschreibung = bereitschaftsTypBeschreibungInput
        ? bereitschaftsTypBeschreibungInput.value.trim()
        : "";
      if (!name) {
        alert("Bitte einen Namen für den Bereitschafts-Typ eingeben.");
        return;
      }

      try {
        const mode = bereitschaftsTypForm.dataset.mode || "create";
        const id = bereitschaftsTypForm.dataset.id;

        const payload = {
          name,
          beschreibung,
          active: true,
        };

        if (mode === "edit" && id) {
          const ref = doc(getBereitschaftsTypenCollection(), id);
          await setDoc(ref, payload, { merge: true });
        } else {
          await addDoc(getBereitschaftsTypenCollection(), payload);
        }

        await reloadBereitschaftsTypenSettings(bereitschaftsTypenList);
        window.closeBereitschaftsTypForm();
      } catch (e) {
        console.error("Fehler beim Speichern des Bereitschafts-Typs:", e);
        alert("Fehler beim Speichern des Bereitschafts-Typs: " + e.message);
      }
    });
  }
}

window.closeSettingsPopup = function () {
  if (settingsPopupOverlay) settingsPopupOverlay.style.display = "none";
  if (settingsPopupForm) settingsPopupForm.style.display = "none";
};

// Hilfsfunktionen zum Rendern der Einstellungslisten

async function reloadStandorteSettings(standorteList, schichtStandortSelect) {
  try {
    await loadStandorte();
    if (standorteList) {
      standorteList.innerHTML = "";
      allStandorte.forEach((s, index) => {
        const row = document.createElement("div");
        row.className = "settings-item draggable-standort-item";
        row.draggable = true;
        row.dataset.standortId = s.id;
        row.dataset.order = s.order || index;

        const dragHandle = document.createElement("div");
        dragHandle.className = "drag-handle";
        dragHandle.innerHTML = "☰";
        dragHandle.title = "Ziehen zum Anordnen (Long Press auf Touch-Geräten)";

        const label = document.createElement("div");
        label.textContent = s.name || s.id;

        const actions = document.createElement("div");
        actions.className = "settings-item-actions";

        const editBtn = document.createElement("button");
        editBtn.className = "btn-small";
        editBtn.title = "Standort bearbeiten";
        editBtn.textContent = "✏️";
        editBtn.addEventListener("click", () => {
          const standortForm = document.getElementById("standortForm");
          const standortFormTitle = document.getElementById("standortFormTitle");
          const standortNameInput = document.getElementById("standortName");
          const ov = document.getElementById("standortFormOverlay");
          if (!standortForm || !standortFormTitle || !standortNameInput || !ov) return;
          standortForm.dataset.mode = "edit";
          standortForm.dataset.id = s.id;
          standortFormTitle.textContent = "Standort bearbeiten";
          standortNameInput.value = s.name || "";
          ov.style.display = "block";
          standortForm.style.display = "block";
        });

        const deleteBtn = document.createElement("button");
        deleteBtn.className = "btn-small btn-danger";
        deleteBtn.title = "Standort löschen";
      deleteBtn.innerHTML = getTrashIconSVG("#ffffff");  // Settings haben weißen Hintergrund
        deleteBtn.addEventListener("click", async () => {
          if (!confirm("Diesen Standort wirklich löschen? Zukünftige Schichten werden gelöscht, vergangene bleiben erhalten.")) return;
          try {
            await deleteStandortWithHistoryPreservation(s.id);
            await reloadStandorteSettings(standorteList, schichtStandortSelect);
            await loadStandorte();
          } catch (e) {
            console.error("Fehler beim Löschen des Standorts:", e);
            alert("Fehler beim Löschen des Standorts: " + e.message);
          }
        });

        actions.appendChild(editBtn);
        actions.appendChild(deleteBtn);

        row.appendChild(dragHandle);
        row.appendChild(label);
        row.appendChild(actions);
        standorteList.appendChild(row);
      });
      
      // Drag & Drop Handler hinzufügen
      setupStandortDragAndDrop(standorteList, schichtStandortSelect);
    }
      if (schichtStandortSelect) {
        schichtStandortSelect.innerHTML = '<option value=\"\">-- Bitte auswählen --</option>';
        allStandorte.forEach((s) => {
        const opt = document.createElement("option");
        opt.value = s.id;
        opt.textContent = s.name || s.id;
        schichtStandortSelect.appendChild(opt);
      });
    }
  } catch (e) {
    console.error("Fehler beim Laden der Standorte für Einstellungen:", e);
  }
}

// Drag & Drop für Standorte
function setupStandortDragAndDrop(standorteList, schichtStandortSelect) {
  if (!standorteList) return;
  
  let draggedElement = null;
  let draggedIndex = -1;
  let longPressTimer = null;
  
  // Helper-Funktion zum Aktualisieren der Items-Liste
  const getItems = () => standorteList.querySelectorAll(".draggable-standort-item");
  
  let items = getItems();
  
  items.forEach((item, index) => {
    // Maus-Drag-Events (Desktop)
    item.addEventListener("dragstart", (e) => {
      draggedElement = item;
      draggedIndex = index;
      item.classList.add("dragging");
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/html", item.outerHTML);
    });
    
    item.addEventListener("dragend", (e) => {
      item.classList.remove("dragging");
      items.forEach(i => i.classList.remove("drag-over"));
    });
    
    item.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (item !== draggedElement) {
        item.classList.add("drag-over");
      }
    });
    
    item.addEventListener("dragleave", (e) => {
      item.classList.remove("drag-over");
    });
    
    item.addEventListener("drop", async (e) => {
      e.preventDefault();
      item.classList.remove("drag-over");
      
      if (draggedElement && draggedElement !== item) {
        // Items-Liste neu abrufen, da sich die DOM-Struktur geändert haben könnte
        items = getItems();
        const currentDraggedIndex = Array.from(items).indexOf(draggedElement);
        const dropIndex = Array.from(items).indexOf(item);
        
        if (currentDraggedIndex !== -1 && dropIndex !== -1 && currentDraggedIndex !== dropIndex) {
          // DOM-Elemente neu anordnen
          if (currentDraggedIndex < dropIndex) {
            standorteList.insertBefore(draggedElement, item.nextSibling);
          } else {
            standorteList.insertBefore(draggedElement, item);
          }
          
          // Order-Werte in Firestore aktualisieren
          await updateStandortOrder(standorteList, schichtStandortSelect);
        }
      }
      
      draggedElement = null;
      draggedIndex = -1;
    });
    
    // Touch-Events für Mobile (Long Press)
    let touchStartY = 0;
    let touchStartX = 0;
    let touchStartTime = 0;
    let isDragging = false;
    
    item.addEventListener("touchstart", (e) => {
      touchStartY = e.touches[0].clientY;
      touchStartX = e.touches[0].clientX;
      touchStartTime = Date.now();
      isDragging = false;
      longPressTimer = setTimeout(() => {
        draggedElement = item;
        draggedIndex = Array.from(getItems()).indexOf(item);
        isDragging = true;
        item.classList.add("dragging");
        // Vibrate auf unterstützten Geräten
        if (navigator.vibrate) navigator.vibrate(50);
        console.log("🔵 Long Press aktiviert für Standort:", item.dataset.standortId);
      }, 300);
    }, { passive: true });
    
    item.addEventListener("touchmove", (e) => {
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
      
      // Prüfe ob Long Press aktiv war und wir jetzt ziehen
      if (isDragging && draggedElement && draggedElement === item) {
        e.preventDefault();
        e.stopPropagation();
        const touchY = e.touches[0].clientY;
        const touchX = e.touches[0].clientX;
        
        // Items-Liste neu abrufen
        items = getItems();
        
        // Finde alle Items und deren Positionen
        items.forEach(i => {
          i.classList.remove("drag-over");
          if (i !== draggedElement) {
            const rect = i.getBoundingClientRect();
            // Prüfe ob Touch-Position innerhalb dieses Items ist
            if (touchY >= rect.top && touchY <= rect.bottom && 
                touchX >= rect.left && touchX <= rect.right) {
              i.classList.add("drag-over");
            }
          }
        });
      } else {
        // Wenn nur kurz bewegt wurde (kein Drag), Timer löschen
        const deltaY = Math.abs(e.touches[0].clientY - touchStartY);
        if (deltaY > 10) {
          clearTimeout(longPressTimer);
          longPressTimer = null;
        }
      }
    }, { passive: false });
    
    item.addEventListener("touchend", async (e) => {
      // Timer löschen falls noch aktiv
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
        // Wenn nur kurz gedrückt wurde (kein Drag), nichts tun
        return;
      }
      
      // Nur verarbeiten wenn wir tatsächlich gezogen haben
      if (isDragging && draggedElement && draggedElement === item) {
        e.preventDefault();
        e.stopPropagation();
        
        const touchY = e.changedTouches[0].clientY;
        const touchX = e.changedTouches[0].clientX;
        
        console.log("🟢 Touch End - Suche Ziel-Position bei:", touchX, touchY);
        
        // Items-Liste neu abrufen
        items = getItems();
        const currentDraggedIndex = Array.from(items).indexOf(draggedElement);
        
        console.log("📍 Aktueller Index des gezogenen Elements:", currentDraggedIndex);
        
        // Finde das Element, über dem wir losgelassen haben
        let targetItem = null;
        let minDistance = Infinity;
        
        items.forEach(i => {
          if (i !== draggedElement) {
            const rect = i.getBoundingClientRect();
            const centerY = rect.top + rect.height / 2;
            const distance = Math.abs(touchY - centerY);
            
            // Prüfe ob Touch-Position innerhalb dieses Items ist (bevorzugt)
            if (touchY >= rect.top && touchY <= rect.bottom) {
              // Wenn mehrere Items überlappen, nimm das mit der geringsten Distanz
              if (!targetItem || distance < minDistance) {
                minDistance = distance;
                targetItem = i;
              }
            } else {
              // Falls kein Item direkt getroffen, suche das nächste basierend auf Distanz
              if (!targetItem && distance < minDistance) {
                minDistance = distance;
                targetItem = i;
              }
            }
          }
        });
        
        items.forEach(i => i.classList.remove("drag-over"));
        
        if (targetItem && targetItem !== draggedElement && currentDraggedIndex !== -1) {
          const dropIndex = Array.from(items).indexOf(targetItem);
          console.log("🎯 Ziel-Index:", dropIndex, "Aktueller Index:", currentDraggedIndex);
          
          if (dropIndex !== -1 && currentDraggedIndex !== dropIndex) {
            // DOM-Elemente neu anordnen
            // Wenn nach unten (dropIndex > currentDraggedIndex): nach dem Ziel einfügen
            // Wenn nach oben (dropIndex < currentDraggedIndex): vor dem Ziel einfügen
            if (currentDraggedIndex < dropIndex) {
              // Nach unten: nach dem Ziel-Element einfügen
              standorteList.insertBefore(draggedElement, targetItem.nextSibling);
            } else {
              // Nach oben: vor dem Ziel-Element einfügen
              standorteList.insertBefore(draggedElement, targetItem);
            }
            
            console.log("✅ Element verschoben von Index", currentDraggedIndex, "zu", dropIndex);
            
            // Order-Werte in Firestore aktualisieren
            await updateStandortOrder(standorteList, schichtStandortSelect);
          } else {
            console.log("⚠️ Keine Änderung nötig (gleicher Index)");
          }
        } else {
          console.log("⚠️ Kein gültiges Ziel gefunden. targetItem:", !!targetItem, "draggedElement:", !!draggedElement, "currentIndex:", currentDraggedIndex);
        }
        
        draggedElement.classList.remove("dragging");
        draggedElement = null;
        draggedIndex = -1;
        isDragging = false;
      }
    }, { passive: false });
    
    item.addEventListener("touchcancel", () => {
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
      if (draggedElement) {
        draggedElement.classList.remove("dragging");
        items = getItems();
        items.forEach(i => i.classList.remove("drag-over"));
        draggedElement = null;
        draggedIndex = -1;
        isDragging = false;
      }
    });
  });
}

// Standort löschen mit Erhaltung der historischen Schichten
async function deleteStandortWithHistoryPreservation(standortId) {
  try {
    const standort = allStandorte.find(s => s.id === standortId) || 
                     allStandorteIncludingDeleted.find(s => s.id === standortId);
    if (!standort) {
      throw new Error("Standort nicht gefunden");
    }
    
    // Aktuelles Datum als Referenzpunkt (WICHTIG: Tag der Löschung)
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    
    console.log(`🗑️ Lösche Standort ${standortId} (Name: ${standort.name})`);
    console.log(`📅 Löschdatum: ${todayStr}`);
    console.log(`✅ ALLE Tage VOR ${todayStr} bleiben KOMPLETT erhalten`);
    console.log(`❌ Tage AB ${todayStr} (inklusive) werden gelöscht`);
    
    // Lade alle Tage für diesen Standort
    const companyId = getCompanyId();
    const tageCollection = collection(db, "kunden", companyId, "schichtplan", standortId, "tage");
    const tageSnapshot = await getDocs(tageCollection);
    
    console.log(`📊 Gefundene Tage für Standort: ${tageSnapshot.docs.length}`);
    
    let deletedFutureDays = 0;
    let preservedPastDays = 0;
    
    // WICHTIG: Lösche NUR Tage >= heute (inklusive heute), alle Tage VOR heute bleiben KOMPLETT erhalten
    for (const tagDoc of tageSnapshot.docs) {
      const dayId = tagDoc.id;
      
      // Parse dayId zu Datum für exakten Vergleich (unterstützt verschiedene Formate)
      const dayDate = parseDayId(dayId);
      if (!dayDate || isNaN(dayDate.getTime())) {
        console.error(`❌ Ungültiges Datum in deleteStandortWithHistoryPreservation: ${dayId}, überspringe`);
        continue;
      }
      dayDate.setHours(0, 0, 0, 0);
      
      // Vergleich: dayDate < today bedeutet VERGANGEN -> BEHALTEN
      // dayDate >= today bedeutet HEUTE oder ZUKUNFT -> LÖSCHEN
      if (dayDate < today) {
        // VERGANGENER Tag (vor heute) - KOMPLETT BEHALTEN, NICHTS löschen!
        console.log(`  ✅ BEHALTEN: ${dayId} (vor ${todayStr}) - Schichten + Bereitschaften bleiben unverändert`);
        preservedPastDays++;
        // EXPLIZIT NICHTS TUN - dieser Tag bleibt komplett erhalten
        continue; // Überspringe diesen Tag komplett
      }
      
      // Tag ist HEUTE oder ZUKUNFTIG (>= today) -> LÖSCHEN
      console.log(`  ❌ LÖSCHE: ${dayId} (${dayDate >= today ? "ab heute" : "zukünftig"})`);
      
      const schichtenCollection = getShiftsCollection(standortId, dayId);
      const bereitschaftenCollection = getBereitschaftenCollection(standortId, dayId);
      
      // Lösche alle Schichten dieses Tages
      const schichtenSnapshot = await getDocs(schichtenCollection);
      let deletedShifts = 0;
      for (const schichtDoc of schichtenSnapshot.docs) {
        await deleteDoc(schichtDoc.ref);
        deletedShifts++;
      }
      
      // Lösche alle Bereitschaften dieses Tages
      const bereitschaftenSnapshot = await getDocs(bereitschaftenCollection);
      let deletedBereitschaften = 0;
      for (const bereitschaftDoc of bereitschaftenSnapshot.docs) {
        await deleteDoc(bereitschaftDoc.ref);
        deletedBereitschaften++;
      }
      
      // Lösche das Tage-Dokument selbst (wenn leer oder nach dem Löschen der Subcollections)
      await deleteDoc(tagDoc.ref);
      
      console.log(`     → ${deletedShifts} Schichten, ${deletedBereitschaften} Bereitschaften gelöscht`);
      deletedFutureDays++;
    }
    
    // WICHTIG: Standort NICHT komplett löschen, sondern nur als gelöscht markieren!
    // So bleiben vergangene Schichten sichtbar und zugänglich
    await setDoc(doc(getStandorteCollection(), standortId), { 
      active: false, 
      deleted: true,
      deletedAt: todayStr, // Speichere Löschdatum für Referenz
      name: standort.name // Name beibehalten für historische Anzeige
    }, { merge: true });
    
    console.log(`✅ Standort als gelöscht markiert (nicht komplett gelöscht)`);
    console.log(`   📦 ${preservedPastDays} vergangene Tage KOMPLETT erhalten (Schichten + Bereitschaften unverändert)`);
    console.log(`   🗑️ ${deletedFutureDays} zukünftige Tage (ab ${todayStr}) gelöscht`);
  } catch (e) {
    console.error("❌ Fehler beim Löschen des Standorts mit Historie:", e);
    alert("Fehler beim Löschen des Standorts: " + e.message);
    throw e;
  }
}

// Standort-Namen ändern mit Erhaltung der historischen Schichten
async function updateStandortNameWithHistoryPreservation(standortId, oldName, newName) {
  try {
    // Aktuelles Datum als Referenzpunkt
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    
    console.log(`✏️ Aktualisiere Standort-Name von "${oldName}" zu "${newName}" ab ${todayStr}`);
    
    // Lade alle Tage für diesen Standort
    const companyId = getCompanyId();
    const tageCollection = collection(db, "kunden", companyId, "schichtplan", standortId, "tage");
    const tageSnapshot = await getDocs(tageCollection);
    
    let updatedFutureDays = 0;
    let preservedPastDays = 0;
    
    // Aktualisiere nur zukünftige Tage (ab heute)
    for (const tagDoc of tageSnapshot.docs) {
      const dayId = tagDoc.id;
      
      // Vergleiche Datum: dayId ist im Format "YYYY-MM-DD"
      if (dayId >= todayStr) {
        // Zukünftiger Tag - Name in Schichten aktualisieren (falls gespeichert)
        const schichtenCollection = getShiftsCollection(standortId, dayId);
        const schichtenSnapshot = await getDocs(schichtenCollection);
        
        const updates = [];
        schichtenSnapshot.forEach((schichtDoc) => {
          const data = schichtDoc.data();
          if (data.standortName === oldName) {
            updates.push(setDoc(schichtDoc.ref, { standortName: newName }, { merge: true }));
          }
        });
        
        await Promise.all(updates);
        updatedFutureDays++;
      } else {
        // Vergangener Tag - unverändert lassen
        preservedPastDays++;
      }
    }
    
    console.log(`✅ Standort-Name aktualisiert: ${preservedPastDays} vergangene Tage unverändert, ${updatedFutureDays} zukünftige Tage aktualisiert`);
  } catch (e) {
    console.error("❌ Fehler beim Aktualisieren des Standort-Namens mit Historie:", e);
    throw e;
  }
}

// Order-Werte nach Drag & Drop aktualisieren
async function updateStandortOrder(standorteList, schichtStandortSelect) {
  try {
    const items = standorteList.querySelectorAll(".draggable-standort-item");
    const updates = [];
    
    items.forEach((item, index) => {
      const standortId = item.dataset.standortId;
      const newOrder = index + 1;
      updates.push({
        ref: doc(getStandorteCollection(), standortId),
        order: newOrder
      });
    });
    
    // Alle Updates parallel ausführen
    await Promise.all(updates.map(({ ref, order }) => 
      setDoc(ref, { order }, { merge: true })
    ));
    
    console.log("✅ Standort-Reihenfolge aktualisiert");
    
    // Liste neu laden
    await reloadStandorteSettings(standorteList, schichtStandortSelect);
    await loadStandorte();
  } catch (e) {
    console.error("❌ Fehler beim Aktualisieren der Standort-Reihenfolge:", e);
    alert("Fehler beim Aktualisieren der Reihenfolge: " + e.message);
  }
}

async function reloadSchichtenSettings(schichtenList) {
  if (!schichtenList) return;
  try {
    // Lade Schichten neu, falls noch nicht geladen
    if (!allSchichten || allSchichten.length === 0) {
      await loadSchichten();
    }
    
    console.log(`📋 reloadSchichtenSettings: ${allSchichten.length} Schichten geladen`);
    allSchichten.forEach((s) => {
      console.log(`  - ${s.name} (standortId: "${s.standortId}", ID: ${s.id}, active: ${s.active})`);
    });
    
    // Sortiere Schichten: zuerst nach Standortname (alphabetisch), dann nach Schichtname (alphabetisch)
    const sortedSchichten = [...allSchichten].sort((a, b) => {
      const standortA = allStandorte.find(st => st.id === a.standortId);
      const standortB = allStandorte.find(st => st.id === b.standortId);
      const standortNameA = standortA ? standortA.name : (a.standortId || "");
      const standortNameB = standortB ? standortB.name : (b.standortId || "");
      
      // Zuerst nach Standortname sortieren
      const standortCompare = standortNameA.localeCompare(standortNameB, 'de', { sensitivity: 'base' });
      if (standortCompare !== 0) return standortCompare;
      
      // Bei gleichem Standort nach Schichtname sortieren
      const nameA = a.name || "";
      const nameB = b.name || "";
      return nameA.localeCompare(nameB, 'de', { sensitivity: 'base' });
    });
    
    schichtenList.innerHTML = "";
    sortedSchichten.forEach((s) => {
      const row = document.createElement("div");
      row.className = "settings-item";

      const label = document.createElement("div");
      const standort = allStandorte.find((st) => st.id === s.standortId);
      label.textContent = `${s.name || s.id} (${standort ? standort.name : "ohne Standort"})`;

      const actions = document.createElement("div");
      actions.className = "settings-item-actions";

      const editBtn = document.createElement("button");
      editBtn.className = "btn-small";
      editBtn.title = "Schicht bearbeiten";
      editBtn.textContent = "✏️";
      editBtn.addEventListener("click", async () => {
        const schichtForm = document.getElementById("schichtForm");
        const schichtFormTitle = document.getElementById("schichtFormTitle");
        const schichtNameInput = document.getElementById("schichtName");
        const schichtStandortSelect = document.getElementById("schichtStandort");
        const ov = document.getElementById("schichtFormOverlay");
        if (!schichtForm || !schichtFormTitle || !schichtNameInput || !schichtStandortSelect || !ov)
          return;

        schichtForm.dataset.mode = "edit";
        schichtForm.dataset.id = s.id;
        schichtFormTitle.textContent = "Schicht bearbeiten";
        schichtNameInput.value = s.name || "";

        // Standorte ins Dropdown laden und aktuellen auswählen
        await reloadStandorteSettings(null, schichtStandortSelect);
        schichtStandortSelect.value = s.standortId || "";

        ov.style.display = "block";
        schichtForm.style.display = "block";
      });

      const deleteBtn = document.createElement("button");
      deleteBtn.className = "btn-small btn-danger";
      deleteBtn.title = "Schicht löschen";
      deleteBtn.innerHTML = getTrashIconSVG("#ffffff");  // Settings haben weißen Hintergrund
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Diese Schicht wirklich löschen?")) return;
        try {
          await deleteDoc(doc(getSchichtenDefinitionCollection(), s.id));
          await reloadSchichtenSettings(schichtenList);
          await loadSchichten();
        } catch (e) {
          console.error("Fehler beim Löschen der Schicht:", e);
          alert("Fehler beim Löschen der Schicht: " + e.message);
        }
      });

      actions.appendChild(editBtn);
      actions.appendChild(deleteBtn);

      row.appendChild(label);
      row.appendChild(actions);
      schichtenList.appendChild(row);
    });
  } catch (e) {
    console.error("Fehler beim Laden der Schichten für Einstellungen:", e);
  }
}

async function reloadMitarbeiterSettings(mitarbeiterList, searchTerm = "") {
  if (!mitarbeiterList) return;
  try {
    await loadMitarbeiter();
    
    // Sortiere Mitarbeiter alphabetisch: zuerst nach Nachname, dann nach Vorname
    const sortedMitarbeiter = [...allMitarbeiter].sort((a, b) => {
      const nachnameA = (a.nachname || "").toLowerCase();
      const nachnameB = (b.nachname || "").toLowerCase();
      const nachnameCompare = nachnameA.localeCompare(nachnameB, 'de', { sensitivity: 'base' });
      if (nachnameCompare !== 0) return nachnameCompare;
      
      // Bei gleichem Nachname nach Vorname sortieren
      const vornameA = (a.vorname || "").toLowerCase();
      const vornameB = (b.vorname || "").toLowerCase();
      return vornameA.localeCompare(vornameB, 'de', { sensitivity: 'base' });
    });
    
    // Filtere nach Suchbegriff (falls vorhanden)
    const searchLower = searchTerm ? searchTerm.toLowerCase().trim() : "";
    const filteredMitarbeiter = searchLower 
      ? sortedMitarbeiter.filter(m => {
          const fullName = `${m.vorname || ""} ${m.nachname || ""}`.toLowerCase();
          const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(" ").toLowerCase() : "";
          const result = fullName.includes(searchLower) || qualis.includes(searchLower);
          return result;
        })
      : sortedMitarbeiter;
    
    console.log(`🔍 Gefilterte Mitarbeiter: ${filteredMitarbeiter.length} von ${sortedMitarbeiter.length} (Suchbegriff: "${searchTerm}")`);
    
    mitarbeiterList.innerHTML = "";
    filteredMitarbeiter.forEach((m) => {
      const row = document.createElement("div");
      row.className = "settings-item mitarbeiter-settings-item";
      const label = document.createElement("div");
      // Nur Name anzeigen, Qualifikation ist bereits im Namen enthalten (wird später ergänzt)
      label.textContent = `${m.nachname}, ${m.vorname}`;

      const actions = document.createElement("div");
      actions.className = "settings-item-actions";

      const editBtn = document.createElement("button");
      editBtn.className = "btn-small";
      editBtn.title = "Mitarbeiter bearbeiten";
      editBtn.textContent = "✏️";
      editBtn.addEventListener("click", () => {
        const mitarbeiterForm = document.getElementById("mitarbeiterForm");
        const mitarbeiterFormTitle = document.getElementById("mitarbeiterFormTitle");
        const mitarbeiterVornameInput = document.getElementById("mitarbeiterVorname");
        const mitarbeiterNachnameInput = document.getElementById("mitarbeiterNachname");
        const mitarbeiterFuehrerscheinInput = document.getElementById("mitarbeiterFuehrerschein");
        const mitarbeiterTelefonInput = document.getElementById("mitarbeiterTelefon");
        const qualisContainer = document.getElementById("mitarbeiterQualifikationen");
        const ov = document.getElementById("mitarbeiterFormOverlay");
        if (
          !mitarbeiterForm ||
          !mitarbeiterFormTitle ||
          !mitarbeiterVornameInput ||
          !mitarbeiterNachnameInput ||
          !qualisContainer ||
          !ov
        )
          return;

        mitarbeiterForm.dataset.mode = "edit";
        mitarbeiterForm.dataset.id = m.id;
        mitarbeiterFormTitle.textContent = "Mitarbeiter bearbeiten";
        mitarbeiterVornameInput.value = m.vorname || "";
        mitarbeiterNachnameInput.value = m.nachname || "";
        if (mitarbeiterFuehrerscheinInput) mitarbeiterFuehrerscheinInput.value = m.fuehrerschein || "";
        if (mitarbeiterTelefonInput) mitarbeiterTelefonInput.value = m.telefonnummer || "";

        // Qualifikation setzen (nur die erste, da nur eine ausgewählt werden kann)
        const currentQualis = Array.isArray(m.qualifikation) ? m.qualifikation : [];
        const firstQuali = currentQualis.length > 0 ? currentQualis[0] : null;
        qualisContainer
          .querySelectorAll("input.qualification-checkbox")
          .forEach((cb) => {
            cb.checked = cb.value === firstQuali;
          });

        ov.style.display = "block";
        mitarbeiterForm.style.display = "block";
      });

      const deleteBtn = document.createElement("button");
      deleteBtn.className = "btn-small btn-danger";
      deleteBtn.title = "Mitarbeiter löschen";
      deleteBtn.innerHTML = getTrashIconSVG("#ffffff");  // Settings haben weißen Hintergrund
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Diesen Mitarbeiter wirklich löschen?")) return;
        try {
          await deleteDoc(doc(getMitarbeiterCollection(), m.id));
          const searchInput = document.getElementById("mitarbeiterSearchInput");
          const searchTerm = searchInput ? searchInput.value : "";
          await reloadMitarbeiterSettings(mitarbeiterList, searchTerm);
          await loadMitarbeiter();
        } catch (e) {
          console.error("Fehler beim Löschen des Mitarbeiters:", e);
          alert("Fehler beim Löschen des Mitarbeiters: " + e.message);
        }
      });

      actions.appendChild(editBtn);
      actions.appendChild(deleteBtn);

      row.appendChild(label);
      row.appendChild(actions);
      mitarbeiterList.appendChild(row);

      // Rechtsklick: Datenblatt anzeigen, Kontextmenü unterdrücken
      row.addEventListener("contextmenu", (ev) => {
        ev.preventDefault();
        openMitarbeiterDatenblatt(m.id);
      });

      // Long-Press auf Touch-Geräten: Datenblatt anzeigen, ohne Copy-Menü
      let longPressTimer = null;
      row.addEventListener("touchstart", (ev) => {
        ev.preventDefault();
        ev.stopPropagation();
        // Copy-Menü unterdrücken
        if (ev.target) {
          ev.target.style.webkitTouchCallout = "none";
          ev.target.style.webkitUserSelect = "none";
          ev.target.style.userSelect = "none";
        }
        longPressTimer = window.setTimeout(() => {
          openMitarbeiterDatenblatt(m.id);
        }, 600);
      });
      ["touchend", "touchcancel", "touchmove"].forEach((evtName) => {
        row.addEventListener(evtName, () => {
          if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
          }
        });
      });
    });
  } catch (e) {
    console.error("Fehler beim Laden der Mitarbeiter für Einstellungen:", e);
  }
}

async function reloadBereitschaftsTypenSettings(bereitschaftsTypenList) {
  if (!bereitschaftsTypenList) return;
  try {
    const snap = await getDocs(query(getBereitschaftsTypenCollection(), orderBy("name", "asc")));
    bereitschaftsTypenList.innerHTML = "";
    snap.forEach((docSnap) => {
      const data = docSnap.data() || {};
      const row = document.createElement("div");
      row.className = "settings-item";
      const beschr = data.beschreibung ? ` – ${data.beschreibung}` : "";

      const label = document.createElement("div");
      label.textContent = `${data.name || docSnap.id}${beschr}`;

      const actions = document.createElement("div");
      actions.className = "settings-item-actions";

      const editBtn = document.createElement("button");
      editBtn.className = "btn-small";
      editBtn.title = "Bereitschafts-Typ bearbeiten";
      editBtn.textContent = "✏️";
      editBtn.addEventListener("click", () => {
        const form = document.getElementById("bereitschaftsTypForm");
        const formTitle = document.getElementById("bereitschaftsTypFormTitle");
        const nameInput = document.getElementById("bereitschaftsTypName");
        const beschreibungInput = document.getElementById("bereitschaftsTypBeschreibung");
        const ov = document.getElementById("bereitschaftsTypFormOverlay");
        if (!form || !formTitle || !nameInput || !ov) return;

        form.dataset.mode = "edit";
        form.dataset.id = docSnap.id;
        formTitle.textContent = "Bereitschafts-Typ bearbeiten";
        nameInput.value = data.name || "";
        if (beschreibungInput) beschreibungInput.value = data.beschreibung || "";

        ov.style.display = "block";
        form.style.display = "block";
      });

      const deleteBtn = document.createElement("button");
      deleteBtn.className = "btn-small btn-danger";
      deleteBtn.title = "Bereitschafts-Typ löschen";
      deleteBtn.innerHTML = getTrashIconSVG("#ffffff");  // Settings haben weißen Hintergrund
      deleteBtn.addEventListener("click", async () => {
        if (!confirm("Diesen Bereitschafts-Typ wirklich löschen?")) return;
        try {
          await deleteDoc(doc(getBereitschaftsTypenCollection(), docSnap.id));
          await reloadBereitschaftsTypenSettings(bereitschaftsTypenList);
        } catch (e) {
          console.error("Fehler beim Löschen des Bereitschafts-Typs:", e);
          alert("Fehler beim Löschen des Bereitschafts-Typs: " + e.message);
        }
      });

      actions.appendChild(editBtn);
      actions.appendChild(deleteBtn);

      row.appendChild(label);
      row.appendChild(actions);
      bereitschaftsTypenList.appendChild(row);
    });
  } catch (e) {
    console.error("Fehler beim Laden der Bereitschafts-Typen für Einstellungen:", e);
  }
}

// ---------------------------------------------------------
// Mitarbeiter-Datenblatt
// ---------------------------------------------------------

function openMitarbeiterDatenblatt(mitarbeiterId) {
  const overlay = document.getElementById("mitarbeiterDatenblattOverlay");
  const form = document.getElementById("mitarbeiterDatenblattForm");
  const content = document.getElementById("mitarbeiterDatenblattContent");
  if (!overlay || !form || !content) return;

  const m = allMitarbeiter.find((mm) => mm.id === mitarbeiterId);
  if (!m) {
    alert("Mitarbeiter nicht gefunden.");
    return;
  }

  const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(" / ") : "";
  const fuehrerschein = m.fuehrerschein || "-";
  const telefon = m.telefonnummer || "-";
  // Telefonnummer als tel: Link formatieren (Leerzeichen entfernen für tel: Schema)
  const telLink = telefon && telefon !== "-" ? telefon.replace(/\s+/g, "") : "";
  const telefonDisplay = telLink
    ? `<a href="tel:${telLink}" style="color: var(--primary-color); text-decoration: underline;">${telefon}</a>`
    : "-";

  content.innerHTML = `
    <div class="mitarbeiter-datenblatt">
      <h3>${m.vorname || ""} ${m.nachname || ""}</h3>
      <p><strong>Qualifikationen:</strong> ${qualis || "-"}</p>
      <p><strong>Führerschein:</strong> ${fuehrerschein}</p>
      <p><strong>Telefon:</strong> ${telefonDisplay}</p>
    </div>
  `;

  overlay.style.display = "block";
  form.style.display = "block";
}

// Mitarbeiter-Datenblatt von Bereitschaft aus öffnen (mit Schichtzuweisung)
async function openMitarbeiterDatenblattFromBereitschaft(dayId, bereitschaft) {
  const overlay = document.getElementById("mitarbeiterDatenblattOverlay");
  const form = document.getElementById("mitarbeiterDatenblattForm");
  const content = document.getElementById("mitarbeiterDatenblattContent");
  if (!overlay || !form || !content) return;

  if (!bereitschaft.mitarbeiterId) {
    alert("Fehler: Keine Mitarbeiter-ID in der Bereitschaft gefunden.");
    return;
  }

  const m = allMitarbeiter.find((mm) => mm.id === bereitschaft.mitarbeiterId);
  if (!m) {
    alert("Mitarbeiter nicht gefunden.");
    return;
  }

  try {
    // Alle offenen Slots sammeln (wie in assignBereitschaftToOpenShift)
    const offeneSlots = [];

    const standortPromises = allStandorte
      .filter((s) => s.active !== false)
      .map(async (standort) => {
        const dayRef = getDayDocRef(standort.id, dayId);
        const daySnap = await getDoc(dayRef);
        if (!daySnap.exists()) return;

        const shiftsCol = getShiftsCollection(standort.id, dayId);
        const snap = await getDocs(shiftsCol);
        snap.forEach((docSnap) => {
          const data = docSnap.data() || {};
          const shiftName = getShiftDisplayName(standort.id, docSnap.id, data);
          if (!data.personal1) {
            offeneSlots.push({
              standortId: standort.id,
              standortName: standort.name,
              shiftId: docSnap.id,
              shiftName,
              slotIndex: 1,
            });
          }
          if (!data.personal2) {
            offeneSlots.push({
              standortId: standort.id,
              standortName: standort.name,
              shiftId: docSnap.id,
              shiftName,
              slotIndex: 2,
            });
          }
        });
      });

    await Promise.all(standortPromises);

    const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(" / ") : "";
    const fuehrerschein = m.fuehrerschein || "-";
    const telefon = m.telefonnummer || "-";
    // Telefonnummer als tel: Link formatieren
    const telLink = telefon && telefon !== "-" ? telefon.replace(/\s+/g, "") : "";
    const telefonDisplay = telLink
      ? `<a href="tel:${telLink}" style="color: var(--primary-color); text-decoration: underline;">${telefon}</a>`
      : "-";

    let schichtzuweisungHTML = "";
    if (offeneSlots.length === 0) {
      schichtzuweisungHTML = '<p style="color: #64748b; font-style: italic;">Keine offenen Schicht-Slots an diesem Tag verfügbar.</p>';
    } else {
      schichtzuweisungHTML = `
        <hr style="margin: 20px 0; border: none; border-top: 1px solid var(--border-color);">
        <h4>Schichtzuweisung</h4>
        <label for="bereitschaftSchichtSelect">Bereitschaft einer Schicht zuordnen:</label>
        <select id="bereitschaftSchichtSelect" style="width: 100%; padding: 8px; margin-bottom: 15px; border-radius: 6px; border: 1px solid var(--border-color);">
          <option value="">-- Bitte Schicht auswählen --</option>
          ${offeneSlots
            .map(
              (slot, index) =>
                `<option value="${index}">${slot.standortName} – Schicht ${slot.shiftName || "ohne Namen"} – Personal ${slot.slotIndex}</option>`
            )
            .join("")}
        </select>
        <div class="form-actions">
          <button id="bereitschaftSchichtZuordnenBtn" style="padding: 10px 15px; background-color: var(--primary-color); color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: 600;">Zuordnen</button>
          <button onclick="closeMitarbeiterDatenblatt()" class="cancel-btn">Schließen</button>
        </div>
      `;
    }

    content.innerHTML = `
      <div class="mitarbeiter-datenblatt">
        <h3>${m.vorname || ""} ${m.nachname || ""}</h3>
        <p><strong>Qualifikationen:</strong> ${qualis || "-"}</p>
        <p><strong>Führerschein:</strong> ${fuehrerschein}</p>
        <p><strong>Telefon:</strong> ${telefonDisplay}</p>
        ${schichtzuweisungHTML}
      </div>
    `;

    // Zuordnen-Button Handler (wenn offene Slots vorhanden sind)
    if (offeneSlots.length > 0) {
      const zuordnenBtn = document.getElementById("bereitschaftSchichtZuordnenBtn");
      const select = document.getElementById("bereitschaftSchichtSelect");
      if (zuordnenBtn && select) {
        zuordnenBtn.addEventListener("click", async () => {
          const selectedIndex = parseInt(select.value, 10);
          if (isNaN(selectedIndex) || selectedIndex < 0 || selectedIndex >= offeneSlots.length) {
            alert("Bitte eine gültige Schicht auswählen.");
            return;
          }

          const ziel = offeneSlots[selectedIndex];

          // Mitarbeiter-Daten aus Bereitschaft übernehmen (immer Gelb für Bereitschaften)
          let qualis = [];
          if (Array.isArray(m.qualifikation)) {
            qualis = m.qualifikation;
          }

          const personalData = {
            mitarbeiterId: bereitschaft.mitarbeiterId,
            name: bereitschaft.name || (m ? `${m.vorname} ${m.nachname}` : ""),
            qualifikationen: qualis,
            farbe: "#ffef94", // Bereitschaften standardmäßig gelb
          };

          // Prüfe auf Doppelbelegung
          const existingAssignments = await checkMitarbeiterAlreadyAssigned(dayId, bereitschaft.mitarbeiterId, ziel.standortId, ziel.shiftId, ziel.slotIndex);
          if (existingAssignments.length > 0) {
            const shouldContinue = await showDoubleAssignmentWarning(personalData.name, existingAssignments);
            if (!shouldContinue) {
              return; // Abbruch
            }
          }

          try {
            // Schicht-Slot setzen
            const shiftsCol = getShiftsCollection(ziel.standortId, dayId);
            const ref = doc(shiftsCol, ziel.shiftId);
            const field = ziel.slotIndex === 1 ? "personal1" : "personal2";
            await setDoc(ref, { [field]: personalData }, { merge: true });

            // Bereitschaft löschen
            const bereitsCol = getBereitschaftenCollection(bereitschaft.standortId, dayId);
            await deleteDoc(doc(bereitsCol, bereitschaft.id));

            closeMitarbeiterDatenblatt();
            await showCalendarDayDetails(dayId);
          } catch (err) {
            console.error("Fehler beim Zuordnen der Bereitschaft:", err);
            alert("Fehler beim Zuordnen der Bereitschaft. Details siehe Konsole.");
          }
        });
      }
    }

    overlay.style.display = "block";
    form.style.display = "block";
  } catch (e) {
    console.error("Fehler beim Öffnen des Mitarbeiter-Datenblatts von Bereitschaft:", e);
    alert("Fehler beim Laden der Daten. Details siehe Konsole.");
  }
}

// ---------------------------------------------------------
// Bereitschaft einem offenen Schicht-Slot zuordnen
// ---------------------------------------------------------

async function assignBereitschaftToOpenShift(dayId, bereitschaft) {
  try {
    // Alle offenen Slots (personal1 oder personal2 leer) über alle Standorte und Schichten einsammeln
    const offeneSlots = [];

    const standortPromises = allStandorte
      .filter((s) => s.active !== false)
      .map(async (standort) => {
        const dayRef = getDayDocRef(standort.id, dayId);
        const daySnap = await getDoc(dayRef);
        if (!daySnap.exists()) return;

        const shiftsCol = getShiftsCollection(standort.id, dayId);
        const snap = await getDocs(shiftsCol);
        snap.forEach((docSnap) => {
          const data = docSnap.data() || {};
          const shiftName = getShiftDisplayName(standort.id, docSnap.id, data);
          if (!data.personal1) {
            offeneSlots.push({
              standortId: standort.id,
              standortName: standort.name,
              shiftId: docSnap.id,
              shiftName,
              slotIndex: 1,
            });
          }
          if (!data.personal2) {
            offeneSlots.push({
              standortId: standort.id,
              standortName: standort.name,
              shiftId: docSnap.id,
              shiftName,
              slotIndex: 2,
            });
          }
        });
      });

    await Promise.all(standortPromises);

    if (offeneSlots.length === 0) {
      alert("Es gibt keine offenen Schicht-Slots an diesem Tag.");
      return;
    }

    // Kleinen Dialog mit Dropdown für die Slot-Auswahl anzeigen
    const existingDialog = document.getElementById("assignBereitschaftDialog");
    if (existingDialog) {
      existingDialog.remove();
    }

    const dialog = document.createElement("div");
    dialog.id = "assignBereitschaftDialog";
    dialog.className = "assign-bereitschaft-dialog";

    const title = document.createElement("h3");
    title.textContent = "Bereitschaft zuordnen";

    const info = document.createElement("p");
    info.textContent = "Bitte Ziel-Schicht für diese Bereitschaft auswählen:";

    const select = document.createElement("select");
    offeneSlots.forEach((slot, index) => {
      const opt = document.createElement("option");
      opt.value = String(index);
      // Nur den echten Schichtnamen anzeigen; wenn keiner gesetzt ist, neutralen Platzhalter verwenden
      const labelShiftName = slot.shiftName && slot.shiftName.trim().length > 0
        ? slot.shiftName
        : "Schicht ohne Namen";
      opt.textContent = `${slot.standortName} – Schicht ${labelShiftName} – Personal ${slot.slotIndex}`;
      select.appendChild(opt);
    });

    const actions = document.createElement("div");
    actions.className = "form-actions";

    const confirmBtn = document.createElement("button");
    confirmBtn.textContent = "Zuordnen";

    const cancelBtn = document.createElement("button");
    cancelBtn.textContent = "Abbrechen";
    cancelBtn.className = "cancel-btn";

    actions.appendChild(confirmBtn);
    actions.appendChild(cancelBtn);

    dialog.appendChild(title);
    dialog.appendChild(info);
    dialog.appendChild(select);
    dialog.appendChild(actions);

    // Dialog innerhalb des Tages-Popups einblenden
    if (dayPopupForm) {
      dayPopupForm.appendChild(dialog);
    } else {
      document.body.appendChild(dialog);
    }

    cancelBtn.addEventListener("click", () => {
      dialog.remove();
    });

    confirmBtn.addEventListener("click", async () => {
      const idx = parseInt(select.value, 10);
      if (isNaN(idx) || idx < 0 || idx >= offeneSlots.length) {
        alert("Bitte eine gültige Ziel-Schicht auswählen.");
        return;
      }

      const ziel = offeneSlots[idx];

      // Mitarbeiter-Daten aus Bereitschaft übernehmen
      const mitarbeiter = allMitarbeiter.find((m) => m.id === bereitschaft.mitarbeiterId);
      let qualis = [];
      if (Array.isArray(mitarbeiter?.qualifikation)) {
        qualis = mitarbeiter.qualifikation;
      }

      const personalData = {
        mitarbeiterId: bereitschaft.mitarbeiterId,
        name:
          bereitschaft.name || (mitarbeiter ? `${mitarbeiter.vorname} ${mitarbeiter.nachname}` : ""),
        qualifikationen: qualis,
        // Bereitschaften standardmäßig in Gelb hervorheben
        farbe: "#ffef94",
      };

      // Prüfe auf Doppelbelegung
      const existingAssignments = await checkMitarbeiterAlreadyAssigned(dayId, bereitschaft.mitarbeiterId, ziel.standortId, ziel.shiftId, ziel.slotIndex);
      if (existingAssignments.length > 0) {
        const shouldContinue = await showDoubleAssignmentWarning(personalData.name, existingAssignments);
        if (!shouldContinue) {
          dialog.remove();
          return; // Abbruch
        }
      }

      try {
        // Schicht-Slot setzen
        const shiftsCol = getShiftsCollection(ziel.standortId, dayId);
        const ref = doc(shiftsCol, ziel.shiftId);
        const field = ziel.slotIndex === 1 ? "personal1" : "personal2";
        await setDoc(ref, { [field]: personalData }, { merge: true });

        // Bereitschaft löschen
        const bereitsCol = getBereitschaftenCollection(bereitschaft.standortId, dayId);
        await deleteDoc(doc(bereitsCol, bereitschaft.id));

        dialog.remove();
        await showCalendarDayDetails(dayId);
      } catch (err) {
        console.error("Fehler beim Zuordnen der Bereitschaft:", err);
        alert("Fehler beim Zuordnen der Bereitschaft. Details siehe Konsole.");
      }
    });
  } catch (e) {
    console.error("Fehler beim Zuordnen einer Bereitschaft zu einer Schicht:", e);
    alert("Fehler beim Zuordnen der Bereitschaft. Details siehe Konsole.");
  }
}

// Dummy-Schließfunktionen für weitere Formulare, damit keine Fehler entstehen,
// wenn Buttons geklickt werden. Diese können später mit echter Logik gefüllt werden.

window.closeDatePopup = function () {
  const ov = document.getElementById("datePopupOverlay");
  const form = document.getElementById("datePopupForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

window.closeMitarbeiterDatenblatt = function () {
  const ov = document.getElementById("mitarbeiterDatenblattOverlay");
  const form = document.getElementById("mitarbeiterDatenblattForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

window.closeStandortForm = function () {
  const ov = document.getElementById("standortFormOverlay");
  const form = document.getElementById("standortForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

window.closeSchichtForm = function () {
  const ov = document.getElementById("schichtFormOverlay");
  const form = document.getElementById("schichtForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

window.closeMitarbeiterForm = function () {
  const ov = document.getElementById("mitarbeiterFormOverlay");
  const form = document.getElementById("mitarbeiterForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

window.closeBereitschaftsTypForm = function () {
  const ov = document.getElementById("bereitschaftsTypFormOverlay");
  const form = document.getElementById("bereitschaftsTypForm");
  if (ov) ov.style.display = "none";
  if (form) form.style.display = "none";
};

// closeBereitschaftenView entfernt - Fenster wird nicht mehr verwendet

// ---------------------------------------------------------
// Start: Auth-Handshake und App-Initialisierung
// ---------------------------------------------------------

window.addEventListener("DOMContentLoaded", async () => {
  try {
    userAuthData = await waitForAuthData();
    console.log(
      `✅ Schichtplan: Auth-Daten geladen - Company: ${userAuthData.companyId}, Role: ${userAuthData.role}`
    );
    await initializeApp();
  } catch (e) {
    console.error("❌ Fehler bei der Initialisierung des Schichtplans:", e);
  }
});
