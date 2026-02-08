// ovdeinsatztagebuch.js – OVD Einsatztagebuch Modul
// - Auth-Handshake über das Dashboard
// - Automatische Anlage täglicher Einsatztagebücher
// - CRUD-Operationen für Einträge

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
  updateDoc,
  where,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände & Konstanten
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, ... }
let currentDayId = null; // Format: DD.MM.YYYY
let currentDayDoc = null; // Aktuelles Tagebuch-Dokument
let editAllowedRoles = ['superadmin', 'admin', 'leiterssd']; // Rollen, die abgeschlossene/vergangene Tage bearbeiten dürfen
let settingsAllowedRoles = ['superadmin', 'admin', 'leiterssd']; // Rollen, die Einstellungen sehen können
let allEreignisse = []; // Liste aller verfügbaren Ereignisse

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const topBar = document.getElementById("topBar");
const mainContent = document.getElementById("mainContent");
const printDayBtn = document.getElementById("printDayBtn");
const savePdfDayBtn = document.getElementById("savePdfDayBtn");
const settingsBtn = document.getElementById("settingsBtn");
const addEventBtn = document.getElementById("addEventBtn");
const eventsTableBody = document.getElementById("eventsTableBody");
const eventPopupOverlay = document.getElementById("eventPopupOverlay");
const eventPopupForm = document.getElementById("eventPopupForm");
const eventPopupTitle = document.getElementById("eventPopupTitle");
const eventForm = document.getElementById("eventForm");
const eventIdInput = document.getElementById("eventId");
const eventDateInput = document.getElementById("eventDate");
const eventTimeInput = document.getElementById("eventTime");
const eventTypeInput = document.getElementById("eventType");
const eventTextInput = document.getElementById("eventText");
const eventOvdInput = document.getElementById("eventOvd");
const setCurrentDateBtn = document.getElementById("setCurrentDateBtn");
const setCurrentTimeBtn = document.getElementById("setCurrentTimeBtn");
const cancelEventBtn = document.getElementById("cancelEventBtn");
const closePopupBtn = document.getElementById("closePopupBtn");
const daySelector = document.getElementById("daySelector");
const todayBtn = document.getElementById("todayBtn");
const settingsMenu = document.getElementById("settingsMenu");
const manageEventsBtn = document.getElementById("manageEventsBtn");
const uebersichtBtn = document.getElementById("uebersichtBtn");
const eventsManagePopupOverlay = document.getElementById("eventsManagePopupOverlay");
const eventsManagePopupForm = document.getElementById("eventsManagePopupForm");
const closeEventsManageBtn = document.getElementById("closeEventsManageBtn");
const newEventNameInput = document.getElementById("newEventName");
const addEventNameBtn = document.getElementById("addEventNameBtn");
const eventsList = document.getElementById("eventsList");

// ---------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------

/**
 * Formatiert ein Date-Objekt zu DD.MM.YYYY
 */
function formatDate(date) {
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = date.getFullYear();
  return `${day}.${month}.${year}`;
}

/**
 * Formatiert ein Date-Objekt zu HH.MM
 */
function formatTime(date) {
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  return `${hours}.${minutes}`;
}

/**
 * Parst DD.MM.YYYY zu Date
 */
function parseDate(dateString) {
  const [day, month, year] = dateString.split('.');
  return new Date(year, month - 1, day);
}

/**
 * Gibt den aktuellen Tag-ID zurück (DD.MM.YYYY)
 */
function getCurrentDayId() {
  return formatDate(new Date());
}

/**
 * Prüft, ob ein Tag abgeschlossen ist
 */
function isDayClosed(dayDoc) {
  return dayDoc?.closed === true;
}

/**
 * Prüft, ob ein Tag in der Vergangenheit liegt
 */
function isPastDay(dayId) {
  try {
    const dayDate = parseDate(dayId);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    dayDate.setHours(0, 0, 0, 0);
    return dayDate < today;
  } catch (error) {
    console.error("Fehler beim Prüfen, ob Tag in der Vergangenheit liegt:", error);
    return false;
  }
}

/**
 * Ruft den Namen (Vor- und Nachname) eines Mitarbeiters aus der zentralen mitarbeiter Collection ab
 * 🔥 NEU: Verwendet die zentrale mitarbeiter Collection statt schichtplanMitarbeiter
 */
async function getEmployeeName(uid) {
  try {
    if (!uid || !userAuthData?.companyId) {
      console.warn("getEmployeeName: Keine UID oder companyId verfügbar");
      return null;
    }
    
    // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Suche direkt nach UID
    // Versuche 1: Direkte Abfrage mit UID als Dokument-ID
    const mitarbeiterRef = doc(db, "kunden", userAuthData.companyId, "mitarbeiter", uid);
    const mitarbeiterSnap = await getDoc(mitarbeiterRef);
    
    if (mitarbeiterSnap.exists()) {
      const mitarbeiterData = mitarbeiterSnap.data();
      const vorname = mitarbeiterData.vorname || '';
      const nachname = mitarbeiterData.nachname || '';
      
      if (vorname || nachname) {
        const fullName = `${vorname} ${nachname}`.trim();
        console.log(`getEmployeeName: Name gefunden (direkt): ${fullName}`);
        return fullName;
      }
    }
    
    // Versuche 2: Suche nach uid-Feld in der mitarbeiter Collection
    const mitarbeiterCollection = collection(db, "kunden", userAuthData.companyId, "mitarbeiter");
    const uidQuery = query(mitarbeiterCollection, where("uid", "==", uid));
    const uidSnapshot = await getDocs(uidQuery);
    
    if (!uidSnapshot.empty) {
      const mitarbeiterDoc = uidSnapshot.docs[0];
      const mitarbeiterData = mitarbeiterDoc.data();
      const vorname = mitarbeiterData.vorname || '';
      const nachname = mitarbeiterData.nachname || '';
      
      if (vorname || nachname) {
        const fullName = `${vorname} ${nachname}`.trim();
        console.log(`getEmployeeName: Name gefunden (über uid-Feld): ${fullName}`);
        return fullName;
      }
    }
    
    console.warn(`getEmployeeName: Kein Mitarbeiter mit UID ${uid} gefunden`);
    return null;
  } catch (error) {
    console.error("Fehler beim Abrufen des Mitarbeiternamens:", error);
    return null;
  }
}

/**
 * Prüft, ob der Benutzer Einstellungen sehen darf
 */
function canAccessSettings() {
  if (!userAuthData) return false;
  // Normalisiere Rolle zu Kleinbuchstaben für Vergleich
  const normalizedRole = (userAuthData.role || '').toLowerCase().trim();
  return settingsAllowedRoles.some(role => role.toLowerCase() === normalizedRole);
}

/**
 * Prüft, ob der Benutzer einen Tag sehen darf
 */
function canViewDay(dayDoc) {
  if (!dayDoc) return true; // Wenn kein Dokument existiert, darf man es sehen (wird beim Laden erstellt)
  
  // Superadmin und Admin können immer alle Tage sehen
  if (userAuthData?.role === 'superadmin' || userAuthData?.role === 'admin') {
    return true;
  }
  
  // Für andere Rollen: Prüfe, ob der Tag freigegeben ist (später implementierbar über ein Feld in dayDoc)
  // Aktuell: Alle Tage sind sichtbar, aber nur bearbeitbar wenn nicht abgeschlossen
  return true;
}

/**
 * Prüft, ob der Benutzer einen Tag bearbeiten darf
 */
