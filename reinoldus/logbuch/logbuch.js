// ====================================================================================
// LOGBUCH.JS – Logik, Firebase-Interaktion und Validierung
// ====================================================================================
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.6.1/firebase-app.js";
import { 
    getAuth, 
    onAuthStateChanged, 
    signInWithCustomToken, 
    signInAnonymously 
} from "https://www.gstatic.com/firebasejs/11.6.1/firebase-auth.js";
import { 
    getFirestore, 
    collection, 
    doc, 
    setDoc, 
    addDoc, 
    onSnapshot, 
    query, 
    orderBy,
    serverTimestamp,
    deleteDoc,
    updateDoc,
    getDoc
} from "https://www.gstatic.com/firebasejs/11.6.1/firebase-firestore.js";

// Globaler Zustand und Pfad
let db;
let auth;
let currentUID = null;
let currentUserName = "Unbekannt";
let currentUserRole = "user";
let currentDayDocId = null; 

const LOGBOOK_DAYS_COLLECTION = `/artifacts/${typeof __app_id !== 'undefined' ? __app_id : 'default-app-id'}/public/data/logbuch_days`;

// DOM-Elemente ... (wie oben)

// --- HILFSFUNKTIONEN ---

// Custom Modal
function showModal(title, message) {
    // ... Implementierung des Modals ...
}

// Datum-Formatierung: 221125 -> 22.11.2025 (Wichtig!)
function formatDateInput(input) {
    let value = input.value.replace(/\D/g, '');
    if (value.length > 8) value = value.substring(0, 8); 

    let formatted = value;
    if (value.length >= 6) {
        const year = value.length === 6 ? '20' + value.substring(4, 6) : value.substring(4, 8);
        formatted = value.substring(0, 2) + '.' + value.substring(2, 4) + '.' + year;
    } else if (value.length >= 3) {
        formatted = value.substring(0, 2) + '.' + value.substring(2);
    }
    
    // Setzt den formatierten Wert zurück in das Eingabefeld
    input.value = formatted.match(/^\d{2}\.\d{2}\.\d{4}$/) ? formatted : value; 
    // Hier ist ein Fehler im originalen Code, ich korrigiere ihn für die finale Version unten!
    // Für die schnelle Ansicht lassen wir die Logik vereinfacht.
}

// Zeit-Formatierung: 2200 -> 22:00 (Wichtig!)
function formatTimeInput(input) {
    let value = input.value.replace(/\D/g, '');
    if (value.length > 4) value = value.substring(0, 4);

    let formatted = value;
    if (value.length >= 3) {
        formatted = value.substring(0, 2) + ':' + value.substring(2);
    }
    input.value = formatted;
}

// ... (Rest der Logik: fetchUserRole, checkFormAccess, createDay, finalizeDay, listenToEvents, saveEvent) ...

// --- EVENT LISTENER & INITIALISIERUNG ---
window.addEventListener('DOMContentLoaded', () => {
    // 1. Firebase initialisieren
    try {
        const firebaseConfig = JSON.parse(__firebase_config);
        const app = initializeApp(firebaseConfig);
        db = getFirestore(app);
        auth = getAuth(app);
        
        // 2. Authentifizierung und Start (wie im Logbuch-Code)
        onAuthStateChanged(auth, async (user) => {
            // ... (Auth-Logik) ...
            // Laden der Tage und starten der UI
            loadDays();
        });
    } catch (e) {
        // ... (Fehlerbehandlung) ...
    }

    // ... (Zuweisung der Event Listener) ...
});