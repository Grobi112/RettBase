// login.js
// Login-Funktionalität für RettBase

import { auth, login, logout, onAuthStateChanged } from "./auth.js";
import { sendPasswordResetEmail } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

// 🔥 KRITISCH: Service Worker für Login-Seite DEAKTIVIERT
// Der Service Worker wird erst nach erfolgreichem Login im Dashboard registriert
// Dies stellt sicher, dass Login in WebApps IMMER funktioniert
if ('serviceWorker' in navigator) {
    // Prüfe ob bereits ein Service Worker aktiv ist
    navigator.serviceWorker.getRegistrations().then((registrations) => {
        // Deaktiviere alle Service Worker für die Login-Seite
        registrations.forEach((registration) => {
            registration.unregister().then((success) => {
                if (success) {
                    console.log('✅ Service Worker für Login-Seite deaktiviert');
                }
            }).catch((error) => {
                console.warn('⚠️ Konnte Service Worker nicht deaktivieren:', error);
            });
        });
    }).catch((error) => {
        console.warn('⚠️ Konnte Service Worker-Registrierungen nicht abrufen:', error);
    });
    
    // Verhindere automatische Registrierung neuer Service Worker auf Login-Seite
    // Der Service Worker wird erst im Dashboard registriert
    console.log('✅ Service Worker wird auf Login-Seite nicht registriert - Login sollte jetzt zuverlässig funktionieren');
}

// DOM-Elemente - werden dynamisch gesucht, falls beim ersten Laden noch nicht verfügbar
let loginForm, emailOrPersonalnummerInput, passwordInput, errorMessage, passwordToggle, eyeIcon;

// Funktion zum Initialisieren der DOM-Elemente
function initDOMElements() {
  loginForm = document.getElementById("login-form");
  emailOrPersonalnummerInput = document.getElementById("emailOrPersonalnummer");
  passwordInput = document.getElementById("password");
  errorMessage = document.getElementById("error-message");
  passwordToggle = document.getElementById("passwordToggle");
  eyeIcon = document.getElementById("eyeIcon");
  
  // Prüfe ob alle kritischen Elemente vorhanden sind
  if (!emailOrPersonalnummerInput) {
    console.error("❌ Kritisch: emailOrPersonalnummerInput nicht gefunden!");
    return false;
  }
  return true;
}

// ⚡ PWA-FIX: Stelle sicher, dass Input-Felder fokussiert werden können
// Dies behebt das Problem, dass die Tastatur beim ersten Öffnen einer neu installierten WebApp nicht erscheint
function focusFirstInput(retries = 10, delay = 200) {
  // Prüfe ob Input-Feld verfügbar ist
  const input = document.getElementById('emailOrPersonalnummer');
  
  if (!input) {
    // Input-Feld noch nicht verfügbar - Retry
    if (retries > 0) {
      console.log(`🔄 Input-Feld noch nicht verfügbar, warte ${delay}ms... (${retries} Versuche übrig)`);
      setTimeout(() => focusFirstInput(retries - 1, delay), delay);
    } else {
      console.warn("⚠️ Input-Feld konnte nach mehreren Versuchen nicht gefunden werden");
    }
    return;
  }
  
  if (retries <= 0) {
    console.warn("⚠️ Max. Fokus-Versuche erreicht");
    return;
  }
  
  try {
    // Versuche zu fokussieren
    input.focus();
    
    // Zusätzlich: Versuche setSelectionRange (hilft manchmal beim Öffnen der Tastatur)
    try {
      if (input.setSelectionRange) {
        setTimeout(() => {
          input.setSelectionRange(0, 0);
        }, 50);
      }
    } catch (e) {
      // Ignoriere Fehler bei setSelectionRange
    }
    
    // Prüfe ob Fokus erfolgreich war (mit kurzer Verzögerung)
    setTimeout(() => {
      if (document.activeElement === input) {
        console.log("✅ Erstes Input-Feld erfolgreich fokussiert");
        return;
      }
      
      // Falls Fokus nicht erfolgreich: Retry mit längerer Verzögerung
      if (retries > 1) {
        console.log(`🔄 Fokus-Versuch ${11 - retries} fehlgeschlagen (activeElement: ${document.activeElement?.tagName}), versuche erneut in ${delay}ms...`);
        focusFirstInput(retries - 1, Math.min(delay * 1.2, 1000)); // Max 1 Sekunde Delay
      } else {
        console.warn("⚠️ Konnte Input-Feld nicht fokussieren nach allen Versuchen");
      }
    }, 100);
    
  } catch (error) {
    console.warn("⚠️ Fehler beim Fokussieren:", error);
    if (retries > 1) {
      setTimeout(() => focusFirstInput(retries - 1, Math.min(delay * 1.2, 1000)), delay);
    }
  }
}