function canEditDay(dayDoc) {
  if (!dayDoc) return false;
  
  // Superadmin, Admin und Rettungsdienstleiter können immer bearbeiten
  const normalizedRole = (userAuthData?.role || '').toLowerCase().trim();
  if (editAllowedRoles.some(role => role.toLowerCase() === normalizedRole)) {
    return true;
  }
  
  // OVD: Nur aktueller Tag bearbeitbar
  if (userAuthData?.role === 'ovd') {
    const todayId = getCurrentDayId();
    // OVD kann nur den aktuellen Tag bearbeiten
    return dayDoc.id === todayId && !isDayClosed(dayDoc);
  }
  
  // Für andere Rollen: Vergangene/abgeschlossene Tage nicht bearbeitbar
  const todayId = getCurrentDayId();
  if (isPastDay(dayDoc.id) || isDayClosed(dayDoc)) {
    return false;
  }
  
  // Aktueller Tag (nicht abgeschlossen): Bearbeitbar
  if (dayDoc.id === todayId && !isDayClosed(dayDoc)) {
    return true;
  }
  
  // Zukünftige Tage: Bearbeitbar
  return true;
}

// ---------------------------------------------------------
// Ereignisse (Master-Daten) Funktionen
// ---------------------------------------------------------

/**
 * Lädt alle Ereignisse aus Firestore
 * Pfad: kunden/{companyId}/ovdEinsatztagebuchEreignisse/{ereignisId}
 * 
 * HINWEIS: Alle Rollen (inkl. OVD) können die Ereignisse laden und im Dropdown auswählen.
 * Die Verwaltung der Ereignisse (Hinzufügen/Bearbeiten/Löschen) ist nur für 
 * Superadmin, Admin und Rettungsdienstleiter über das Einstellungsmenü möglich.
 */
async function loadEreignisse() {
  try {
    const ereignisseRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchEreignisse");
    const snapshot = await getDocs(ereignisseRef);
    
    const ereignisse = [];
    snapshot.forEach((doc) => {
      // Stelle sicher, dass order eine Zahl ist
      const orderValue = doc.data().order;
      const order = (typeof orderValue === 'number') ? orderValue : (typeof orderValue === 'string' ? parseInt(orderValue, 10) : 999);
      
      ereignisse.push({
        id: doc.id,
        name: doc.data().name || doc.id,
        order: isNaN(order) ? 999 : order,
        active: doc.data().active !== false
      });
    });
    
    // Sortiere nach order, dann nach Name (numerische Sortierung für order)
    ereignisse.sort((a, b) => {
      const orderA = typeof a.order === 'number' ? a.order : parseInt(a.order, 10) || 999;
      const orderB = typeof b.order === 'number' ? b.order : parseInt(b.order, 10) || 999;
      
      if (orderA !== orderB) {
        return orderA - orderB;
      }
      return (a.name || '').localeCompare(b.name || '');
    });
    
    allEreignisse = ereignisse;
    return ereignisse;
  } catch (error) {
    console.error("Fehler beim Laden der Ereignisse:", error);
    return [];
  }
}

/**
 * Speichert ein neues Ereignis
 */
async function saveEreignis(name) {
  try {
    // Lade aktuelle Ereignisse, um die richtige Order zu bestimmen
    const ereignisse = await loadEreignisse();
    const maxOrder = ereignisse.length > 0 
      ? Math.max(...ereignisse.map(e => e.order || 0)) 
      : -1;
    
    const ereignisseRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchEreignisse");
    const ereignisId = name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
    
    const ereignisDoc = {
      name: name.trim(),
      order: maxOrder + 1,
      active: true,
      createdAt: serverTimestamp(),
      createdBy: userAuthData.uid
    };
    
    const docRef = doc(ereignisseRef, ereignisId);
    await setDoc(docRef, ereignisDoc);
    console.log(`✅ Ereignis gespeichert: ${ereignisId}`);
    return ereignisId;
  } catch (error) {
    console.error("Fehler beim Speichern des Ereignisses:", error);
    throw error;
  }
}

/**
 * Löscht ein Ereignis
 */
