// Datei: firebase-config.js

import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js"; 
import { getFirestore, enableMultiTabIndexedDbPersistence } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-storage.js";

// 🔥 Firebase rettbase-app – einheitlich für alle RettBase-Systeme
const firebaseConfig = {
    apiKey: "AIzaSyCl67Qcs2Z655Y0507NG6o9WCL4twr65uc",
    authDomain: "rettbase-app.firebaseapp.com",
    projectId: "rettbase-app",
    storageBucket: "rettbase-app.firebasestorage.app",
    messagingSenderId: "339125193380",
    appId: "1:339125193380:web:350966b45a875fae8eb431"
};

// Initialisiere Firebase App
const app = initializeApp(firebaseConfig);

// Exportiere die Dienste-Instanzen
export const auth = getAuth(app);

// 🔥 Firestore initialisieren
export const db = getFirestore(app);

// 🔥 Storage initialisieren
export const storage = getStorage(app);

// 🔥 Aktiviere Multi-Tab-Persistenz (erlaubt mehrere Tabs gleichzeitig)
// Dies verhindert den "Failed to obtain exclusive access" Fehler
enableMultiTabIndexedDbPersistence(db).catch((err) => {
  if (err.code == 'failed-precondition') {
    // Persistenz bereits aktiviert - das ist OK
    console.debug("ℹ️ Offline-Persistenz bereits aktiviert");
  } else if (err.code == 'unimplemented') {
    // Browser unterstützt keine Offline-Persistenz - das ist OK
    console.debug("ℹ️ Browser unterstützt keine Offline-Persistenz");
  } else {
    // Anderer Fehler - nur dann warnen
    console.warn("⚠️ Fehler beim Aktivieren der Multi-Tab-Persistenz:", err);
  }
});

console.log("✅ Firestore initialisiert mit Multi-Tab-Persistenz");

export default app;