// login.js
// Login-Funktionalität für RettBase

import { auth, login, onAuthStateChanged } from "./auth.js";

const loginForm = document.getElementById("login-form");
const emailOrPersonalnummerInput = document.getElementById("emailOrPersonalnummer");
const passwordInput = document.getElementById("password");
const errorMessage = document.getElementById("error-message");
const passwordToggle = document.getElementById("passwordToggle");
const eyeIcon = document.getElementById("eyeIcon");

// Passwort anzeigen/verstecken Toggle
passwordToggle.addEventListener("click", () => {
  const isPassword = passwordInput.type === "password";
  passwordInput.type = isPassword ? "text" : "password";
  
  // Ändere das Icon (Auge offen/geschlossen)
  if (isPassword) {
    // Zeige geschlossenes Auge (Passwort ist sichtbar)
    eyeIcon.innerHTML = `
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
      <line x1="1" y1="1" x2="23" y2="23"></line>
    `;
  } else {
    // Zeige offenes Auge (Passwort ist versteckt)
    eyeIcon.innerHTML = `
      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
      <circle cx="12" cy="12" r="3"></circle>
    `;
  }
});

// Prüfe auf Fehlermeldung aus sessionStorage (z.B. "Zugang gesperrt")
const loginError = sessionStorage.getItem('loginError');
if (loginError) {
    errorMessage.textContent = loginError;
    errorMessage.style.color = 'red';
    sessionStorage.removeItem('loginError');
}

onAuthStateChanged(auth, (user) => {
    if (user) {
        console.log("✅ Auth State Changed: Leite zu dashboard.html weiter.");
        window.location.href = "dashboard.html";
    }
});

loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  errorMessage.textContent = "";

  const emailOrPersonalnummer = emailOrPersonalnummerInput.value.trim();
  const password = passwordInput.value;

  if (!emailOrPersonalnummer || !password) {
    errorMessage.textContent = "❌ Bitte E-Mail/Personalnummer und Passwort eingeben.";
    errorMessage.style.color = 'red';
    return;
  }

  try {
    // Prüfe die Subdomain, um zu sehen, für welche Firma der Login ist
    const hostname = window.location.hostname;
    const subdomain = hostname.split('.')[0];
    console.log(`🔍 Login-Versuch für Subdomain: ${subdomain}`);
    
    // Ruft die erweiterte 'login' Funktion auf (unterstützt E-Mail oder Personalnummer)
    await login(emailOrPersonalnummer, password);
    
    console.log("✅ Login-Aufruf erfolgreich. Warte auf Firebase Auth State Change...");

  } catch (error) {
    console.error("❌ Login Fehler:", error);
    console.error("   Fehler-Code:", error.code);
    console.error("   Fehler-Message:", error.message);
    
    let msg = "Fehler beim Anmelden.";
    
    if (error.code === "auth/user-not-found") {
        msg = "❌ Diese E-Mail-Adresse oder Personalnummer ist nicht registriert.";
    } else if (error.code === "auth/wrong-password") {
        msg = "❌ Das Passwort ist falsch.";
    } else if (error.code === "auth/invalid-credential") {
        msg = "❌ E-Mail/Personalnummer oder Passwort ist falsch. Bitte überprüfe deine Anmeldedaten.";
    } else if (error.code === "auth/invalid-email") {
        msg = "❌ Ungültiges E-Mail-Format.";
    } else if (error.code === "auth/too-many-requests") {
        msg = "❌ Zu viele fehlgeschlagene Anmeldeversuche. Bitte versuche es später erneut.";
    } else if (error.code === "auth/network-request-failed") {
        msg = "❌ Netzwerkfehler. Bitte überprüfe deine Internetverbindung.";
    } else {
         msg = `❌ Ein unerwarteter Fehler ist aufgetreten: ${error.message}`;
    }
    
    errorMessage.textContent = msg;
    errorMessage.style.color = 'red';
  }
});