async function deleteEreignis(ereignisId) {
  try {
    const ereignisRef = doc(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchEreignisse", ereignisId);
    await deleteDoc(ereignisRef);
    console.log(`✅ Ereignis gelöscht: ${ereignisId}`);
  } catch (error) {
    console.error("Fehler beim Löschen des Ereignisses:", error);
    throw error;
  }
}

/**
 * Füllt das Ereignis-Dropdown im Formular
 * 
 * HINWEIS: Alle Rollen (inkl. OVD) können die Ereignisse im Dropdown sehen und auswählen,
 * um vordefinierte Ereignisse beim Erstellen neuer Einträge zu verwenden.
 */
async function fillEventTypeDropdown() {
  const select = eventTypeInput;
  if (!select) return;
  
  // Aktuellen Wert merken
  const currentValue = select.value;
  
  // Lade aktuelle Ereignisse (für alle Rollen verfügbar)
  const ereignisse = await loadEreignisse();
  
  // Filtere nur aktive Ereignisse und sortiere sie
  const activeEreignisse = ereignisse
    .filter(ereignis => ereignis.active !== false)
    .sort((a, b) => {
      // Stelle sicher, dass order numerisch ist
      const orderA = typeof a.order === 'number' ? a.order : parseInt(a.order, 10) || 999;
      const orderB = typeof b.order === 'number' ? b.order : parseInt(b.order, 10) || 999;
      
      if (orderA !== orderB) {
        return orderA - orderB;
      }
      return (a.name || '').localeCompare(b.name || '');
    });
  
  // Leere Optionen bis auf die erste
  select.innerHTML = '<option value="">Bitte wählen...</option>';
  
  // Füge sortierte Ereignisse hinzu
  activeEreignisse.forEach(ereignis => {
    const option = document.createElement('option');
    option.value = ereignis.name;
    option.textContent = ereignis.name;
    select.appendChild(option);
  });
  
  // Setze vorherigen Wert wieder, falls vorhanden
  if (currentValue) {
    select.value = currentValue;
  }
}

// ---------------------------------------------------------
// Datenbank-Funktionen
// ---------------------------------------------------------

/**
 * Erstellt oder lädt das Tagebuch für einen Tag
 * Pfad: kunden/{companyId}/ovdEinsatztagebuchTage/{dayId}
 */
async function ensureDayDocument(dayId) {
  try {
    const dayRef = doc(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId);
    const daySnap = await getDoc(dayRef);
    
    if (!daySnap.exists()) {
      // Erstelle neues Tagebuch-Dokument
      const dayData = {
        datum: dayId,
        createdAt: serverTimestamp(),
        closed: false,
        createdBy: userAuthData.uid,
        createdByName: userAuthData.email || "Unbekannt"
      };
      await setDoc(dayRef, dayData);
      console.log(`✅ Tagebuch für ${dayId} erstellt`);
      return { id: dayId, ...dayData };
    }
    
    return { id: dayId, ...daySnap.data() };
  } catch (error) {
    console.error("Fehler beim Erstellen/Laden des Tagebuchs:", error);
    throw error;
  }
}

/**
 * Lädt alle Einträge für einen Tag
 * Pfad: kunden/{companyId}/ovdEinsatztagebuchTage/{dayId}/eintraege/{eintragId}
 */
async function loadEventsForDay(dayId) {
  try {
    const eventsRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege");
    const snapshot = await getDocs(eventsRef);
    
    const events = [];
    snapshot.forEach((doc) => {
      events.push({ id: doc.id, ...doc.data() });
    });
    
    // Sortiere manuell: Zuerst nach Datum, dann nach Uhrzeit
    events.sort((a, b) => {
      const dateCompare = (a.datum || '').localeCompare(b.datum || '');
      if (dateCompare !== 0) return dateCompare;
      return (a.uhrzeit || '').localeCompare(b.uhrzeit || '');
    });
    
    return events;
  } catch (error) {
    console.error("Fehler beim Laden der Einträge:", error);
    return [];
  }
}

/**
 * Speichert einen neuen Eintrag
 */
async function saveEvent(dayId, eventData) {
  try {
    const eventsRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege");
    
    // Automatisch den Vor- und Nachname des eingeloggten Benutzers verwenden, falls nicht gesetzt
    let diensthabenderOvd = eventData.diensthabenderOvd;
    if (!diensthabenderOvd || diensthabenderOvd === "Unbekannt") {
      const employeeName = await getEmployeeName(userAuthData.uid);
      if (employeeName) {
        diensthabenderOvd = employeeName;
      }
    }
    
    const eventDoc = {
      ...eventData,
      diensthabenderOvd: diensthabenderOvd || "Unbekannt",
      createdAt: serverTimestamp(),
      createdBy: userAuthData.uid,
      createdByName: userAuthData.email || "Unbekannt"
    };
    const docRef = await addDoc(eventsRef, eventDoc);
    console.log(`✅ Eintrag gespeichert: ${docRef.id}`);
    return docRef.id;
  } catch (error) {
    console.error("Fehler beim Speichern des Eintrags:", error);
    throw error;
  }
}

/**
 * Aktualisiert einen Eintrag
 */
async function updateEvent(dayId, eventId, eventData) {
  try {
    const eventRef = doc(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege", eventId);
    await updateDoc(eventRef, {
      ...eventData,
      updatedAt: serverTimestamp(),
      updatedBy: userAuthData.uid
    });
    console.log(`✅ Eintrag aktualisiert: ${eventId}`);
  } catch (error) {
    console.error("Fehler beim Aktualisieren des Eintrags:", error);
    throw error;
  }
}

/**
 * Löscht einen Eintrag
 */
async function deleteEvent(dayId, eventId) {
  try {
    const eventRef = doc(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege", eventId);
    await deleteDoc(eventRef);
    console.log(`✅ Eintrag gelöscht: ${eventId}`);
  } catch (error) {
    console.error("Fehler beim Löschen des Eintrags:", error);
    throw error;
  }
}

/**
 * Fragt nach Bestätigung und löscht dann einen Eintrag
 */
async function deleteEventConfirm(eventId) {
  if (!canEditDay(currentDayDoc)) {
    alert("Sie haben keine Berechtigung, diesen Eintrag zu löschen.");
    return;
  }
  
  if (confirm("Möchten Sie diesen Eintrag wirklich löschen?")) {
    try {
      await deleteEvent(currentDayId, eventId);
      await refreshEvents();
    } catch (error) {
      console.error("Fehler beim Löschen:", error);
      alert("Fehler beim Löschen des Eintrags.");
    }
  }
}

// Globale Funktion für Delete (wird vom onclick-Attribut aufgerufen)
window.deleteEventConfirm = deleteEventConfirm;

// ---------------------------------------------------------
// UI-Funktionen
// ---------------------------------------------------------

/**
 * Rendert die Einträge in der Tabelle
 */
function renderEvents(events) {
  if (events.length === 0) {
    eventsTableBody.innerHTML = '<tr><td colspan="5" class="no-events">Keine Einträge vorhanden</td></tr>';
    return;
  }
  
  // Prüfe ob Mobile (Bildschirmbreite < 480px)
  const isMobile = window.innerWidth <= 480;
  
  eventsTableBody.innerHTML = events.map(event => {
    // Nur Uhrzeit anzeigen (ohne Datum)
    let uhrzeit = event.uhrzeit || '';
    // Konvertiere HH:MM:SS zu HH:MM (oder HH.MM zu HH:MM)
    if (uhrzeit.includes(':')) {
      uhrzeit = uhrzeit.split(':').slice(0, 2).join(':');
    } else if (uhrzeit.includes('.')) {
      uhrzeit = uhrzeit.replace(/\./g, ':').split(':').slice(0, 2).join(':');
    }
    const zeitpunkt = uhrzeit;
    const canEdit = canEditDay(currentDayDoc);
    const clickable = canEdit ? 'clickable' : '';
    const onclick = canEdit ? `onclick="openEditEvent('${event.id}')"` : '';
    const ovd = event.diensthabenderOvd || event.createdByName || 'Unbekannt';
    
    if (isMobile) {
      // Mobile: Karten-Layout mit data-label Attributen
      // Zeitpunkt (erste Zeile) hat kein Label, wird größer und fett angezeigt
      const deleteBtn = canEdit ? `
        <td class="delete-cell" onclick="event.stopPropagation(); deleteEventConfirm('${event.id}')" title="Eintrag löschen">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            <line x1="10" y1="11" x2="10" y2="17"></line>
            <line x1="14" y1="11" x2="14" y2="17"></line>
          </svg>
        </td>
      ` : '<td class="delete-cell"></td>';
      
      return `
        <tr class="${clickable}" ${onclick}>
          <td>${zeitpunkt}</td>
          <td data-label="Ereignis">${event.ereignis || ''}</td>
          <td data-label="Text">${event.text || ''}</td>
          <td data-label="OVD">${ovd}</td>
          ${deleteBtn}
        </tr>
      `;
    } else {
      // Desktop: Normale Tabellen-Ansicht
      const deleteBtn = canEdit ? `
        <td class="delete-cell" onclick="event.stopPropagation(); deleteEventConfirm('${event.id}')" title="Eintrag löschen">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            <line x1="10" y1="11" x2="10" y2="17"></line>
            <line x1="14" y1="11" x2="14" y2="17"></line>
          </svg>
        </td>
      ` : '<td></td>';
      
      return `
        <tr class="${clickable}" ${onclick}>
          <td>${zeitpunkt}</td>
          <td>${event.ereignis || ''}</td>
          <td>${event.text || ''}</td>
          <td>${ovd}</td>
          ${deleteBtn}
        </tr>
      `;
    }
  }).join('');
  
  // Event: Re-render bei Resize für responsive Umschaltung
  if (!window.hasResizeListener) {
    window.hasResizeListener = true;
    let resizeTimeout;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(() => {
        // Re-render Events wenn sich die Bildschirmgröße ändert
        if (currentDayId) {
          refreshEvents();
        }
      }, 250);
    });
  }
}

/**
 * Öffnet das Popup zum Hinzufügen eines neuen Eintrags
 */
async function openAddEvent() {
  eventPopupTitle.textContent = "Neues Ereignis";
  eventForm.reset();
  eventIdInput.value = '';
  
  // Automatisch den Vor- und Nachname des eingeloggten Benutzers eintragen
  const employeeName = await getEmployeeName(userAuthData?.uid);
  if (employeeName) {
    eventOvdInput.value = employeeName;
  } else {
    eventOvdInput.value = userAuthData?.email || "Unbekannt";
  }
  
  // Feld IMMER schreibgeschützt - darf nicht geändert werden
  eventOvdInput.readOnly = true;
  eventOvdInput.style.backgroundColor = '#f3f4f6';
  eventOvdInput.style.cursor = 'not-allowed';
  
  // Setze aktuelles Datum und Zeit
  const now = new Date();
  eventDateInput.value = formatDate(now);
  eventTimeInput.value = formatTime(now);
  
  // Fülle Ereignis-Dropdown
  await fillEventTypeDropdown();
  
  eventPopupOverlay.style.display = 'block';
  eventPopupForm.style.display = 'flex';
}

/**
 * Öffnet das Popup zum Bearbeiten eines Eintrags
 */
async function openEditEvent(eventId) {
  if (!canEditDay(currentDayDoc)) {
    alert("Sie haben keine Berechtigung, diesen Eintrag zu bearbeiten.");
    return;
  }
  
  try {
    const events = await loadEventsForDay(currentDayId);
    const event = events.find(e => e.id === eventId);
    
    if (!event) {
      alert("Eintrag nicht gefunden.");
      return;
    }
    
    // Fülle Ereignis-Dropdown
    await fillEventTypeDropdown();
    
    eventPopupTitle.textContent = "Ereignis bearbeiten";
    eventIdInput.value = eventId;
    eventDateInput.value = event.datum || '';
    // Konvertiere Uhrzeit von HH:MM:SS zu HH.MM falls nötig
    let timeValue = event.uhrzeit || '';
    if (timeValue.includes(':')) {
      timeValue = timeValue.split(':').slice(0, 2).join('.');
    }
    eventTimeInput.value = timeValue;
    eventTypeInput.value = event.ereignis || '';
    eventTextInput.value = event.text || '';
    
    // Beim Bearbeiten: Zeige immer den Namen des aktuell eingeloggten Benutzers an
    // Dieser wird beim Speichern verwendet (konsistent mit neuem Ereignis)
    const employeeName = await getEmployeeName(userAuthData?.uid);
    if (employeeName) {
      eventOvdInput.value = employeeName;
    } else {
      eventOvdInput.value = userAuthData?.email || "Unbekannt";
    }
    
    // Feld IMMER schreibgeschützt - darf nicht geändert werden
    eventOvdInput.readOnly = true;
    eventOvdInput.style.backgroundColor = '#f3f4f6';
    eventOvdInput.style.cursor = 'not-allowed';
    
    eventPopupOverlay.style.display = 'block';
    eventPopupForm.style.display = 'flex';
  } catch (error) {
    console.error("Fehler beim Laden des Eintrags:", error);
    alert("Fehler beim Laden des Eintrags.");
  }
}

/**
 * Schließt das Popup
 */
function closeEventPopup() {
  eventPopupOverlay.style.display = 'none';
  eventPopupForm.style.display = 'none';
  eventForm.reset();
}

/**
 * Setzt das aktuelle Datum
 */
function setCurrentDate() {
  eventDateInput.value = formatDate(new Date());
}

/**
 * Setzt die aktuelle Uhrzeit
 */
function setCurrentTime() {
  eventTimeInput.value = formatTime(new Date());
}

// ---------------------------------------------------------
// Einstellungsmenü Funktionen
// ---------------------------------------------------------

/**
 * Öffnet das Einstellungs-Menü
 */
function openSettingsMenu() {
  if (settingsMenu) {
    settingsMenu.style.display = 'block';
  }
}

/**
 * Schließt das Einstellungs-Menü
 */
function closeSettingsMenu() {
  if (settingsMenu) {
    settingsMenu.style.display = 'none';
  }
}

/**
 * Toggle das Einstellungs-Menü
 */
function toggleSettingsMenu() {
  if (settingsMenu) {
    if (settingsMenu.style.display === 'block') {
      closeSettingsMenu();
    } else {
      openSettingsMenu();
    }
  }
}

/**
 * Öffnet das Popup zum Verwalten von Ereignissen
 */
async function openManageEventsPopup() {
  if (!canAccessSettings()) {
    alert("Sie haben keine Berechtigung für diese Funktion.");
    return;
  }
  
  eventsManagePopupOverlay.style.display = 'block';
  eventsManagePopupForm.style.display = 'flex';
  await renderEventsList();
}

/**
 * Schließt das Ereignisse-Verwaltungs-Popup
 */
function closeManageEventsPopup() {
  eventsManagePopupOverlay.style.display = 'none';
  eventsManagePopupForm.style.display = 'none';
  if (newEventNameInput) newEventNameInput.value = '';
}

/**
 * Rendert die Liste der Ereignisse
 */
async function renderEventsList() {
  const ereignisse = await loadEreignisse();
  
  if (ereignisse.length === 0) {
    eventsList.innerHTML = '<li class="no-items">Keine Ereignisse vorhanden</li>';
    return;
  }
  
  // Lösche alte Event-Listener
  eventsList.innerHTML = '';
  
  ereignisse.forEach((ereignis, index) => {
    const li = document.createElement('li');
    li.className = 'event-item draggable-event-item';
    li.draggable = true;
    li.dataset.ereignisId = ereignis.id;
    li.dataset.order = ereignis.order || index;
    
    const dragHandle = document.createElement('div');
    dragHandle.className = 'drag-handle';
    dragHandle.innerHTML = '☰';
    dragHandle.title = 'Ziehen zum Anordnen (Long Press auf Touch-Geräten)';
    
    const nameSpan = document.createElement('span');
    nameSpan.textContent = ereignis.name;
    
    const deleteBtn = document.createElement('button');
    deleteBtn.type = 'button';
    deleteBtn.className = 'delete-event-btn';
    deleteBtn.title = 'Löschen';
    deleteBtn.onclick = () => deleteEreignisConfirm(ereignis.id, ereignis.name);
    deleteBtn.innerHTML = `
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="3 6 5 6 21 6"></polyline>
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
      </svg>
    `;
    
    li.appendChild(dragHandle);
    li.appendChild(nameSpan);
    li.appendChild(deleteBtn);
    eventsList.appendChild(li);
  });
  
  // Setze Drag & Drop Handler
  setupEventsDragAndDrop();
}

/**
 * Löscht ein Ereignis nach Bestätigung
 */
async function deleteEreignisConfirm(ereignisId, ereignisName) {
  if (confirm(`Möchten Sie das Ereignis "${ereignisName}" wirklich löschen?`)) {
    try {
      await deleteEreignis(ereignisId);
      await renderEventsList();
      await fillEventTypeDropdown(); // Aktualisiere auch das Dropdown im Formular
    } catch (error) {
      console.error("Fehler beim Löschen:", error);
      alert("Fehler beim Löschen des Ereignisses.");
    }
  }
}

/**
 * Drag & Drop für Ereignisse
 */
function setupEventsDragAndDrop() {
  if (!eventsList) return;
  
  let draggedElement = null;
  let draggedIndex = -1;
  let longPressTimer = null;
  
  const getItems = () => eventsList.querySelectorAll(".draggable-event-item");
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
        items = getItems();
        const currentDraggedIndex = Array.from(items).indexOf(draggedElement);
        const dropIndex = Array.from(items).indexOf(item);
        
        if (currentDraggedIndex !== -1 && dropIndex !== -1 && currentDraggedIndex !== dropIndex) {
          if (currentDraggedIndex < dropIndex) {
            eventsList.insertBefore(draggedElement, item.nextSibling);
          } else {
            eventsList.insertBefore(draggedElement, item);
          }
          
          await updateEreignisOrder();
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
        if (navigator.vibrate) navigator.vibrate(50);
      }, 300);
    }, { passive: true });
    
    item.addEventListener("touchmove", (e) => {
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
      
      if (isDragging && draggedElement && draggedElement === item) {
        e.preventDefault();
        e.stopPropagation();
        const touchY = e.touches[0].clientY;
        const touchX = e.touches[0].clientX;
        
        items = getItems();
        items.forEach(i => {
          i.classList.remove("drag-over");
          if (i !== draggedElement) {
            const rect = i.getBoundingClientRect();
            if (touchY >= rect.top && touchY <= rect.bottom && 
                touchX >= rect.left && touchX <= rect.right) {
              i.classList.add("drag-over");
            }
          }
        });
      } else {
        const deltaY = Math.abs(e.touches[0].clientY - touchStartY);
        if (deltaY > 10) {
          clearTimeout(longPressTimer);
          longPressTimer = null;
        }
      }
    }, { passive: false });
    
    item.addEventListener("touchend", async (e) => {
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
      
      if (!isDragging || !draggedElement || draggedElement !== item) {
        return;
      }
      
      if (isDragging && draggedElement && draggedElement === item) {
        e.preventDefault();
        e.stopPropagation();
        
        const touchY = e.changedTouches[0].clientY;
        const touchX = e.changedTouches[0].clientX;
        
        items = getItems();
        const currentDraggedIndex = Array.from(items).indexOf(draggedElement);
        
        let targetItem = null;
        let minDistance = Infinity;
        
        items.forEach(i => {
          if (i !== draggedElement) {
            const rect = i.getBoundingClientRect();
            const centerY = rect.top + rect.height / 2;
            const distance = Math.abs(touchY - centerY);
            
            if (touchY >= rect.top && touchY <= rect.bottom) {
              if (!targetItem || distance < minDistance) {
                minDistance = distance;
                targetItem = i;
              }
            }
          }
        });
        
        items.forEach(i => i.classList.remove("drag-over"));
        
        if (targetItem && targetItem !== draggedElement && currentDraggedIndex !== -1) {
          const dropIndex = Array.from(items).indexOf(targetItem);
          
          if (dropIndex !== -1 && currentDraggedIndex !== dropIndex) {
            if (currentDraggedIndex < dropIndex) {
              eventsList.insertBefore(draggedElement, targetItem.nextSibling);
            } else {
              eventsList.insertBefore(draggedElement, targetItem);
            }
            
            await updateEreignisOrder();
          }
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

/**
 * Aktualisiert die Reihenfolge der Ereignisse in Firestore
 */
async function updateEreignisOrder() {
  try {
    const items = eventsList.querySelectorAll(".draggable-event-item");
    const updates = [];
    
    items.forEach((item, index) => {
      const ereignisId = item.dataset.ereignisId;
      const newOrder = index;
      updates.push({
        id: ereignisId,
        order: newOrder
      });
    });
    
    // Führe Updates parallel aus
    await Promise.all(updates.map(async (update) => {
      const ereignisRef = doc(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchEreignisse", update.id);
      await updateDoc(ereignisRef, { order: update.order });
    }));
    
    console.log("✅ Ereignis-Reihenfolge aktualisiert");
    
    // Aktualisiere lokale Liste und Dropdown
    await loadEreignisse();
    await fillEventTypeDropdown();
  } catch (error) {
    console.error("Fehler beim Aktualisieren der Reihenfolge:", error);
    alert("Fehler beim Aktualisieren der Reihenfolge.");
  }
}

/**
 * Erstellt ein PDF für den aktuellen Tag (gemeinsame Basis-Funktion)
 * Gibt das PDF-Objekt zurück, ohne es zu speichern
 */
async function createPdfForDay() {
  if (!currentDayId) {
    throw new Error("Kein Tag ausgewählt.");
  }
  
  // Lade Einträge für den aktuellen Tag
  const events = await loadEventsForDay(currentDayId);
  
  if (events.length === 0) {
    throw new Error("Keine Einträge für diesen Tag vorhanden.");
  }
  
  // Initialisiere jsPDF
  const { jsPDF } = window.jspdf;
  const pdf = new jsPDF('p', 'mm', 'a4');
    const pageWidth = pdf.internal.pageSize.getWidth(); // A4: 210mm
    const pageHeight = pdf.internal.pageSize.getHeight(); // A4: 297mm
    const margin = 10; // Reduzierte Margins für mehr Platz (10mm statt 15mm)
    const tableStartY = 40; // Verringert von 50 auf 40 (1 Zeile weniger Abstand zum Datum)
    let currentY = tableStartY;
    const lineHeight = 5; // Weiter verringert von 6 auf 5 für noch kompaktere Zeilen
    const rowHeight = 8; // Weiter verringert von 10 auf 8 für noch kompaktere Zeilen
    const textPadding = 1.058; // 4px in mm (bei 96 DPI)
    const columnGap = 5; // 5mm Abstand zwischen Zeitpunkt und Ereignis (verringert von 10mm)
    
    // Zuerst Titel und Datum zeichnen (vor Tabellenkopf-Berechnung)
    // Titel "Einsatztagebuch-OVD"
    pdf.setFontSize(18);
    pdf.setFont('helvetica', 'bold');
    pdf.setTextColor(14, 165, 233); // Primary color (RGB)
    pdf.text('Einsatztagebuch-OVD', margin, 20);
    
    // Datum
    pdf.setFontSize(12);
    pdf.setFont('helvetica', 'normal');
    pdf.setTextColor(30, 41, 59); // Text color (RGB)
    pdf.text(`Datum: ${currentDayId}`, margin, 30);
    
    console.log('📄 PDF: Titel und Datum gezeichnet. currentDayId:', currentDayId);
    console.log('📄 PDF: Seite 1, Y-Positionen - Titel: 20, Datum: 30');
    
    const tableWidth = pageWidth - 2 * margin;
    
    // Setze Font für Breitenberechnung
    pdf.setFontSize(10);
    pdf.setFont('helvetica', 'bold');
    
    // Abstände zwischen Spalten
    const textColumnGap = 10; // 1cm Abstand zwischen Ereignis und Text
    
    // Berechne X-Positionen mit 4px (1.058mm) Abstand links
    // Zeitpunkt und Ereignis haben 1cm (10mm) Abstand zueinander (basierend auf Textbreite)
    const colX = {
      zeitpunkt: margin + textPadding
    };
    
    // Berechne die tatsächliche Breite von "Zeitpunkt" für die Positionierung
    // Zeitpunkt-Spalte als Referenzgröße verwenden
    const zeitpunktHeaderWidth = pdf.getTextWidth('Zeitpunkt');
    const zeitpunktColWidth = Math.max(zeitpunktHeaderWidth + textPadding * 2, 25); // Mindestbreite 25mm
    
    colX.ereignis = colX.zeitpunkt + zeitpunktColWidth + columnGap; // Abstand nach "Zeitpunkt"
    
    // Ereignis-Spalte: Breiter machen, damit "Eingehender Anruf" in einer Zeile passt
    const ereignisHeaderWidth = pdf.getTextWidth('Ereignis');
    // Teste die Breite von "Eingehender Anruf" (längster typischer Text)
    // Wichtig: Font muss für normale Inhalte gesetzt sein (nicht bold)
    pdf.setFont('helvetica', 'normal');
    const longestEventText = 'Eingehender Anruf';
    const longestEventWidth = pdf.getTextWidth(longestEventText);
    const ereignisColWidth = Math.max(longestEventWidth + textPadding * 2, zeitpunktColWidth, 35); // Mindestens 35mm
    // Font wieder auf bold für Header setzen
    pdf.setFont('helvetica', 'bold');
    
    // OVD-Spalte am rechten Rand (rechtsbündig)
    const ovdHeaderText = 'Eintragender OVD';
    const ovdHeaderWidth = pdf.getTextWidth(ovdHeaderText);
    const ovdColWidth = Math.max(ovdHeaderWidth + textPadding * 2, 35); // Mindestens 35mm
    colX.ovd = pageWidth - margin - textPadding - ovdColWidth;
    
    // Text-Spalte zwischen Ereignis und OVD (mit 1cm Abstand nach "Ereignis")
    colX.text = colX.ereignis + ereignisColWidth + textColumnGap;
    
    // Spaltenbreiten für Inhalte (nur für maxWidth-Berechnungen)
    const colWidths = {
      zeitpunkt: zeitpunktColWidth,
      ereignis: ereignisColWidth,
      text: colX.ovd - colX.text - columnGap, // Rest zwischen Text und OVD
      ovd: ovdColWidth
    };
    
    // Hilfsfunktion zum Zeichnen des Tabellenkopfes
    const drawTableHeader = (yPos) => {
      console.log('📊 PDF: drawTableHeader aufgerufen, yPos:', yPos, 'tableWidth:', tableWidth, 'rowHeight:', rowHeight);
      
      // Hintergrund für Header (vertikal zentriert um yPos)
      // Header-Bereich: von yPos - rowHeight/2 bis yPos + rowHeight/2 (8mm hoch)
      const headerTop = yPos - (rowHeight / 2);  // yPos - 4mm
      const headerBottom = yPos + (rowHeight / 2); // yPos + 4mm
      pdf.setFillColor(243, 244, 246); // Secondary color (RGB)
      pdf.rect(margin, headerTop, tableWidth, rowHeight, 'F');
      
      // Header-Text vertikal zentriert
      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'bold');
      pdf.setTextColor(30, 41, 59); // Text color (RGB)
      
      // Vertikale Zentrierung: Berechne Baseline-Position für Header-Text
      // Header-Bereich: von headerTop (yPos - 4mm) bis headerBottom (yPos + 4mm)
      // Die Mitte ist bei yPos
      // jsPDF verwendet Y-Position als Baseline (Unterkante der Buchstaben)
      // Für 10pt Font: Die visuelle Mitte liegt etwa bei Baseline + (FontSize * 0.4)
      // FontSize 10pt = 3.52778mm, also Textmitte ≈ Baseline + 1.41mm
      // Um Textmitte bei yPos zu haben: Baseline = yPos - 1.41mm
      // Aber praktisch funktioniert yPos direkt am besten (kein Offset), da jsPDF die Baseline etwas anders interpretiert
      // Vertikale Zentrierung: Verwende jsPDF's baseline: 'middle' Option
      // yPos ist die Mitte des Header-Bereichs, verwende es direkt mit baseline: 'middle'
      console.log('🔍 DEBUG Header: headerTop=', headerTop.toFixed(2), 'headerBottom=', headerBottom.toFixed(2), 'yPos (Mitte)=', yPos.toFixed(2), 'Verwende baseline: middle');
      
      // Stelle sicher, dass Font korrekt gesetzt ist
      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'bold');
      pdf.setTextColor(30, 41, 59);
      
      // Verwende baseline: 'middle' für vertikale Zentrierung (yPos ist die Mitte)
      pdf.text('Zeitpunkt', colX.zeitpunkt, yPos, { baseline: 'middle' });
      pdf.text('Ereignis', colX.ereignis, yPos, { baseline: 'middle' });
      pdf.text('Text', colX.text, yPos, { baseline: 'middle' });
      
      // "Eintragender OVD" zentriert ausrichten (horizontal und vertikal)
      const ovdHeaderText = 'Eintragender OVD';
      const ovdHeaderX = colX.ovd + colWidths.ovd / 2;
      pdf.text(ovdHeaderText, ovdHeaderX, yPos, { align: 'center', baseline: 'middle' });
      
      // Linie unter Header
      pdf.setDrawColor(229, 231, 235); // Border color (RGB)
      pdf.setLineWidth(0.5);
      pdf.line(margin, yPos + (rowHeight / 2), pageWidth - margin, yPos + (rowHeight / 2));
      
      console.log('📊 PDF: Tabellenkopf gezeichnet bei Y:', yPos);
    };
    
    // Zeichne Tabellenkopf auf erster Seite (vertikal zentriert um currentY)
    drawTableHeader(currentY);
    currentY += rowHeight;
    
    events.forEach((event, index) => {
      // Nur Uhrzeit extrahieren und ins HH:MM Format konvertieren
      let uhrzeit = event.uhrzeit || '';
      // Konvertiere HH.MM zu HH:MM (falls im alten Format)
      if (uhrzeit.includes('.')) {
        uhrzeit = uhrzeit.replace(/\./g, ':').split(':').slice(0, 2).join(':');
      } else if (uhrzeit.includes(':')) {
        // Stelle sicher, dass nur Stunden und Minuten angezeigt werden
        uhrzeit = uhrzeit.split(':').slice(0, 2).join(':');
      }
      
      // Text umbrechen falls zu lang
      // Font muss vor splitTextToSize gesetzt werden
      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'normal');
      
      // Berechne verfügbare Breiten für Textumbruch
      // Verwende die Spaltenbreiten aus colWidths
      const zeitpunktMaxWidth = colWidths.zeitpunkt;
      const ereignisMaxWidth = colWidths.ereignis;
      
      const textMaxWidth = colX.ovd - colX.text - columnGap;
      const ovdMaxWidth = colWidths.ovd;
      
      // Debug: Log die berechneten Breiten (kann später entfernt werden)
      if (event.ereignis && event.ereignis.includes('Eingehender')) {
        console.log('📊 PDF: Ereignis-Debug für "Eingehender Anruf"');
        console.log('  - colX.ereignis:', colX.ereignis, 'colX.text:', colX.text, 'textColumnGap:', textColumnGap);
        console.log('  - ereignisMaxWidth:', ereignisMaxWidth, 'mm');
        console.log('  - Ereignis-Text:', event.ereignis);
      }
      
      const textLines = pdf.splitTextToSize(event.text || '', textMaxWidth);
      const ereignisLines = pdf.splitTextToSize(event.ereignis || '', ereignisMaxWidth);
      const zeitpunktLines = pdf.splitTextToSize(uhrzeit, zeitpunktMaxWidth);
      const ovdLines = pdf.splitTextToSize(event.diensthabenderOvd || '', ovdMaxWidth);
      
      // Setze Textfarbe für die Ausgabe
      pdf.setTextColor(30, 41, 59);
      
      const maxLines = Math.max(
        textLines.length,
        ereignisLines.length,
        zeitpunktLines.length,
        ovdLines.length,
        1
      );
      
      // Abstand zwischen Inhalt und Trennlinie: weiter verringert auf 2mm (statt 3mm)
      const separatorGap = 2; // Weiter verringert von 3mm auf 2mm für noch kompaktere Zeilen
      
      // Berechne die Höhe der Zeile: Inhalt + Abstand zur Trennlinie
      const actualRowHeight = Math.max(maxLines * lineHeight, rowHeight) + separatorGap;
      
      // Prüfe ob neue Seite nötig (inklusive Header-Höhe wenn nötig)
      if (currentY + actualRowHeight > pageHeight - margin) {
        pdf.addPage();
        
        // Titel und Datum auf neuer Seite zeichnen
        pdf.setFontSize(18);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(14, 165, 233);
        pdf.text('Einsatztagebuch-OVD', margin, 20);
        
        pdf.setFontSize(12);
        pdf.setFont('helvetica', 'normal');
        pdf.setTextColor(30, 41, 59);
        pdf.text(`Datum: ${currentDayId}`, margin, 30);
        
        currentY = tableStartY;
        // Header auf neuer Seite zeichnen (vertikal zentriert)
        drawTableHeader(currentY);
        currentY += rowHeight;
      }
      
      // Start-Position für diese Zeile ist einfach currentY
      // currentY zeigt bereits auf die Position nach dem Header oder nach der vorherigen Zeile
      const rowStartY = currentY;
      
      // Zeichne Zeile-Hintergrund
      pdf.setFillColor(255, 255, 255);
      pdf.rect(margin, rowStartY, tableWidth, actualRowHeight, 'F');
      
      // Text in Spalten oben ausrichten mit kleinem Abstand zum oberen Rand
      // Abstand oben: 2mm für sauberes Aussehen
      const topPadding = 2;
      const textStartY = rowStartY + topPadding;
      
      // Stelle sicher, dass Font und Farbe korrekt gesetzt sind
      pdf.setFontSize(10);
      pdf.setFont('helvetica', 'normal');
      pdf.setTextColor(30, 41, 59);
      
      // Zeichne Text und berechne tatsächliche Positionen, um den Abstand zwischen Inhalten zu kontrollieren
      // Zeitpunkt: linksbündig bei colX.zeitpunkt
      pdf.text(zeitpunktLines, colX.zeitpunkt, textStartY, { maxWidth: zeitpunktMaxWidth });
      
      // Ereignis: linksbündig bei colX.ereignis
      pdf.text(ereignisLines, colX.ereignis, textStartY, { maxWidth: ereignisMaxWidth });
      
      // Text-Inhalt bündig mit dem "Text"-Header beginnen (bei colX.text)
      const textContentX = colX.text;
      
      // Berechne die verfügbare Breite für Text-Inhalt (bis zur OVD-Spalte)
      const textContentMaxWidth = colX.ovd - textContentX - columnGap;
      
      pdf.text(textLines, textContentX, textStartY, { maxWidth: textContentMaxWidth });
      
      // OVD-Spalte zentriert ausrichten
      // Die Mitte der Spalte ist colX.ovd + colWidths.ovd / 2
      const ovdTextX = colX.ovd + colWidths.ovd / 2;
      pdf.text(ovdLines, ovdTextX, textStartY, { maxWidth: colWidths.ovd, align: 'center' });
      
      // Trennlinie unter der Zeile
      // Berechne Y-Position der Trennlinie: Ende des Inhalts + separatorGap (kleiner Abstand)
      // textStartY ist oben ausgerichtet mit topPadding, also ist das Ende bei textStartY + (maxLines - 1) * lineHeight
      const lastLineY = textStartY + (maxLines - 1) * lineHeight;
      const separatorY = lastLineY + separatorGap; // separatorGap = 2mm Abstand zum Inhalt
      
      pdf.setDrawColor(229, 231, 235); // Border color (RGB)
      pdf.setLineWidth(0.2);
      pdf.line(margin, separatorY, pageWidth - margin, separatorY);
      
      // Aktualisiere currentY für die nächste Zeile: Start dieser Zeile + gesamte Höhe (inkl. Trennlinie)
      currentY = rowStartY + actualRowHeight;
    });
    
    // Fußzeile mit Seitenzahl auf allen Seiten
    const totalPages = pdf.internal.pages.length - 1;
    for (let i = 1; i <= totalPages; i++) {
      pdf.setPage(i);
      
      // Stelle sicher, dass auf jeder Seite Titel, Datum und Header vorhanden sind
      if (i > 1) {
        // Auf nachfolgenden Seiten Titel und Datum neu zeichnen
        pdf.setFontSize(18);
        pdf.setFont('helvetica', 'bold');
        pdf.setTextColor(14, 165, 233);
        pdf.text('Einsatztagebuch-OVD', margin, 20);
        
        pdf.setFontSize(12);
        pdf.setFont('helvetica', 'normal');
        pdf.setTextColor(30, 41, 59);
        pdf.text(`Datum: ${currentDayId}`, margin, 30);
        
        // Header auf neuer Seite neu zeichnen
        drawTableHeader(tableStartY);
      }
      
      // Seitenzahl
      pdf.setFontSize(8);
      pdf.setFont('helvetica', 'normal');
      pdf.setTextColor(100, 100, 100);
      pdf.text(
        `Seite ${i} von ${totalPages}`,
        pageWidth - margin - 20,
        pageHeight - 10
      );
    }
    
    // Gebe das PDF-Objekt zurück (ohne zu speichern)
    return pdf;
}

/**
 * Exportiert den aktuellen Tag als PDF-Datei (herunterladen)
 */
async function exportDayToPdf() {
  try {
    const pdf = await createPdfForDay();
    
    // Dateiname generieren
    const fileName = `OVD_Einsatztagebuch_${currentDayId.replace(/\./g, '_')}.pdf`;
    
    // Datei herunterladen
    pdf.save(fileName);
    
    console.log("✅ PDF exportiert:", fileName);
  } catch (error) {
    console.error("Fehler beim PDF-Export:", error);
    alert("Fehler beim Exportieren des PDFs: " + error.message);
  }
}

/**
 * Öffnet Druckvorschau (nur Vorschau, kein Druckdialog)
 */
async function printDayDirectly() {
  try {
    if (!currentDayId) {
      alert("Kein Tag ausgewählt.");
      return;
    }
    
    const pdf = await createPdfForDay();
    
    // Erstelle Blob aus PDF
    const pdfBlob = pdf.output('blob');
    
    // Erstelle URL für Blob
    const pdfUrl = URL.createObjectURL(pdfBlob);
    
    // Öffne PDF in neuem Fenster zur Vorschau (ohne Druckdialog)
    const printWindow = window.open(pdfUrl, '_blank');
    
    if (printWindow) {
      // Cleanup nach kurzer Zeit
      setTimeout(() => URL.revokeObjectURL(pdfUrl), 1000);
      console.log("✅ PDF-Vorschau geöffnet");
    } else {
      alert("Pop-up wurde blockiert. Bitte erlauben Sie Pop-ups für diese Seite.");
      URL.revokeObjectURL(pdfUrl);
    }
  } catch (error) {
    console.error("Fehler beim Öffnen der Druckvorschau:", error);
    alert("Fehler beim Öffnen der Druckvorschau: " + error.message);
  }
}

/**
 * Speichert den aktuellen Tag als PDF (mit Speicherort-Abfrage)
 * Der Browser merkt sich den letzten Speicherort automatisch
 */
async function saveDayAsPdf() {
  try {
    if (!currentDayId) {
      alert("Kein Tag ausgewählt.");
      return;
    }
    
    const pdf = await createPdfForDay();
    
    // Generiere Dateiname
    const defaultFileName = `OVD_Einsatztagebuch_${currentDayId.replace(/\./g, '_')}.pdf`;
    
    // Speichere PDF (Browser öffnet Save-Dialog und merkt sich automatisch den letzten Ordner)
    // Der Browser fragt immer nach, aber zeigt den zuletzt verwendeten Ordner an
    pdf.save(defaultFileName);
    
    console.log("✅ PDF-Speicher-Dialog geöffnet:", defaultFileName);
  } catch (error) {
    console.error("Fehler beim Speichern des PDFs:", error);
    alert("Fehler beim Speichern: " + error.message);
  }
}



// Globale Funktionen
window.deleteEreignisConfirm = deleteEreignisConfirm;

// ---------------------------------------------------------
// Event Listeners
// ---------------------------------------------------------

// Formular absenden
eventForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  
  if (!canEditDay(currentDayDoc)) {
    alert("Sie haben keine Berechtigung, Einträge zu bearbeiten.");
    return;
  }
  
  const eventId = eventIdInput.value;
  
  // Verwende IMMER den Namen des aktuell eingeloggten Benutzers
  // Das Feld "Eintragender OVD" ist readonly und zeigt nur zur Information den ursprünglichen Wert an
  let diensthabenderOvd = null;
  const employeeName = await getEmployeeName(userAuthData.uid);
  if (employeeName) {
    diensthabenderOvd = employeeName;
  } else {
    diensthabenderOvd = userAuthData?.email || "Unbekannt";
  }
  
  const eventData = {
    datum: eventDateInput.value.trim(),
    uhrzeit: eventTimeInput.value.trim(),
    ereignis: eventTypeInput.value.trim(),
    text: eventTextInput.value.trim(),
    diensthabenderOvd: diensthabenderOvd
  };
  
  try {
    if (eventId) {
      // Aktualisiere bestehenden Eintrag
      await updateEvent(currentDayId, eventId, eventData);
    } else {
      // Erstelle neuen Eintrag
      await saveEvent(currentDayId, eventData);
    }
    
    closeEventPopup();
    await refreshEvents();
  } catch (error) {
    console.error("Fehler beim Speichern:", error);
    alert("Fehler beim Speichern des Eintrags.");
  }
});

