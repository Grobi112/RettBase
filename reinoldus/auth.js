// ===============================
// AUTH.JS – korrigierte Version
// ===============================

import { 
  initializeApp 
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";

import {
  getAuth,
  signInWithEmailAndPassword,
  signOut,
  onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

import {
  getFirestore,
  doc,
  getDoc
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --------------------------------------------------
// Firebase Config
// --------------------------------------------------
const firebaseConfig = {
  apiKey: "AIzaSyB_PRdGdU_f18VeKlrBUqStc6pXVu3tU04",
  authDomain: "reinoldus-f4dc3.firebaseapp.com",
  projectId: "reinoldus-f4dc3",
  storageBucket: "reinoldus-f4dc3.firebasestorage.app",
  messagingSenderId: "518113038751",
  appId: "1:518113038751:web:04cdccdfb7b43ea0c06daa",
  measurementId: "G-CCGFYRWEH1"
};

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const db = getFirestore(app);

// --------------------------------------------------
// LOGIN FUNKTION
// --------------------------------------------------
export async function login(email, password) {
  return await signInWithEmailAndPassword(auth, email, password);
}

// --------------------------------------------------
// LOGOUT FUNKTION
// --------------------------------------------------
export async function logout() {
  return await signOut(auth);
}

// --------------------------------------------------
// NUTZER ROLLEN LADEN (KORRIGIERT)
// --------------------------------------------------
export async function getUserRole(uid) {
  const ref = doc(db, "users", uid);
  try {
    const snap = await getDoc(ref);

    if (snap.exists()) {
      const data = snap.data();
      
      // Explizite Prüfung auf den Wert 'admin'
      if (data.role && data.role.toLowerCase() === 'admin') {
        return 'admin';
      }
    }
    
    // Standard-Rolle für alle anderen Fälle
    return 'user';

  } catch (error) {
    console.error("Fehler beim Abrufen der Rolle:", error);
    return 'user'; 
  }
}