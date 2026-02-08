// firebase-config.js
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyB_PRdGdU_f18VeKlrBUqStc6pXVu3tU04",
  authDomain: "reinoldus-f4dc3.firebaseapp.com",
  projectId: "reinoldus-f4dc3",
  storageBucket: "reinoldus-f4dc3.firebasestorage.app",
  messagingSenderId: "518113038751",
  appId: "1:518113038751:web:04cdccdfb7b43ea0c06daa",
  measurementId: "G-CCGFYRWEH1"
};

// Firebase nur einmal initialisieren
const app = initializeApp(firebaseConfig);

// Exporte
export const auth = getAuth(app);
export const db = getFirestore(app);