// Buttons
addEventBtn?.addEventListener('click', openAddEvent);
setCurrentDateBtn?.addEventListener('click', setCurrentDate);
setCurrentTimeBtn?.addEventListener('click', setCurrentTime);
cancelEventBtn?.addEventListener('click', closeEventPopup);
closePopupBtn?.addEventListener('click', closeEventPopup);
eventPopupOverlay?.addEventListener('click', closeEventPopup);

// Datums-Selector Event Listeners
if (daySelector) {
  daySelector.addEventListener('change', (e) => {
    const selectedDate = e.target.value;
    if (selectedDate) {
      const dayId = dateInputToDayId(selectedDate);
      loadDay(dayId);
    }
  });
}

if (todayBtn) {
  todayBtn.addEventListener('click', () => {
    const todayId = getCurrentDayId();
    loadDay(todayId);
  });
}

// Verhindere, dass Klicks im Popup das Overlay schließen
eventPopupForm?.addEventListener('click', (e) => {
  e.stopPropagation();
});

// Globale Funktion für Edit (wird vom onclick-Attribut aufgerufen)
window.openEditEvent = openEditEvent;

// Event Listener für Einstellungs-Popup
if (settingsBtn) {
  settingsBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (canAccessSettings()) {
      toggleSettingsMenu();
    }
  });
}

