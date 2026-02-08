// Datei: firebase-config.js

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js"; 
import { getFirestore, enableMultiTabIndexedDbPersistence } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-storage.js";

// 🔥 Deine Firebase Konfiguration (mit deinen Live-Daten)
const firebaseConfig = {
    apiKey: "AIzaSyCBpI6-cT5PDbRzjNPsx_k03np4JK8AJtA", 
    authDomain: "rett-fe0fa.firebaseapp.com",
    projectId: "rett-fe0fa",
    storageBucket: "rett-fe0fa.firebasestorage.app",
    messagingSenderId: "740721219821",
    appId: "1:740721219821:web:a8e7f8070f875866ccd4e4"
    // measurementId kann optional hinzugefügt werden, falls benötigt.
};

// Initialisiere Firebase App
const app = initializeApp(firebaseConfig);

// Exportiere die Dienste-Instanzen
export const auth = getAuth(app);

// 🔥 Firestore initialisieren
export const db = getFirestore(app);

// 🔥 Storage initialisieren
export const storage = getStorage(app);

// 🔥 Aktiviere Multi-Tab-Persistenz NUR außerhalb der Login-Seite
// Auf der Login-Seite kann Persistenz beim ersten Laden (Cache geleert) zu Cold-Start-Problemen führen
const isLoginPage = typeof window !== 'undefined' && /login\.html?$/i.test(window.location.pathname || '');
if (!isLoginPage) {
  enableMultiTabIndexedDbPersistence(db).catch((err) => {
    if (err.code == 'failed-precondition') {
      console.debug("ℹ️ Offline-Persistenz bereits aktiviert");
    } else if (err.code == 'unimplemented') {
      console.debug("ℹ️ Browser unterstützt keine Offline-Persistenz");
    } else {
      console.warn("⚠️ Fehler beim Aktivieren der Multi-Tab-Persistenz:", err);
    }
  });
  console.log("✅ Firestore initialisiert mit Multi-Tab-Persistenz");
} else {
  console.log("✅ Firestore initialisiert (ohne Persistenz auf Login-Seite)");
}

export default app;