function ensureInputFocus() {
  // Sofort versuchen, wenn DOM bereits geladen ist
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    setTimeout(() => focusFirstInput(), 100);
  } else {
    // Warte auf DOMContentLoaded
    document.addEventListener('DOMContentLoaded', () => {
      setTimeout(() => focusFirstInput(), 100);
    }, { once: true });
  }
}

// ⚡ PWA-FIX: Touch-Event-Handler für bessere Kompatibilität
// Manche PWAs benötigen einen expliziten Touch-Event, bevor Input-Felder fokussiert werden können
function setupTouchHandlers() {
  // Stelle sicher, dass DOM-Elemente initialisiert sind
  if (!initDOMElements()) {
    console.warn("⚠️ DOM-Elemente noch nicht verfügbar für setupTouchHandlers - versuche später");
    // Retry nach kurzer Verzögerung
    setTimeout(setupTouchHandlers, 200);
    return;
  }
  
  // Füge Touch-Event-Listener zu Input-Feldern hinzu
  [emailOrPersonalnummerInput, passwordInput].forEach(input => {
    if (input) {
      // Entferne alte Listener falls vorhanden (verhindert Duplikate)
      const touchHandler = (e) => {
        // Verhindere Standard-Verhalten nicht, damit die Tastatur erscheint
        if (document.activeElement !== input) {
          input.focus();
          // Zusätzlich: Versuche Tastatur explizit zu öffnen
          if (input.setSelectionRange && input.value.length === 0) {
            setTimeout(() => {
              input.setSelectionRange(0, 0);
            }, 50);
          }
        }
      };
      
      // Touch-Start Event: Stelle sicher, dass das Feld fokussiert wird
      input.addEventListener('touchstart', touchHandler, { passive: true });
      
      // Touch-End Event (manche Geräte benötigen das)
      input.addEventListener('touchend', (e) => {
        e.preventDefault(); // Verhindere doppelte Events
        if (document.activeElement !== input) {
          input.focus();
        }
      }, { passive: false });
      
      // Click Event als Fallback (für Desktop/Maus)
      input.addEventListener('click', touchHandler);
      
      // Focus Event: Stelle sicher, dass Tastatur erscheint
      input.addEventListener('focus', () => {
        console.log('✅ Input-Feld hat Fokus erhalten');
        // Zusätzlicher Versuch, Tastatur zu öffnen
        if (input.setSelectionRange && input === emailOrPersonalnummerInput) {
          setTimeout(() => {
            try {
              input.setSelectionRange(0, 0);
            } catch (e) {
              // Ignoriere Fehler bei setSelectionRange (bei readonly-Feldern)
            }
          }, 100);
        }
      });
    }
  });
}