// Schließe Menü beim Klick außerhalb
document.addEventListener('click', (e) => {
  if (settingsMenu && settingsBtn && 
      !settingsMenu.contains(e.target) && 
      !settingsBtn.contains(e.target)) {
    closeSettingsMenu();
  }
});

// Event Listener für Einstellungs-Menü-Items
if (manageEventsBtn) {
  manageEventsBtn.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    closeSettingsMenu();
    openManageEventsPopup();
  });
}

if (uebersichtBtn) {
  uebersichtBtn.addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();
    closeSettingsMenu();
    const frame = window.parent?.document.getElementById("contentFrame");
    if (frame) {
      frame.src = "/module/ovdeinsatztagebuch/ovdeinsatztagebuch-uebersicht.html";
    } else {
      window.location.href = "/module/ovdeinsatztagebuch/ovdeinsatztagebuch-uebersicht.html";
    }
  });
}

// Event Listener für Drucken
if (printDayBtn) {
  printDayBtn.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();
    await printDayDirectly();
  });
}

// Event Listener für Als PDF speichern
if (savePdfDayBtn) {
  savePdfDayBtn.addEventListener('click', async (e) => {
    e.preventDefault();
    e.stopPropagation();
    await saveDayAsPdf();
  });
}


// Event Listener für Ereignisse verwalten
if (closeEventsManageBtn) {
  closeEventsManageBtn.addEventListener('click', closeManageEventsPopup);
}

if (eventsManagePopupOverlay) {
  eventsManagePopupOverlay.addEventListener('click', closeManageEventsPopup);
}

if (eventsManagePopupForm) {
  eventsManagePopupForm.addEventListener('click', (e) => {
    e.stopPropagation();
  });
}

if (addEventNameBtn) {
  addEventNameBtn.addEventListener('click', async () => {
    const name = newEventNameInput?.value.trim();
    if (!name) {
      alert("Bitte geben Sie einen Ereignisnamen ein.");
      return;
    }
    
    try {
      await saveEreignis(name);
      newEventNameInput.value = '';
      await renderEventsList();
      await fillEventTypeDropdown(); // Aktualisiere auch das Dropdown im Formular
    } catch (error) {
      console.error("Fehler beim Hinzufügen:", error);
      alert("Fehler beim Hinzufügen des Ereignisses.");
    }
  });
}

// Enter-Taste für neues Ereignis
if (newEventNameInput) {
  newEventNameInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      addEventNameBtn?.click();
    }
  });
}


// ---------------------------------------------------------
// Initialisierung & Datenladen
// ---------------------------------------------------------

/**
 * Lädt die Einträge neu
 */
async function refreshEvents() {
  try {
    const events = await loadEventsForDay(currentDayId);
    renderEvents(events);
  } catch (error) {
    console.error("Fehler beim Laden der Einträge:", error);
    eventsTableBody.innerHTML = '<tr><td colspan="5" class="no-events error">Fehler beim Laden der Einträge</td></tr>';
  }
}