// ⚡ PWA-FIX: Initialisiere alles nach DOMContentLoaded
// Das stellt sicher, dass alle DOM-Elemente verfügbar sind
document.addEventListener('DOMContentLoaded', () => {
  console.log('📄 DOMContentLoaded - initialisiere Login...');
  
  // Initialisiere DOM-Elemente
  if (!initDOMElements()) {
    console.error('❌ Kritisch: DOM-Elemente konnten nicht initialisiert werden!');
    return;
  }
  
  // Initialisiere Touch-Handler
  setupTouchHandlers();
  
  // ⚡ PWA-FIX: Beim ersten Laden einer WebApp: Warte auf User-Interaktion für Focus
  // PWAs erlauben Focus oft erst nach User-Interaktion (z.B. Touch auf Seite)
  const isFirstLoad = !sessionStorage.getItem('webappInitialized');
  if (isFirstLoad) {
    console.log('🆕 Erster Laden einer WebApp erkannt - warte auf User-Interaktion für Focus');
    sessionStorage.setItem('webappInitialized', 'true');
    
    // Beim ersten Laden: Fokussiere erst nach User-Interaktion (Touch/Click)
    // Das umgeht die Browser-Beschränkung, dass Focus ohne User-Interaktion nicht erlaubt ist
    const enableFocusOnInteraction = () => {
      console.log('👆 User-Interaktion erkannt - aktiviere Focus...');
      setTimeout(() => {
        focusFirstInput(15, 150);
      }, 100);
    };
    
    // Warte auf verschiedene User-Interaktionen
    document.addEventListener('touchstart', enableFocusOnInteraction, { once: true, passive: true });
    document.addEventListener('click', enableFocusOnInteraction, { once: true });
    
    // Zusätzlich: Versuche Focus nach längerer Verzögerung (falls User bereits interagiert hat)
    setTimeout(() => {
      focusFirstInput(10, 200);
    }, 1500); // Längere Verzögerung für WebApp-Erststart
  } else {
    // Normale Focus-Strategie für nachfolgende Ladungen
    setTimeout(() => {
      focusFirstInput(10, 200);
    }, 400);
  }
}, { once: true });

// ⚡ PWA-FIX: pageshow Event - wichtig für PWAs
// Wird auch beim ersten Laden einer WebApp getriggert
window.addEventListener('pageshow', (event) => {
  console.log('📖 Page shown (persisted:', event.persisted, ') - versuche Fokus...');
  if (initDOMElements() && emailOrPersonalnummerInput) {
    // Bei persisted oder beim ersten Laden: Focus versuchen mit längerer Verzögerung
    setTimeout(() => focusFirstInput(10, 200), event.persisted ? 300 : 600);
  }
}, { once: true });

// Bei vollständigem Laden (load Event) - zusätzlicher Versuch
window.addEventListener('load', () => {
  console.log('📦 Window loaded - versuche Fokus...');
  if (initDOMElements() && emailOrPersonalnummerInput) {
    // Beim ersten Laden: Längere Verzögerung
    const isFirstLoad = !sessionStorage.getItem('webappInitialized');
    setTimeout(() => focusFirstInput(8, 250), isFirstLoad ? 800 : 500);
  }
}, { once: true });

// Visibility-Change: Wenn App wieder sichtbar wird
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && initDOMElements() && emailOrPersonalnummerInput) {
    if (document.activeElement !== emailOrPersonalnummerInput) {
      setTimeout(() => focusFirstInput(5, 300), 150);
    }
  }
});