/**
 * Konvertiert dayId (DD.MM.YYYY) zu Date für date input
 */
function dayIdToDateInput(dayId) {
  const [day, month, year] = dayId.split('.');
  return `${year}-${month}-${day}`;
}

/**
 * Konvertiert Date Input (YYYY-MM-DD) zu dayId (DD.MM.YYYY)
 */
function dateInputToDayId(dateInput) {
  const [year, month, day] = dateInput.split('-');
  return `${day}.${month}.${year}`;
}

/**
 * Lädt einen bestimmten Tag
 */
async function loadDay(dayId) {
  try {
    currentDayId = dayId;
    currentDayDoc = await ensureDayDocument(dayId);
    
    // Prüfe, ob der Benutzer diesen Tag sehen darf
    if (!canViewDay(currentDayDoc)) {
      eventsTableBody.innerHTML = '<tr><td colspan="5" class="no-events error">Sie haben keine Berechtigung, diesen Tag einzusehen.</td></tr>';
      return;
    }
    
    // Aktualisiere Datums-Selector
    if (daySelector) {
      daySelector.value = dayIdToDateInput(dayId);
    }
    
    // Lade Einträge
    await refreshEvents();
    
    // Entferne alte Listener
    if (window.eventsSnapshotUnsubscribe) {
      window.eventsSnapshotUnsubscribe();
    }
    
    // Setze Live-Update Listener
    const eventsRef = collection(db, "kunden", userAuthData.companyId, "ovdEinsatztagebuchTage", dayId, "eintraege");
    
    window.eventsSnapshotUnsubscribe = onSnapshot(eventsRef, async (snapshot) => {
      const events = [];
      snapshot.forEach((doc) => {
        events.push({ id: doc.id, ...doc.data() });
      });
      
      // Sortiere manuell: Zuerst nach Datum, dann nach Uhrzeit
      events.sort((a, b) => {
        const dateCompare = (a.datum || '').localeCompare(b.datum || '');
        if (dateCompare !== 0) return dateCompare;
        return (a.uhrzeit || '').localeCompare(b.uhrzeit || '');
      });
      
      renderEvents(events);
    });
    
  } catch (error) {
    console.error("Fehler beim Laden des Tages:", error);
    eventsTableBody.innerHTML = '<tr><td colspan="5" class="no-events error">Fehler beim Laden des Tagebuchs</td></tr>';
  }
}

/**
 * Initialisiert das Modul für den aktuellen Tag oder ein Datum aus URL-Parameter
 */
async function initializeDay() {
  // Prüfe, ob ein Datum als URL-Parameter übergeben wurde
  const urlParams = new URLSearchParams(window.location.search);
  const dateParam = urlParams.get('date');
  
  if (dateParam) {
    // Konvertiere YYYY-MM-DD zu DD.MM.YYYY
    const dayId = dateInputToDayId(dateParam);
    await loadDay(dayId);
  } else {
    const todayId = getCurrentDayId();
    await loadDay(todayId);
  }
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
 * Hauptinitialisierung
 */
async function initializeApp() {
  try {
    // Zurück-Button Event Listener
    const backBtn = document.getElementById("backBtn");
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
    
    userAuthData = await waitForAuthData();
    console.log(`✅ OVD Einsatztagebuch - Auth-Daten empfangen: Role ${userAuthData.role}, Company ${userAuthData.companyId}`);

    // Zeige Einstellungsbutton nur für berechtigte Rollen
    // Zeige Drucken und PDF speichern Buttons (immer sichtbar, wenn Tag geladen)
    if (printDayBtn) {
      printDayBtn.style.display = 'flex';
    }
    if (savePdfDayBtn) {
      savePdfDayBtn.style.display = 'flex';
    }
    
    // Zeige Settings-Button nur für berechtigte Rollen
    if (settingsBtn && canAccessSettings()) {
      settingsBtn.style.display = 'flex';
    }

    // Lade Ereignisse und fülle Dropdown
    await fillEventTypeDropdown();

    // Initialisiere den aktuellen Tag
    await initializeDay();

    console.log("✅ OVD Einsatztagebuch Modul initialisiert");
  } catch (error) {
    console.error("❌ Fehler bei der Initialisierung:", error);
    mainContent.innerHTML = '<div class="error-message">Fehler beim Laden des Moduls.</div>';
  }
}


// Starte Initialisierung
window.addEventListener("DOMContentLoaded", initializeApp);

// Sende IFRAME_READY sofort, falls Parent bereits bereit ist
if (window.parent) {
  window.parent.postMessage({ type: "IFRAME_READY" }, "*");
}