// Initialisiere Event-Handler nach DOMContentLoaded
document.addEventListener('DOMContentLoaded', () => {
  // Stelle sicher, dass alle Elemente verfügbar sind
  if (!initDOMElements()) {
    console.error('❌ Kritisch: Kann Event-Handler nicht initialisieren - DOM-Elemente fehlen!');
    return;
  }
  
  // Passwort anzeigen/verstecken Toggle
  if (passwordToggle && passwordInput && eyeIcon) {
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
  }
  
  // Prüfe auf Fehlermeldung aus sessionStorage (nach Redirect-Verhinderung/Reload)
  if (errorMessage) {
    const loginError = sessionStorage.getItem('rettbase_login_error') || sessionStorage.getItem('loginError');
    if (loginError) {
      errorMessage.textContent = loginError;
      errorMessage.style.color = 'red';
      sessionStorage.removeItem('rettbase_login_error');
      sessionStorage.removeItem('loginError');
      errorMessage.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }
  
  // Auth State Changed Listener
  if (auth) {
    let authStateChangeHandled = false;
    
    onAuthStateChanged(auth, async (user) => {
      if (user && !authStateChangeHandled) {
        // Warte kurz, damit Login-Catch bei Fehlern zuerst laufen kann
        await new Promise(r => setTimeout(r, 150));
        if (sessionStorage.getItem("rettbase_login_error_no_redirect") === "1") {
          sessionStorage.removeItem("rettbase_login_error_no_redirect");
          await logout();
          return;
        }
        console.log("✅ Auth State Changed: User eingeloggt. UID:", user.uid);
        authStateChangeHandled = true;
        try {
          window.location.replace("dashboard.html");
        } catch (error) {
          window.location.href = "dashboard.html";
        }
      } else if (!user) {
        authStateChangeHandled = false;
      }
    });
  }
  
  // Form Submit Handler
  if (loginForm) {
    loginForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (!errorMessage || !emailOrPersonalnummerInput || !passwordInput) {
        console.error("❌ Kritisch: DOM-Elemente nicht verfügbar für Form-Submit!");
        return;
      }
      
      errorMessage.textContent = "";

      let emailOrPersonalnummer = emailOrPersonalnummerInput.value.trim();
      const password = passwordInput.value;

      if (!emailOrPersonalnummer || !password) {
        errorMessage.textContent = "❌ Bitte E-Mail/Personalnummer und Passwort eingeben.";
        errorMessage.style.color = 'red';
        return;
      }

      // Wenn keine @ enthält: Personalnummer – ergänze zu personalnummer@subdomain.rettbase.de
      if (!emailOrPersonalnummer.includes("@")) {
        const hostname = window.location.hostname;
        const subdomain = (hostname.split('.')[0] || 'admin').toLowerCase();
        if (subdomain !== 'www' && subdomain !== 'login') {
          emailOrPersonalnummer = `${emailOrPersonalnummer}@${subdomain}.rettbase.de`;
          console.log(`🔍 Personalnummer erkannt, Login als: ${emailOrPersonalnummer}`);
        }
      }

      try {
        const hostname = window.location.hostname;
        const subdomain = hostname.split('.')[0];
        console.log(`🔍 Login-Versuch für Subdomain: ${subdomain}`);
        
        await login(emailOrPersonalnummer, password);
        
        console.log("✅ Login-Aufruf erfolgreich – warte auf Weiterleitung...");
        
        // onAuthStateChanged wird automatisch ausgelöst und leitet weiter

      } catch (error) {
        console.error("❌ Login Fehler:", error);
        const errorCode = error.code || error.type || '';
        const errorMessageText = error.message || '';
        let msg = "Fehler beim Anmelden.";
        
        if (errorCode === 'auth/password-reset-email-sent' || errorMessageText.includes('password-reset-email-sent')) {
          msg = "✅ Eine Passwort-Reset-Email wurde an Ihre E-Mail-Adresse gesendet.";
        } else if (errorCode === 'auth/password-reset-required' || errorMessageText.includes('password-reset-required')) {
          msg = "Passwort zurückgesetzt – bitte 'Passwort vergessen' nutzen.";
        } else if (errorCode === 404 || errorMessageText.includes('user_not_found') || errorMessageText.includes('auth/user-not-found')) {
          msg = "❌ E-Mail oder Personalnummer ist nicht registriert.";
        } else if (errorCode === 401 || errorCode === 'auth/wrong-password' || errorCode === 'auth/invalid-credential') {
          msg = "❌ E-Mail/Personalnummer oder Passwort ist falsch.";
        } else if (errorCode === 400 || errorCode === 'auth/invalid-email' || errorMessageText.includes('Invalid query')) {
          msg = errorMessageText.includes('Invalid query') ? "❌ Datenbankfehler – Administrator kontaktieren." : "❌ Ungültiges E-Mail-Format.";
        } else if (errorCode === 429 || errorCode === 'auth/too-many-requests') {
          msg = "❌ Zu viele Versuche – bitte später erneut probieren.";
        } else if (errorCode === 'permission-denied' || errorMessageText.includes('permission') || errorMessageText.includes('insufficient permissions')) {
          msg = "❌ Zugriff verweigert – Administrator soll den Mitarbeiter erneut speichern (Bearbeiten → Speichern).";
        } else if (errorMessageText.includes('Failed to fetch') || errorMessageText.includes('network')) {
          msg = "❌ Netzwerkfehler – Internetverbindung prüfen.";
        } else {
          msg = `❌ Fehler: ${errorMessageText || 'Unbekannter Fehler'}`;
        }
        
        sessionStorage.setItem("rettbase_login_error", msg);
        sessionStorage.setItem("rettbase_login_error_no_redirect", "1");
        if (errorMessage) {
          errorMessage.textContent = msg;
          errorMessage.style.color = 'red';
          errorMessage.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      }
    });
  }

  // Passwort zurücksetzen Funktionalität
  const forgotPasswordLink = document.getElementById("forgotPasswordLink");
  const resetPasswordModal = document.getElementById("resetPasswordModal");
  const closeResetModal = document.getElementById("closeResetModal");
  const cancelResetPassword = document.getElementById("cancelResetPassword");
  const resetPasswordForm = document.getElementById("resetPasswordForm");
  const resetEmailInput = document.getElementById("resetEmail");
  const resetPasswordMessage = document.getElementById("resetPasswordMessage");

  // Modal öffnen
  if (forgotPasswordLink) {
    forgotPasswordLink.addEventListener("click", (e) => {
      e.preventDefault();
      resetPasswordModal.classList.add("active");
      resetEmailInput.value = emailOrPersonalnummerInput?.value || "";
      resetEmailInput.focus();
      resetPasswordMessage.textContent = "";
      resetPasswordMessage.className = "";
    });
  }

  // Modal schließen
  function closeResetModalFunc() {
    resetPasswordModal.classList.remove("active");
    resetPasswordForm.reset();
    resetPasswordMessage.textContent = "";
    resetPasswordMessage.className = "";
  }

  if (closeResetModal) {
    closeResetModal.addEventListener("click", closeResetModalFunc);
  }

  if (cancelResetPassword) {
    cancelResetPassword.addEventListener("click", closeResetModalFunc);
  }

  // Klick außerhalb des Modals schließt es
  if (resetPasswordModal) {
    resetPasswordModal.addEventListener("click", (e) => {
      if (e.target === resetPasswordModal) {
        closeResetModalFunc();
      }
    });
  }

  // Passwort-Reset-Formular absenden
  if (resetPasswordForm) {
    resetPasswordForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      
      const email = resetEmailInput.value.trim();
      
      if (!email) {
        resetPasswordMessage.textContent = "Bitte geben Sie eine E-Mail-Adresse ein.";
        resetPasswordMessage.className = "error";
        return;
      }

      // Validiere E-Mail-Format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        resetPasswordMessage.textContent = "Bitte geben Sie eine gültige E-Mail-Adresse ein.";
        resetPasswordMessage.className = "error";
        return;
      }

      resetPasswordMessage.textContent = "Sende E-Mail...";
      resetPasswordMessage.className = "";

      try {
        // Konfiguriere die Action URL, damit der Link auf unsere eigene reset-password.html Seite zeigt
        const actionCodeSettings = {
          url: window.location.origin + '/reset-password.html',
          handleCodeInApp: false
        };
        
        await sendPasswordResetEmail(auth, email, actionCodeSettings);
        resetPasswordMessage.textContent = "✅ Eine E-Mail zum Zurücksetzen des Passworts wurde an " + email + " gesendet. Bitte überprüfen Sie Ihr Postfach.";
        resetPasswordMessage.className = "success";
        resetPasswordForm.reset();
        
        // Modal nach 3 Sekunden automatisch schließen
        setTimeout(() => {
          closeResetModalFunc();
        }, 3000);
      } catch (error) {
        console.error("Fehler beim Senden der Passwort-Reset-Email:", error);
        
        let errorMsg = "Fehler beim Senden der E-Mail. Bitte versuchen Sie es erneut.";
        
        if (error.code === "auth/user-not-found") {
          errorMsg = "❌ Diese E-Mail-Adresse ist nicht registriert.";
        } else if (error.code === "auth/invalid-email") {
          errorMsg = "❌ Ungültige E-Mail-Adresse.";
        } else if (error.code === "auth/too-many-requests") {
          errorMsg = "❌ Zu viele Anfragen. Bitte versuchen Sie es später erneut.";
        } else if (error.message) {
          errorMsg = "❌ " + error.message;
        }
        
        resetPasswordMessage.textContent = errorMsg;
        resetPasswordMessage.className = "error";
      }
    });
  }
});

