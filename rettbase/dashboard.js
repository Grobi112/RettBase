// dashboard.js 

import { auth, logout, getAuthData, onAuthStateChanged } from "./auth.js"; 
import { getUserModules, getDefaultModulesForRole, initializeDefaultModules, setCompanyModules } from "./modules.js";
import { db } from "./firebase-config.js";
import { 
  collection, 
  doc, 
  getDoc, 
  getDocs, 
  query, 
  where,
  setDoc,
  serverTimestamp,
  onSnapshot
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

const menuToggle = document.getElementById("menuToggle");
const dropdownMenu = document.getElementById("dropdownMenu");
const menuBackdrop = document.getElementById("menuBackdrop");
const contentFrame = document.getElementById("contentFrame");
const logoutLink = document.getElementById("logoutLink");
const userMenuToggle = document.getElementById("userMenuToggle");
const userDropdownMenu = document.getElementById("userDropdownMenu");
const userNameDisplay = document.getElementById("userNameDisplay");
const profileLink = document.getElementById("profileLink");
const chatLink = document.getElementById("chatLink");
const chatUnreadBadge = document.getElementById("chatUnreadBadge");
const chatUnreadIndicator = document.getElementById("chatUnreadIndicator");
const chatUnreadCount = document.getElementById("chatUnreadCount");
const userDropdownLogout = document.getElementById("userDropdownLogout");
const userDropdownBackdrop = document.getElementById("userDropdownBackdrop");

let userAuthData = null;
let userModules = []; // Speichert die für den Benutzer sichtbaren Module
let menuStructure = null; // Gespeicherte Menüstruktur aus Firestore (settings/globalMenu)
let isRenderingMenu = false; // Verhindert mehrfaches gleichzeitiges Rendern
let chatUnreadUnsubscribe = null; // Firestore-Listener für Chat-Unread
let lastChatUnreadCount = 0; // Für AUTH_DATA an iframe

// 🔒 SESSION-TIMEOUT: Automatische Abmeldung nach 30 Minuten Inaktivität
let inactivityTimer = null;
let warningTimer = null;
let activityListenersSetup = false; // Verhindert mehrfache Event-Listener-Registrierung
const INACTIVITY_TIMEOUT = 30 * 60 * 1000; // 30 Minuten in Millisekunden 


/**
 * Sammelt die tatsächlich angezeigten Menüpunkte aus dem Hamburger-Menü
 * Diese Funktion extrahiert alle sichtbaren Menüpunkte (inkl. Submenüs) aus dem DOM
 */
function getVisibleMenuItems() {
    const visibleItems = [];
    
    // Sammle alle sichtbaren Menüpunkte (ohne Container, nur klickbare Items)
    const menuItems = dropdownMenu.querySelectorAll('.menu-item[data-page]:not([data-has-children="true"]), .menu-subitem[data-page]');
    
    menuItems.forEach(item => {
        const itemId = item.dataset.page;
        const itemType = item.dataset.itemType || 'module';
        const label = item.textContent.trim();
        let url = null;
        
        if (itemType === 'custom') {
            // Benutzerdefiniertes Item
            url = item.dataset.url;
            if (!url || url === '#') {
                return; // Container ohne URL - überspringe
            }
        } else {
            // Modul
            const module = userModules.find(m => m.id === itemId);
            if (module) {
                url = module.url;
            } else {
                return; // Modul nicht gefunden - überspringe
            }
        }
        
        if (url) {
            visibleItems.push({
                id: itemId,
                label: label,
                url: url,
                type: itemType
            });
        }
    });
    
    return visibleItems;
}

// --- FUNKTION: DATEN AN IFRAME SENDEN (Handshake-Antwort) ---
function sendAuthDataToIframe(retryCount = 0) {
    const MAX_RETRIES = 10;
    const RETRY_DELAY = 200; // 200ms zwischen Versuchen
    
    // Prüfe ob iFrame existiert und geladen ist
    if (!contentFrame || !contentFrame.contentWindow) {
        // iFrame ist noch nicht bereit - Retry mit Verzögerung
        if (retryCount < MAX_RETRIES) {
            console.log(`🔄 [RETRY ${retryCount + 1}/${MAX_RETRIES}] iFrame noch nicht bereit, warte ${RETRY_DELAY}ms...`);
            setTimeout(() => sendAuthDataToIframe(retryCount + 1), RETRY_DELAY);
        } else {
            console.warn("⚠️ Konnte Auth-Daten nach mehreren Versuchen nicht senden - iFrame nicht verfügbar");
        }
        return;
    }
    
    // Prüfe ob Auth-Daten vorhanden sind
    if (!userAuthData) {
        // Auth-Daten sind noch nicht geladen - Retry mit Verzögerung
        if (retryCount < MAX_RETRIES) {
            console.log(`🔄 [RETRY ${retryCount + 1}/${MAX_RETRIES}] Auth-Daten noch nicht geladen, warte ${RETRY_DELAY}ms...`);
            setTimeout(() => sendAuthDataToIframe(retryCount + 1), RETRY_DELAY);
        } else {
            console.warn("⚠️ Konnte Auth-Daten nach mehreren Versuchen nicht senden - keine Auth-Daten verfügbar");
        }
        return;
    }

    // 🔥 NEU: Sammle die tatsächlich angezeigten Menüpunkte aus dem Hamburger-Menü
    const visibleMenuItems = getVisibleMenuItems();
    
    // ⚡ OPTIMIERT: Sende auch die bereits geladenen Mitarbeiter-Daten mit
    // Das Profil-Iframe muss dann keine zusätzliche Firestore-Abfrage mehr machen
    const authDataToSend = {
        ...userAuthData,
        // Mitarbeiter-Daten werden mitgesendet, wenn vorhanden
        mitarbeiterData: userAuthData.mitarbeiterData || null,
        mitarbeiterDocId: userAuthData.mitarbeiterDocId || null
    };
    
    // 🔥 NEU: Sende auch die verfügbaren Module UND die sichtbaren Menüpunkte an das iframe
    const dataToSend = {
      type: 'AUTH_DATA',
      data: authDataToSend,
      modules: userModules,
      menuItems: visibleMenuItems,
      chatUnreadCount: lastChatUnreadCount
    };
    try {
        // ⚡ WICHTIG: Prüfe, ob iframe wirklich bereit ist (nicht nur ob contentWindow existiert)
        // Versuche zu senden - wenn fehlschlägt, versuche erneut
        try {
            contentFrame.contentWindow.postMessage(dataToSend, '*');
            console.log(`✉️ Auth-Daten (Role: ${userAuthData.role}, Company: ${userAuthData.companyId}), ${userModules.length} Module, ${visibleMenuItems.length} Menüpunkte${userAuthData.mitarbeiterData ? ' + Mitarbeiter-Daten' : ''} gesendet.`);
        } catch (postError) {
            // Wenn postMessage fehlschlägt, versuche erneut
            if (retryCount < MAX_RETRIES) {
                console.log(`🔄 [RETRY ${retryCount + 1}/${MAX_RETRIES}] postMessage fehlgeschlagen, versuche erneut in ${RETRY_DELAY}ms...`);
                setTimeout(() => sendAuthDataToIframe(retryCount + 1), RETRY_DELAY);
            } else {
                console.error("❌ Konnte Auth-Daten nach mehreren Versuchen nicht senden:", postError);
            }
        }
    } catch (error) {
        // Fehler beim Senden - kann passieren wenn iFrame noch nicht vollständig geladen ist
        if (retryCount < MAX_RETRIES) {
            console.log(`🔄 [RETRY ${retryCount + 1}/${MAX_RETRIES}] Fehler beim Senden, versuche erneut in ${RETRY_DELAY}ms:`, error.message);
            setTimeout(() => sendAuthDataToIframe(retryCount + 1), RETRY_DELAY);
        } else {
            console.error("❌ Konnte Auth-Daten nach mehreren Versuchen nicht senden:", error);
        }
    }
}


// --- IFRAME LOAD EVENT: Sende Auth-Daten, wenn iframe geladen wird ---
// ⚡ WICHTIG: Warte bis DOM vollständig geladen ist, bevor wir Event-Listener registrieren
function setupIframeLoadListener() {
    const contentFrame = document.getElementById("contentFrame");
    if (contentFrame) {
        contentFrame.addEventListener('load', () => {
            console.log("📥 iframe load event - sende Auth-Daten...");
            // Warte kurz, damit das iframe vollständig initialisiert ist (besonders wichtig im PWA-Modus)
            setTimeout(() => {
                if (userAuthData) {
                    console.log("🔄 [LOAD] Sende Auth-Daten nach iframe load event...");
                    sendAuthDataToIframe();
                } else {
                    console.log("⏳ [LOAD] Auth-Daten noch nicht verfügbar, warte...");
                    // Versuche nochmal nach kurzer Verzögerung
                    setTimeout(() => {
                        if (userAuthData) {
                            console.log("🔄 [LOAD RETRY] Sende Auth-Daten nach Verzögerung...");
                            sendAuthDataToIframe();
                        }
                    }, 500);
                }
            }, 200); // Erhöhte Verzögerung für PWA-Modus
        });
        console.log("✅ iframe load event listener registriert");
    } else {
        console.warn("⚠️ contentFrame nicht gefunden beim Setup des Load-Listeners");
        // Versuche nochmal nach kurzer Verzögerung
        setTimeout(setupIframeLoadListener, 100);
    }
}

// Initialisiere iframe load listener nach DOM-Laden
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', setupIframeLoadListener);
} else {
    setupIframeLoadListener();
}

// --- HANDSHAKE-LISTENER: Empfängt die 'READY' Nachricht vom iFrame ---
window.addEventListener('message', async (event) => {
    // ⚡ WICHTIG: Im PWA-Modus kann event.source unterschiedlich sein
    // Prüfe ob contentFrame.contentWindow existiert, bevor wir vergleichen
    // Akzeptiere auch Nachrichten, wenn event.source === window (für PWA)
    const isFromIframe = contentFrame && contentFrame.contentWindow && event.source === contentFrame.contentWindow;
    const isFromParent = event.source === window.parent || event.source === window;
    
    // Ignoriere Nachrichten, die nicht vom iframe oder parent kommen
    if (!isFromIframe && !isFromParent && event.source !== window) {
        return;
    }

    if (event.data && event.data.type === 'IFRAME_READY') {
        console.log("🤝 Handshake empfangen: iFrame ist bereit.");
        sendAuthDataToIframe(); 
    }
    
    // Reagiere auf Modul-Änderungen: Lade Module neu und aktualisiere Menü
    // 🔥 WICHTIG: Nur verarbeiten, wenn wirklich Module geändert wurden (reason === 'saved')
    // Verhindert unnötiges Re-Rendering bei normaler Navigation
    if (event.data && event.data.type === 'MODULES_UPDATED' && event.data.reason === 'saved') {
        console.log("🔄 Module wurden aktualisiert (reason: saved), lade Menü neu...");
        if (userAuthData && !isRenderingMenu) {
            userModules = await getUserModules(userAuthData.companyId, userAuthData.role);
            menuStructure = null; // Lade Menüstruktur neu
            console.log(`📋 Module neu geladen:`, userModules.map(m => `${m.label} (${m.id})`));
            await safeRenderMenu();
            sendAuthDataToIframe(); // Aktualisiere auch die Module im iframe
        }
    } else if (event.data && event.data.type === 'MODULES_UPDATED' && event.data.reason !== 'saved') {
        console.debug("⚠️ MODULES_UPDATED ohne reason='saved' ignoriert (normale Navigation?)");
    }
    
    // 🔥 NEU: Reagiere auf Menü-Änderungen: Lade globale Menüstruktur neu und rendere Menü
    if (event.data && event.data.type === 'MENU_UPDATED') {
        console.log("🔄 Globale Menüstruktur wurde aktualisiert, lade Menü neu...");
        if (userAuthData && !isRenderingMenu) {
            // Globale Menüstruktur gilt für alle Firmen - immer neu laden
            menuStructure = null; // Lade Menüstruktur neu
            await loadMenuStructure(); // Explizit neu laden
            await safeRenderMenu();
            console.log("✅ Menü wurde aktualisiert (global)");
        }
    }
    
    // Reagiere auf Navigation-Requests vom iframe (z.B. von Profil-Seite zurück zu Home)
    if (event.data && event.data.type === 'NAVIGATE_TO_HOME') {
        const homeModule = userModules.find(m => m.id === 'home');
        if (homeModule && contentFrame) {
            contentFrame.src = homeModule.url;
        }
    }

    // Chat: In neuem Tab öffnen (Workaround für Mikrofon-Berechtigung im iframe)
    if (event.data && event.data.type === 'OPEN_CHAT_IN_NEW_TAB' && userAuthData) {
        try {
            const authData = {
                uid: userAuthData.uid,
                companyId: userAuthData.companyId,
                role: userAuthData.role,
                email: userAuthData.email,
                mitarbeiterData: userAuthData.mitarbeiterData
            };
            localStorage.setItem('rettbase_chat_auth', JSON.stringify(authData));
            const chatUrl = window.location.origin + '/module/chat/chat.html';
            window.open(chatUrl, '_blank', 'noopener');
        } catch (e) { console.error('Chat in neuem Tab:', e); }
    }
});


// Initialisiere beim Laden
window.onload = () => {
    // contentFrame.src wird nach dem Laden der Module gesetzt
};

// --- EVENTS ---

/**
 * Schließt alle geöffneten Submenüs im Hamburger-Menü
 */
function closeAllSubmenus() {
    // Finde alle geöffneten Submenüs (display !== 'none')
    const openSubmenus = dropdownMenu.querySelectorAll('.menu-submenu');
    openSubmenus.forEach(submenu => {
        if (submenu.style.display !== 'none') {
            submenu.style.display = 'none';
        }
    });
    
    // Entferne 'expanded' Klasse von allen Menu-Items
    const expandedItems = dropdownMenu.querySelectorAll('.menu-item.expanded');
    expandedItems.forEach(item => {
        item.classList.remove('expanded');
    });
    
    // Setze alle Pfeile zurück (rotation = 0deg)
    const arrows = dropdownMenu.querySelectorAll('.menu-arrow');
    arrows.forEach(arrow => {
        arrow.style.transform = 'rotate(0deg)';
    });
}

// Funktion zum Schließen des Menüs
function closeMenu() {
    dropdownMenu.classList.remove("show");
    if (menuBackdrop) {
        menuBackdrop.style.display = "none";
    }
    // 🔥 NEU: Schließe alle Submenüs, wenn das Hauptmenü geschlossen wird
    closeAllSubmenus();
}

// Funktion zum Öffnen des Menüs
function openMenu() {
    dropdownMenu.classList.add("show");
    if (menuBackdrop) {
        menuBackdrop.style.display = "block";
    }
    // 🔥 NEU: Stelle sicher, dass alle Submenüs geschlossen sind, wenn das Menü geöffnet wird
    closeAllSubmenus();
}

// Toggle Menu - schaltet zwischen offen/geschlossen um
menuToggle.addEventListener("click", (e) => {
    e.stopPropagation();
    if (dropdownMenu.classList.contains("show")) {
        closeMenu();
    } else {
        openMenu();
    }
});

// Touch-Logik für Menu-Toggle
menuToggle.addEventListener("touchend", (e) => {
    e.stopPropagation();
    e.preventDefault();
    if (dropdownMenu.classList.contains("show")) {
        closeMenu();
    } else {
        openMenu();
    }
}, { passive: false });

// Backdrop: Schließe Menü bei Klick auf Backdrop
if (menuBackdrop) {
    menuBackdrop.addEventListener("click", (e) => {
        e.stopPropagation();
        closeMenu();
    });
    
    menuBackdrop.addEventListener("touchend", (e) => {
        e.stopPropagation();
        closeMenu();
    }, { passive: true });
}

// --- USER DROPDOWN MENU ---

// Funktion zum Schließen des User-Dropdowns
function closeUserMenu() {
    if (userDropdownMenu) {
        userDropdownMenu.classList.remove("show");
        userDropdownMenu.style.display = "none";
    }
    if (userDropdownBackdrop) userDropdownBackdrop.style.display = "none";
}

// Funktion zum Öffnen des User-Dropdowns
function openUserMenu() {
    if (userDropdownMenu) {
        userDropdownMenu.classList.add("show");
        userDropdownMenu.style.display = "flex";
    }
    if (userDropdownBackdrop) userDropdownBackdrop.style.display = "block";
}

// Toggle User Menu
if (userMenuToggle) {
    userMenuToggle.addEventListener("click", (e) => {
        e.stopPropagation();
        if (userDropdownMenu && userDropdownMenu.classList.contains("show")) {
            closeUserMenu();
        } else {
            // Schließe das Hamburger-Menü, falls es offen ist
            closeMenu();
            openUserMenu();
        }
    });
    
    userMenuToggle.addEventListener("touchend", (e) => {
        e.stopPropagation();
        e.preventDefault();
        if (userDropdownMenu && userDropdownMenu.classList.contains("show")) {
            closeUserMenu();
        } else {
            closeMenu();
            openUserMenu();
        }
    }, { passive: false });
}

// Schließe User-Dropdown bei Klick außerhalb oder auf Backdrop
document.addEventListener("click", (e) => {
    if (userMenuToggle && userDropdownMenu && 
        !userMenuToggle.contains(e.target) && 
        !userDropdownMenu.contains(e.target)) {
        closeUserMenu();
    }
});
if (userDropdownBackdrop) {
    userDropdownBackdrop.addEventListener("click", () => closeUserMenu());
    userDropdownBackdrop.addEventListener("touchend", (e) => { e.preventDefault(); closeUserMenu(); }, { passive: false });
}

// Profil-Link Event Listener
if (profileLink) {
    profileLink.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        // Lade Profil-Seite im iframe
        if (contentFrame) {
            contentFrame.src = "profile.html";
        }
    });
    
    profileLink.addEventListener("touchend", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        if (contentFrame) {
            contentFrame.src = "profile.html";
        }
    }, { passive: false });
}

// Chat-Link Event Listener
if (chatLink) {
    chatLink.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        const chatModule = userModules.find(m => m.id === "chat");
        if (contentFrame && chatModule) {
            contentFrame.src = chatModule.url;
        }
    });
    
    chatLink.addEventListener("touchend", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        const chatModule = userModules.find(m => m.id === "chat");
        if (contentFrame && chatModule) {
            contentFrame.src = chatModule.url;
        }
    }, { passive: false });
}

// Logout im User-Dropdown
if (userDropdownLogout) {
    userDropdownLogout.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
            inactivityTimer = null;
        }
        logout();
    });
    userDropdownLogout.addEventListener("touchend", (e) => {
        e.preventDefault();
        e.stopPropagation();
        closeUserMenu();
        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
            inactivityTimer = null;
        }
        logout();
    }, { passive: false });
}

/**
 * Abonniert die Chat-Unread-Anzahl und aktualisiert das Badge im User-Dropdown
 */
function subscribeToChatUnread(companyId, userId) {
  if (!companyId || !userId) return;
  if (chatUnreadUnsubscribe) {
    chatUnreadUnsubscribe();
    chatUnreadUnsubscribe = null;
  }
  try {
    const chatsRef = collection(db, "kunden", companyId, "chats");
    const q = query(chatsRef, where("participants", "array-contains", userId));
    chatUnreadUnsubscribe = onSnapshot(q, (snapshot) => {
      let total = 0;
      snapshot.forEach((docSnap) => {
        const d = docSnap.data();
        if ((d.deletedBy || []).includes(userId)) return;
        let n = (d.unreadCount || {})[userId];
        if (n != null && n > 0) {
          total += Number(n);
        } else {
          const lastFrom = d.lastMessageFrom;
          const lastAt = d.lastMessageAt?.toMillis?.() || 0;
          const lastRead = (d.lastReadAt || {})[userId];
          const lastReadMs = lastRead?.toMillis?.() || 0;
          if (lastFrom && lastFrom !== userId && lastAt > lastReadMs) total += 1;
        }
      });
      lastChatUnreadCount = total;
      const badgeText = total > 99 ? "99+" : String(total);
      if (total === 0) {
        if (chatUnreadBadge) chatUnreadBadge.style.display = "none";
        if (chatUnreadIndicator) chatUnreadIndicator.classList.remove("visible");
        dropdownMenu.querySelectorAll('[data-chat-badge]').forEach(el => {
          el.textContent = "0";
          el.classList.remove("visible");
        });
      } else {
        if (chatUnreadBadge) {
          chatUnreadBadge.textContent = badgeText;
          chatUnreadBadge.style.display = "flex";
        }
        if (chatUnreadIndicator && chatUnreadCount) {
          chatUnreadCount.textContent = badgeText;
          chatUnreadIndicator.classList.add("visible");
        }
        dropdownMenu.querySelectorAll('[data-chat-badge]').forEach(el => {
          el.textContent = badgeText;
          el.classList.add("visible");
        });
      }
      // An Home-iframe senden für Schnellstart-Badges (auch bei 0)
      if (contentFrame && contentFrame.contentWindow) {
        try {
          contentFrame.contentWindow.postMessage({ type: 'CHAT_UNREAD_UPDATE', count: total }, '*');
        } catch (_) {}
      }
    });
  } catch (e) {
    console.warn("Chat-Unread-Subscription:", e);
  }
}

/**
 * Lädt die vollständigen Mitarbeiter-Daten aus Firestore
 * ⚡ OPTIMIERT: Lädt alle Daten einmalig beim Login für schnelleres Laden
 */
async function loadMitarbeiterData(uid, companyId) {
  try {
    if (!uid || !companyId) {
      console.warn("loadMitarbeiterData: Keine UID oder companyId verfügbar");
      return null;
    }
    
    // Versuche 1: Direkte Abfrage mit UID als Dokument-ID
    const mitarbeiterRef = doc(db, "kunden", companyId, "mitarbeiter", uid);
    const mitarbeiterSnap = await getDoc(mitarbeiterRef);
    
    if (mitarbeiterSnap.exists()) {
      return {
        data: mitarbeiterSnap.data(),
        docId: uid
      };
    }
    
    // Versuche 2: Suche nach uid-Feld in der mitarbeiter Collection
    const mitarbeiterCollection = collection(db, "kunden", companyId, "mitarbeiter");
    const uidQuery = query(mitarbeiterCollection, where("uid", "==", uid));
    const uidSnapshot = await getDocs(uidQuery);
    
    if (!uidSnapshot.empty) {
      const mitarbeiterDoc = uidSnapshot.docs[0];
      return {
        data: mitarbeiterDoc.data(),
        docId: mitarbeiterDoc.id
      };
    }
    
    return null;
  } catch (error) {
    console.error("Fehler beim Laden der Mitarbeiter-Daten:", error);
    return null;
  }
}

/**
 * Ruft den Namen (Vor- und Nachname) eines Mitarbeiters aus Firestore ab
 * ⚡ OPTIMIERT: Verwendet bereits geladene Daten, wenn vorhanden
 */
async function getUserName(uid, companyId, mitarbeiterData = null) {
  try {
    if (!uid || !companyId) {
      console.warn("getUserName: Keine UID oder companyId verfügbar");
      return null;
    }
    
    let mitarbeiter = mitarbeiterData;
    
    // Wenn keine Daten übergeben wurden, lade sie
    if (!mitarbeiter) {
      const result = await loadMitarbeiterData(uid, companyId);
      mitarbeiter = result?.data;
    }
    
    if (mitarbeiter) {
      const vorname = mitarbeiter.vorname || '';
      const nachname = mitarbeiter.nachname || '';
      
      if (vorname || nachname) {
        // Formatiere als "Nachname, Vorname"
        if (vorname && nachname) {
          return `${nachname}, ${vorname}`;
        } else if (nachname) {
          return nachname;
        } else if (vorname) {
          return vorname;
        }
      }
    }
    
    // Fallback: Verwende Email (nur den Teil vor dem @)
    const userEmail = auth.currentUser?.email || "";
    const emailName = userEmail.split('@')[0];
    return emailName || "Benutzer";
  } catch (error) {
    console.error("Fehler beim Abrufen des Benutzernamens:", error);
    return null;
  }
}

/**
 * Aktualisiert die Anzeige des Benutzernamens im Header
 * ⚡ OPTIMIERT: Lädt Mitarbeiter-Daten einmalig und speichert sie in userAuthData
 */
async function updateUserNameDisplay() {
    if (!userAuthData || !userNameDisplay) return;
    
    try {
        // ⚡ OPTIMIERT: Lade Mitarbeiter-Daten einmalig beim Login
        if (!userAuthData.mitarbeiterData) {
            const result = await loadMitarbeiterData(userAuthData.uid, userAuthData.companyId);
            if (result) {
                userAuthData.mitarbeiterData = result.data;
                userAuthData.mitarbeiterDocId = result.docId;
                console.log("✅ Mitarbeiter-Daten im Dashboard geladen und gespeichert");
            }
        }
        
        // Verwende bereits geladene Daten
        const userName = await getUserName(userAuthData.uid, userAuthData.companyId, userAuthData.mitarbeiterData);
        if (userName) {
            userNameDisplay.textContent = userName;
        } else {
            // Fallback: Verwende Email
            const email = auth.currentUser?.email || "";
            const emailName = email.split('@')[0] || "Benutzer";
            userNameDisplay.textContent = emailName;
        }
    } catch (error) {
        console.error("Fehler beim Aktualisieren des Benutzernamens:", error);
        userNameDisplay.textContent = "Benutzer";
    }
}

/**
 * Lädt die globale Menüstruktur aus Firestore (gilt für alle Firmen)
 * ⚡ OPTIMIERT: Lädt aus settings/globalMenu
 */
async function loadMenuStructure() {
    try {
        // 🔥 GLOBAL: Lade Menüstruktur aus globalem Pfad (nicht firmenspezifisch)
        // Firestore: settings/globalMenu
        console.log("🔍 Lade globale Menüstruktur von: settings/globalMenu");
        console.log("🔍 Aktueller Benutzer:", userAuthData ? `UID: ${userAuthData.uid}, Role: ${userAuthData.role}, Company: ${userAuthData.companyId}` : "nicht eingeloggt");
        
        try {
            const menuRef = doc(db, "settings", "globalMenu");
            const menuSnap = await getDoc(menuRef);
            
            if (menuSnap.exists()) {
                const data = menuSnap.data();
                let items = data.items;
                
                // Parse items aus JSON-String (falls als String gespeichert)
                if (typeof items === 'string') {
                    try {
                        items = JSON.parse(items);
                    } catch (e) {
                        console.warn("⚠️ Konnte items nicht parsen:", e);
                        items = null;
                    }
                }
                
                console.log("📋 [LOAD] Firestore-Daten gefunden:", Object.keys(data));
                console.log("📋 [LOAD] data.items:", items);
                console.log("📋 [LOAD] data.items ist Array:", Array.isArray(items));
                console.log("📋 [LOAD] data.items.length:", Array.isArray(items) ? items.length : "N/A");
                
                // 🔥 WICHTIG: Leeres Array sollte nicht zu null werden!
                menuStructure = Array.isArray(items) ? items : (items || []);
                console.log("📋 [LOAD] Globale Menüstruktur geladen:", menuStructure.length, "Items");
                
                if (menuStructure.length > 0) {
                    console.log("📋 Menüstruktur-Items Details:");
                    menuStructure.forEach((item, index) => {
                        console.log(`   [${index}] ${item.label || item.id} - type: ${item.type}, level: ${item.level || 0}, order: ${item.order || 0}`);
                        if (item.roles) {
                            console.log(`       Rollen: ${item.roles.join(', ')}`);
                        }
                    });
                } else {
                    console.log("⚠️ Menüstruktur ist leer (0 Items) - möglicherweise wurde sie noch nicht erstellt");
                    console.log("💡 Tipp: Gehe zur Menü-Verwaltung (als Superadmin) und erstelle/speichere eine Menüstruktur");
                }
                return menuStructure;
            } else {
                console.log("📋 Keine globale Menüstruktur gefunden in Firestore (settings/globalMenu existiert nicht)");
                console.log("💡 Tipp: Gehe zur Menü-Verwaltung (als Superadmin) und erstelle/speichere eine Menüstruktur");
                menuStructure = []; // Leeres Array statt null
                return [];
            }
        } catch (error) {
            console.error("❌ Fehler beim Laden der globalen Menüstruktur:", error);
            console.error("   Fehler-Details:", error.message);
            console.error("   Fehler-Code:", error.code);
            console.error("   Stack:", error.stack);
            
            // Bei Fehler: Leeres Array statt null, damit Fallback funktioniert
            menuStructure = [];
            return [];
        }
    } catch (error) {
        console.error("❌ Fehler beim Laden der globalen Menüstruktur:", error);
        console.error("   Fehler-Details:", error.message);
        console.error("   Stack:", error.stack);
        
        // Bei Fehler: Leeres Array statt null, damit Fallback funktioniert
        menuStructure = [];
        return [];
    }
}

/**
 * Normalisiert einen Rollennamen für den Vergleich
 * Konvertiert "rettungsdienstleitung" zu "leiterssd" etc.
 */
function normalizeRoleName(role) {
    if (!role) return '';
    const normalized = role.toLowerCase().trim();
    // Normalisiere häufige Varianten
    if (normalized === 'rettungsdienstleitung') {
        return 'leiterssd';
    }
    return normalized;
}

/**
 * Prüft, ob eine Rolle in einem Array von Rollen vorhanden ist (case-insensitive mit Normalisierung)
 */
function hasRoleAccess(userRole, allowedRoles) {
    if (!userRole || !allowedRoles || !Array.isArray(allowedRoles)) {
        return false;
    }
    const normalizedUserRole = normalizeRoleName(userRole);
    return allowedRoles.some(role => normalizeRoleName(role) === normalizedUserRole);
}

/**
 * Findet Modul-Informationen für ein Menü-Item
 */
function findModuleInfo(item) {
    if (item.type === 'module') {
        const module = userModules.find(m => m.id === item.id);
        if (!module) {
            console.log(`   ⚠️ Modul '${item.id}' nicht in verfügbaren Modulen gefunden. Verfügbare Module:`, userModules.map(m => m.id));
        }
        return module;
    }
    return null;
}

/**
 * Klappt ein Untermenü ein oder aus
 */
function toggleSubmenu(menuItem, submenuContainer) {
    const isExpanded = submenuContainer.style.display !== 'none';
    const arrow = menuItem.querySelector('.menu-arrow');
    
    if (isExpanded) {
        // Einklappen
        submenuContainer.style.display = 'none';
        if (arrow) {
            arrow.style.transform = 'rotate(0deg)';
        }
        menuItem.classList.remove('expanded');
    } else {
        // Ausklappen
        submenuContainer.style.display = 'block';
        if (arrow) {
            arrow.style.transform = 'rotate(180deg)';
        }
        menuItem.classList.add('expanded');
    }
}

/**
 * Gruppiert Menü-Items nach ihrer Hierarchie (Parent-Child-Beziehungen)
 */
function groupMenuItems(items) {
    const grouped = [];
    let i = 0;
    
    while (i < items.length) {
        const item = items[i];
        const level = item.level || 0;
        
        if (level === 0) {
            // Top-Level Item - prüfe ob es Untermenüs hat
            const children = [];
            let j = i + 1;
            
            while (j < items.length && (items[j].level || 0) > 0) {
                children.push(items[j]);
                j++;
            }
            
            grouped.push({
                ...item,
                children: children,
                hasChildren: children.length > 0
            });
            
            i = j; // Überspringe die Kinder, da sie bereits hinzugefügt wurden
        } else {
            // Sollte nicht vorkommen, da alle Level > 0 Items bereits als Kinder hinzugefügt wurden
            i++;
        }
    }
    
    return grouped;
}

/**
 * Rendert die Menüpunkte basierend auf der gespeicherten Menüstruktur oder den verfügbaren Modulen
 */
/**
 * Sicherer Wrapper für renderMenu() - verhindert mehrfaches gleichzeitiges Rendern
 */
async function safeRenderMenu() {
    if (isRenderingMenu) {
        console.log("⚠️ renderMenu() wird bereits ausgeführt – überspringe erneuten Aufruf");
        return;
    }
    isRenderingMenu = true;
    try {
        await renderMenu();
    } finally {
        isRenderingMenu = false;
    }
}

async function renderMenu() {
    console.log("🎨 [RENDER] ====== renderMenu() START ======");
    console.log("🎨 [RENDER] Aktueller menuStructure-Wert:", menuStructure);
    console.log("🎨 [RENDER] userAuthData:", userAuthData ? `Role: ${userAuthData.role}, Company: ${userAuthData.companyId}` : "null");
    console.log("🎨 [RENDER] userModules:", userModules.length, "Module");
    
    // Entferne alle Menüpunkte außer Logout
    const existingItems = dropdownMenu.querySelectorAll('.menu-item[data-page], .menu-subitem[data-page], .menu-group');
    console.log(`🎨 [RENDER] Entferne ${existingItems.length} bestehende Menüpunkte`);
    existingItems.forEach(item => item.remove());
    
    // Lade globale Menüstruktur, falls noch nicht geladen (gilt für alle Firmen)
    // WICHTIG: Nur laden, wenn menuStructure noch null/undefined ist
    if (!menuStructure || menuStructure === null) {
        console.log("🔄 [RENDER] Lade globale Menüstruktur (noch nicht geladen)...");
        await loadMenuStructure(); // Keine companyId mehr nötig, da global
        console.log("🔄 [RENDER] Menüstruktur geladen:", Array.isArray(menuStructure) ? `${menuStructure.length} Items` : `Typ: ${typeof menuStructure}`);
    } else {
        console.log("🔄 [RENDER] Verwende bereits geladene Menüstruktur:", Array.isArray(menuStructure) ? `${menuStructure.length} Items` : `Typ: ${typeof menuStructure}`);
    }
    
    console.log("🎨 [RENDER] Menüstruktur nach Prüfung:", Array.isArray(menuStructure) ? `${menuStructure.length} Items` : `Typ: ${typeof menuStructure}`);
    console.log("🎨 [RENDER] Verfügbare Module:", userModules.length, "Module");
    console.log("🎨 [RENDER] Verfügbare Module IDs:", userModules.map(m => m.id).join(', '));
    
    // Wenn Menüstruktur vorhanden und nicht leer, verwende diese
    // 🔥 WICHTIG: Auch leere Menüstruktur sollte verarbeitet werden, damit Container angezeigt werden können
    if (Array.isArray(menuStructure) && menuStructure.length > 0) {
        console.log("✅ Verwende globale Menüstruktur mit", menuStructure.length, "Items");
        
        // 🔥 NEU: Füge fehlende Module automatisch zur Menüstruktur hinzu
        // Speziell: Menüverwaltung sollte unter "Admin" als Untermenü angezeigt werden
        const enhancedMenuStructure = [...menuStructure];
        
        // Prüfe ob Menüverwaltung bereits in der Struktur vorhanden ist
        const menueverwaltungExists = enhancedMenuStructure.some(item => 
            item.id === 'menueverwaltung'
        );
        
        // Prüfe ob Menüverwaltung-Modul verfügbar ist
        const menueverwaltungModule = userModules.find(m => m.id === 'menueverwaltung');
        
        // Wenn Menüverwaltung verfügbar ist, aber nicht in der Struktur existiert
        if (menueverwaltungModule && !menueverwaltungExists) {
            console.log("🔧 Menüverwaltung-Modul ist verfügbar, aber nicht in Menüstruktur - füge automatisch hinzu...");
            
            // Suche nach "Admin"-Container (kann verschiedene Namen/IDs haben)
            const adminContainer = enhancedMenuStructure.find(item => {
                const labelLower = (item.label || '').toLowerCase().trim();
                const idLower = (item.id || '').toLowerCase().trim();
                const isContainer = item.type === 'custom' && (!item.url || item.url === '#');
                return (labelLower === 'admin' || idLower === 'admin') && isContainer;
            });
            
            if (adminContainer) {
                // Füge Menüverwaltung als Untermenü unter Admin hinzu
                console.log("✅ Admin-Container gefunden - füge Menüverwaltung als Untermenü hinzu");
                const adminIndex = enhancedMenuStructure.findIndex(item => item === adminContainer);
                
                // Finde die letzte Position unter Admin (level > 0 nach Admin)
                let insertIndex = adminIndex + 1;
                while (insertIndex < enhancedMenuStructure.length && 
                       (enhancedMenuStructure[insertIndex].level || 0) > 0) {
                    insertIndex++;
                }
                
                // Füge Menüverwaltung als Untermenü hinzu
                enhancedMenuStructure.splice(insertIndex, 0, {
                    id: 'menueverwaltung',
                    label: menueverwaltungModule.label || 'Menü-Verwaltung',
                    type: 'module',
                    level: 1, // Untermenü-Level
                    order: (adminContainer.order || 0) + 0.1, // Kleine Zahl, damit es nach anderen Untermenüs kommt
                    roles: menueverwaltungModule.roles || ['superadmin']
                });
                console.log(`✅ Menüverwaltung als Untermenü unter Admin hinzugefügt (Index: ${insertIndex}, level: 1)`);
            } else {
                // Kein Admin-Container gefunden - suche nach "admin"-Modul als Container-Ersatz
                const adminModule = enhancedMenuStructure.find(item => 
                    item.id === 'admin' && item.type === 'module'
                );
                
                if (adminModule) {
                    // Füge Menüverwaltung als Untermenü nach admin-Modul hinzu
                    console.log("✅ Admin-Modul gefunden - füge Menüverwaltung als Untermenü hinzu");
                    const adminIndex = enhancedMenuStructure.findIndex(item => item === adminModule);
                    
                    // Finde die letzte Position unter Admin (level > 0 nach Admin)
                    let insertIndex = adminIndex + 1;
                    while (insertIndex < enhancedMenuStructure.length && 
                           (enhancedMenuStructure[insertIndex].level || 0) > 0) {
                        insertIndex++;
                    }
                    
                    // Füge Menüverwaltung als Untermenü hinzu
                    enhancedMenuStructure.splice(insertIndex, 0, {
                        id: 'menueverwaltung',
                        label: menueverwaltungModule.label || 'Menü-Verwaltung',
                        type: 'module',
                        level: 1, // Untermenü-Level
                        order: (adminModule.order || 0) + 0.1,
                        roles: menueverwaltungModule.roles || ['superadmin']
                    });
                    console.log(`✅ Menüverwaltung als Untermenü nach Admin-Modul hinzugefügt (Index: ${insertIndex}, level: 1)`);
                } else {
                    // Kein Admin-Container oder -Modul - füge als Top-Level hinzu
                    console.log("⚠️ Kein Admin-Container oder -Modul gefunden - füge Menüverwaltung als Top-Level hinzu");
                    enhancedMenuStructure.push({
                        id: 'menueverwaltung',
                        label: menueverwaltungModule.label || 'Menü-Verwaltung',
                        type: 'module',
                        level: 0,
                        order: menueverwaltungModule.order || 10,
                        roles: menueverwaltungModule.roles || ['superadmin']
                    });
                }
            }
        }
        
        // Sortiere nach order
        const sortedItems = [...enhancedMenuStructure].sort((a, b) => (a.order || 0) - (b.order || 0));
        
        // Gruppiere Items nach Hierarchie
        const groupedItems = groupMenuItems(sortedItems);
        console.log("📋 Gruppierte Items:", groupedItems.length, "Gruppen");
        console.log("📋 Gruppierte Items Details:", groupedItems.map(g => `${g.label || g.id} (${g.hasChildren ? g.children.length + ' Kinder' : 'keine Kinder'})`));
        
        let renderedItemsCount = 0;
        groupedItems.forEach(group => {
            const level = group.level || 0;
            
            // Prüfe ob benutzerdefiniertes Item ohne URL (Container) oder mit URL
            const isContainer = group.type === 'custom' && (!group.url || group.url === '#');
            const hasChildren = group.hasChildren || false;
            
            console.log(`🔍 Prüfe Menüpunkt: ${group.label || group.id} (type: ${group.type}, isContainer: ${isContainer}, hasChildren: ${hasChildren}, id: ${group.id})`);
            
            // 🔥 WICHTIG: Container-Items (custom ohne URL) müssen auch auf Modul-Verfügbarkeit geprüft werden
            if (isContainer) {
                // Container-Item - prüfe Rollen (mit Normalisierung)
                if (group.roles && Array.isArray(group.roles) && group.roles.length > 0) {
                    // Prüfe ob Benutzer eine der erlaubten Rollen hat (case-insensitive mit Normalisierung)
                    if (!userAuthData || !userAuthData.role || !hasRoleAccess(userAuthData.role, group.roles)) {
                        // Benutzer hat nicht die erforderliche Rolle - überspringe Container
                        console.log(`❌ Container '${group.label}' wird ausgeblendet - Benutzer hat nicht die erforderliche Rolle (User: ${userAuthData?.role || 'KEINE'}, Erlaubt: ${group.roles.join(', ')})`);
                        return;
                    } else {
                        console.log(`✅ Container '${group.label}' wird angezeigt - Benutzer hat passende Rolle (${userAuthData.role})`);
                    }
                }
                
                // 🔥 NEU: Prüfe nur für Container, die einem Modul entsprechen (z.B. "Office" → "office")
                // Andere Container wie "OVD" oder "Admin" haben kein direktes Modul
                const containerLabel = (group.label || group.id || '').toLowerCase().trim();
                
                // Mapping: Container-Label → Modul-ID
                // Liste der Container-Labels, die einem Modul entsprechen
                const containerToModuleMapping = {
                    'office': 'office'
                };
                
                const correspondingModuleId = containerToModuleMapping[containerLabel];
                if (correspondingModuleId) {
                    const correspondingModule = userModules.find(m => m.id === correspondingModuleId);
                    console.log(`🔍 [CONTAINER-MODULE-CHECK] Container '${group.label}' (Label: ${containerLabel}) → Modul-ID: ${correspondingModuleId}`);
                    console.log(`   Verfügbare Module: ${userModules.map(m => m.id).join(', ')}`);
                    console.log(`   Gefundenes Modul: ${correspondingModule ? correspondingModule.id : 'KEINES'}`);
                    
                    if (!correspondingModule) {
                        console.log(`❌ Container '${group.label}' wird ausgeblendet - zugehöriges Modul '${correspondingModuleId}' nicht verfügbar`);
                        return;
                    } else {
                        console.log(`✅ Container '${group.label}' wird angezeigt - zugehöriges Modul '${correspondingModuleId}' verfügbar`);
                    }
                } else {
                    // Container ohne direktes Modul (z.B. "OVD", "Admin") - nur Rollenprüfung
                    console.log(`✅ Container '${group.label}' wird angezeigt - kein Modul-Check erforderlich (Label: ${containerLabel})`);
                }
            } else {
                // NICHT-Container: Prüfe Module oder benutzerdefinierte Items mit URL
                if (group.type === 'module') {
                    // Prüfe ob Modul verfügbar ist
                    const module = findModuleInfo(group);
                    if (!module) {
                        // Modul nicht verfügbar für diesen Benutzer - überspringe
                        console.log(`❌ Modul '${group.label}' (${group.id}) wird ausgeblendet - nicht verfügbar für Benutzer`);
                        console.log(`   Verfügbare Module: ${userModules.map(m => m.id).join(', ')}`);
                        return;
                    } else {
                        console.log(`✅ Modul '${group.label}' (${group.id}) wird angezeigt - verfügbar`);
                    }
                } else if (group.type === 'custom') {
                    // Benutzerdefiniertes Item mit URL - prüfe Rollen (mit Normalisierung)
                    if (group.roles && Array.isArray(group.roles) && group.roles.length > 0) {
                        if (!userAuthData || !userAuthData.role || !hasRoleAccess(userAuthData.role, group.roles)) {
                            console.log(`❌ Custom-Item '${group.label}' wird ausgeblendet - Benutzer hat nicht die erforderliche Rolle (User: ${userAuthData?.role || 'KEINE'}, Erlaubt: ${group.roles.join(', ')})`);
                            return;
                        } else {
                            console.log(`✅ Custom-Item '${group.label}' wird angezeigt - Benutzer hat passende Rolle (${userAuthData.role})`);
                        }
                    } else {
                        console.log(`✅ Custom-Item '${group.label}' wird angezeigt - keine Rollenprüfung`);
                    }
                }
            }
            
            // Erstelle Menüpunkt-Container
            const menuItemContainer = document.createElement('div');
            menuItemContainer.className = 'menu-group';
            
            // Erstelle Haupt-Menüpunkt
            const menuItem = document.createElement('a');
            menuItem.href = hasChildren || isContainer ? '#' : '#';
            menuItem.className = 'menu-item';
            menuItem.dataset.page = group.id;
            menuItem.dataset.itemType = group.type || 'module';
            menuItem.dataset.hasChildren = hasChildren || isContainer ? 'true' : 'false';
            
            // Pfeil-Icon für Items mit Untermenüs
            const arrowIcon = hasChildren || isContainer ? `
                <svg class="menu-arrow" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                    <polyline points="6 9 12 15 18 9"></polyline>
                </svg>
            ` : '';
            
            const chatBadge = (group.id === 'chat') ? '<span class="menu-chat-badge" data-chat-badge></span>' : '';
            menuItem.innerHTML = `
                <span class="menu-item-text">${group.label || group.id}</span>
                ${chatBadge}
                ${arrowIcon}
            `;
            
            // Setze URL falls vorhanden (für benutzerdefinierte Items)
            if (group.url && group.type === 'custom' && !isContainer) {
                menuItem.dataset.url = group.url;
            }
            
            menuItemContainer.appendChild(menuItem);
            
            // Erstelle Untermenü-Container (wird ausgeblendet/angezeigt)
            if (hasChildren || isContainer) {
                const submenuContainer = document.createElement('div');
                submenuContainer.className = 'menu-submenu';
                submenuContainer.style.display = 'none'; // Standardmäßig ausgeblendet
                
                // Füge Untermenü-Items hinzu
                let visibleChildrenCount = 0;
                group.children.forEach(child => {
                    // Prüfe ob Kind ein Modul ist und ob der Benutzer Zugriff hat
                    if (child.type === 'module') {
                        const module = findModuleInfo(child);
                        if (!module) {
                            // Modul nicht verfügbar - überspringe
                            console.log(`   ❌ Untermenü-Item '${child.label}' wird ausgeblendet - Modul nicht verfügbar`);
                            return;
                        }
                    } else if (child.type === 'custom') {
                        // Prüfe Rollen für benutzerdefinierte Untermenü-Items (mit Normalisierung)
                        if (child.roles && Array.isArray(child.roles) && child.roles.length > 0) {
                            if (!userAuthData || !userAuthData.role || !hasRoleAccess(userAuthData.role, child.roles)) {
                                console.log(`   ❌ Untermenü-Item '${child.label}' wird ausgeblendet - Rolle nicht passend (User: ${userAuthData?.role || 'KEINE'}, Erlaubt: ${child.roles.join(', ')})`);
                                return;
                            } else {
                                console.log(`   ✅ Untermenü-Item '${child.label}' wird angezeigt - Rolle passend (${userAuthData.role})`);
                            }
                        }
                        
                        // 🔥 NEU: Prüfe ob custom Submenu-Item zu einem Modul gehört und ob das Modul verfügbar ist
                        // Beispiel: "email" gehört zu "office" - prüfe ob "office" verfügbar ist
                        if (child.id === 'email' && group.id === 'office') {
                            const officeModule = userModules.find(m => m.id === 'office');
                            if (!officeModule) {
                                console.log(`   ❌ Untermenü-Item '${child.label}' wird ausgeblendet - übergeordnetes Modul 'office' nicht verfügbar`);
                                return;
                            }
                        }
                    }
                    
                    const subItem = document.createElement('a');
                    subItem.href = '#';
                    subItem.className = 'menu-subitem';
                    subItem.dataset.page = child.id;
                    subItem.dataset.itemType = child.type || 'module';
                    const subChatBadge = (child.id === 'chat') ? '<span class="menu-chat-badge" data-chat-badge></span>' : '';
                    subItem.innerHTML = `<span>${child.label || child.id}</span>${subChatBadge}`;
                    
                    // Setze URL falls vorhanden
                    if (child.url && child.type === 'custom') {
                        subItem.dataset.url = child.url;
                    }
                    
                    submenuContainer.appendChild(subItem);
                    visibleChildrenCount++;
                });
                
                // Wenn Container keine sichtbaren Kinder hat, zeige trotzdem den Container an
                // (kann später gefüllt werden, wenn Module freigeschaltet werden)
                if (visibleChildrenCount === 0 && isContainer) {
                    console.log(`   ⚠️ Container '${group.label}' hat keine sichtbaren Kinder, wird aber trotzdem angezeigt`);
                }
                
                menuItemContainer.appendChild(submenuContainer);
                
                // Event Listener für Ein-/Ausklappen
                menuItem.addEventListener('click', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    toggleSubmenu(menuItem, submenuContainer);
                });
                
                menuItem.addEventListener('touchend', (e) => {
                    e.preventDefault();
                    e.stopPropagation();
                    toggleSubmenu(menuItem, submenuContainer);
                }, { passive: false });
            }
            
            dropdownMenu.insertBefore(menuItemContainer, logoutLink);
            renderedItemsCount++;
        });
        
        console.log(`✅ Menü gerendert: ${renderedItemsCount} von ${groupedItems.length} Items wurden angezeigt`);
        
        if (renderedItemsCount === 0 && groupedItems.length > 0) {
            console.error("❌ PROBLEM: Alle Menü-Items wurden herausgefiltert!");
            console.error("📊 Analyse:");
            console.error(`   - Menüstruktur hat ${groupedItems.length} Items`);
            console.error(`   - Verfügbare Module: ${userModules.length} (${userModules.map(m => m.id).join(', ')})`);
            console.error(`   - Benutzer-Rolle: ${userAuthData?.role || 'unbekannt'}`);
            console.error(`   - Firma: ${userAuthData?.companyId || 'unbekannt'}`);
            console.error("💡 Mögliche Ursachen:");
            console.error("   1. Module sind nicht für diese Firma freigeschaltet");
            console.error("   2. Rollenprüfung filtert alles heraus");
            console.error("   3. Benutzer hat keine passenden Module");
            console.error("💡 Lösung: Prüfe die Console-Ausgaben oben für jedes Item");
        } else if (renderedItemsCount > 0) {
            console.log(`✅ Erfolg: ${renderedItemsCount} Menü-Items werden angezeigt`);
        }
    } else if (Array.isArray(menuStructure) && menuStructure.length === 0) {
        // Menüstruktur ist leer - verwende Fallback
        console.log("⚠️ Menüstruktur ist ein leeres Array - verwende Fallback");
        // Fallback: Verwende die Standard-Module-Liste
        console.log("📋 Verfügbare Module für Fallback:", userModules.map(m => `${m.label} (${m.id})`));
        
        if (userModules.length === 0) {
            console.error("❌ Keine Module verfügbar - Menü bleibt leer!");
            return;
        }
        
        userModules.forEach(module => {
            const menuItem = document.createElement('a');
            menuItem.href = '#';
            menuItem.className = 'menu-item';
            menuItem.dataset.page = module.id;
            menuItem.dataset.itemType = 'module';
            menuItem.textContent = module.label;
            
            dropdownMenu.insertBefore(menuItem, logoutLink);
        });
        
        console.log(`✅ ${userModules.length} Module als Fallback-Menü gerendert`);
    } else {
        // Fallback: Verwende die Standard-Module-Liste
        console.log("⚠️ Keine globale Menüstruktur gefunden oder leer - verwende Standard-Module-Liste");
        console.log("📋 Verfügbare Module für Fallback:", userModules.map(m => `${m.label} (${m.id})`));
        
        if (userModules.length === 0) {
            console.error("❌ Keine Module verfügbar - Menü bleibt leer!");
            return;
        }
        
        userModules.forEach(module => {
            const menuItem = document.createElement('a');
            menuItem.href = '#';
            menuItem.className = 'menu-item';
            menuItem.dataset.page = module.id;
            menuItem.dataset.itemType = 'module';
            menuItem.textContent = module.label;
            
            dropdownMenu.insertBefore(menuItem, logoutLink);
        });
        
        console.log(`✅ ${userModules.length} Module als Fallback-Menü gerendert`);
    }
    
    // Event Listener für Navigation hinzufügen
    // Nur für Items OHNE Untermenüs und für Untermenü-Items selbst
    document.querySelectorAll(".menu-item[data-page]:not([data-has-children='true']), .menu-subitem[data-page]").forEach(item => {
        // Click Event (für Maus)
        item.addEventListener("click", (e) => {
            e.stopPropagation(); // Verhindere, dass der Klick als "außerhalb" erkannt wird
            e.preventDefault();
            const itemId = item.dataset.page;
            const itemType = item.dataset.itemType || 'module';
            
            let targetUrl = null;
            
            if (itemType === 'custom') {
                // Benutzerdefiniertes Item
                const customUrl = item.dataset.url;
                if (customUrl && customUrl !== '#') {
                    targetUrl = customUrl;
                } else {
                    // Container ohne URL - tue nichts
                    return;
                }
            } else {
                // Modul
                const module = userModules.find(m => m.id === itemId);
                if (module) {
                    targetUrl = module.url;
                } else {
                    console.error(`❌ Modul nicht gefunden: ${itemId}`);
                    return;
                }
            }
            
            if (targetUrl) {
                // Stelle sicher, dass die URL mit / beginnt (außer bei absoluten URLs)
                if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://') && !targetUrl.startsWith('/')) {
                    targetUrl = '/' + targetUrl;
                }
                console.log(`🔄 Lade: ${item.textContent} (${targetUrl})`);
                contentFrame.src = targetUrl;
                // Menü schließen nach Auswahl eines Menüpunkts
                closeMenu();
            }
        });
        
        // Touch Event (für Touch-Geräte)
        item.addEventListener("touchend", (e) => {
            e.stopPropagation(); // Verhindere, dass der Touch als "außerhalb" erkannt wird
            e.preventDefault();
            const itemId = item.dataset.page;
            const itemType = item.dataset.itemType || 'module';
            
            let targetUrl = null;
            
            if (itemType === 'custom') {
                // Benutzerdefiniertes Item
                const customUrl = item.dataset.url;
                if (customUrl && customUrl !== '#') {
                    targetUrl = customUrl;
                } else {
                    // Container ohne URL - tue nichts
                    return;
                }
            } else {
                // Modul
                const module = userModules.find(m => m.id === itemId);
                if (module) {
                    targetUrl = module.url;
                } else {
                    console.error(`❌ Modul nicht gefunden: ${itemId}`);
                    return;
                }
            }
            
            if (targetUrl) {
                // Stelle sicher, dass die URL mit / beginnt (außer bei absoluten URLs)
                if (!targetUrl.startsWith('http://') && !targetUrl.startsWith('https://') && !targetUrl.startsWith('/')) {
                    targetUrl = '/' + targetUrl;
                }
                console.log(`🔄 Lade: ${item.textContent} (${targetUrl})`);
                contentFrame.src = targetUrl;
                // Menü schließen nach Auswahl eines Menüpunkts
                closeMenu();
            }
        }, { passive: false });
    });
}

// Logout
logoutLink.addEventListener("click", (e) => {
    e.stopPropagation(); // Verhindere, dass der Klick als "außerhalb" erkannt wird
    e.preventDefault();
    // Schließe das Menü beim Logout
    closeMenu();
    // Stoppe den Inaktivitäts-Timer beim manuellen Logout
    if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
    }
    logout();
});

// Touch-Logik für Logout
logoutLink.addEventListener("touchend", (e) => {
    e.stopPropagation();
    e.preventDefault();
    // Schließe das Menü beim Logout
    closeMenu();
    // Stoppe den Inaktivitäts-Timer beim manuellen Logout
    if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
    }
    logout();
}, { passive: false });

/**
 * Initialisiert die Datenbankstruktur automatisch (nur für Superadmin)
 * ⚡ OPTIMIERT: Verwendet Firestore und modules.js Funktionen
 */
async function initializeDatabaseIfNeeded(companyId, userId) {
    try {
        // Prüfe, ob Module bereits existieren (aus modules.js)
        const modulesRef = doc(db, "modules", "home");
        const modulesSnap = await getDoc(modulesRef);
        
        if (!modulesSnap.exists()) {
            // Module existieren nicht - initialisiere
            console.log("🔧 Initialisiere Datenbankstruktur...");
            
            try {
                // 1. Standard-Module anlegen (aus modules.js)
                await initializeDefaultModules();
                
                // 2. Module für Firma freischalten (aus modules.js)
                await setCompanyModules(companyId, {
                    'home': true,
                    'admin': true,
                    'kundenverwaltung': true,
                    'modulverwaltung': true,
                    'menueverwaltung': true,
                    'einstellungen': true,
                    'schichtplan': true,
                    'chat': true
                });
                
                console.log("✅ Datenbankstruktur initialisiert");
            } catch (initError) {
                console.warn("⚠️ Initialisierung fehlgeschlagen (möglicherweise bereits vorhanden):", initError);
            }
        } else {
            console.log("ℹ️ Module existieren bereits - keine Initialisierung nötig");
        }
    } catch (error) {
        console.warn("⚠️ Automatische Initialisierung fehlgeschlagen:", error);
    }
}


// ✅ AUTH UND MULTI-TENANT-PRÜFUNG
onAuthStateChanged(auth, async (user) => {
    if (!user) {
        // 🔒 Stoppe Session-Timeouts-Timer wenn Benutzer ausgeloggt ist
        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
            inactivityTimer = null;
        }
        if (chatUnreadUnsubscribe) {
            chatUnreadUnsubscribe();
            chatUnreadUnsubscribe = null;
        }
        
        // 🔥 PRÜFE: Gibt es gespeicherte Superadmin-Daten für Wiederherstellung?
        const restoreEmail = localStorage.getItem('superadmin_restore_email');
        const restoreUid = localStorage.getItem('superadmin_restore_uid');
        
        if (restoreEmail && restoreUid) {
            console.log("⚠️ Kein eingeloggter Benutzer, aber Superadmin-Wiederherstellungsdaten gefunden.");
            console.log("   Bitte melden Sie sich erneut als Superadmin an.");
            // Lösche die Wiederherstellungsdaten, da sie nicht mehr benötigt werden
            localStorage.removeItem('superadmin_restore_email');
            localStorage.removeItem('superadmin_restore_uid');
        }
        
        window.location.href = "login.html";
        return;
    }

    try {
        // 🔥 PRÜFE: Ist dies eine Wiederherstellung nach Kunden-Anlage?
        const restoreEmail = localStorage.getItem('superadmin_restore_email');
        if (restoreEmail && user.email === restoreEmail) {
            console.log("✅ Superadmin-Session wiederhergestellt nach Kunden-Anlage");
            // Lösche die Wiederherstellungsdaten, da sie nicht mehr benötigt werden
            localStorage.removeItem('superadmin_restore_email');
            localStorage.removeItem('superadmin_restore_uid');
        }
        
        // 🔥 KORREKTUR: user.email MUSS an getAuthData übergeben werden
        const authData = await getAuthData(user.uid, user.email); 
        
        userAuthData = authData; 
        
        if (authData.role === "guest") {
          sessionStorage.setItem("rettbase_login_error", "Kein Zugang: Ihr Benutzer ist nicht registriert oder nicht korrekt angelegt. Bitte wenden Sie sich an den Administrator.");
          await logout();
          return;
        }
        const authErrorBanner = document.getElementById("authErrorBanner");
        const loginError = sessionStorage.getItem("rettbase_login_error");
        if (loginError) {
          if (authErrorBanner) {
            authErrorBanner.textContent = loginError;
            authErrorBanner.style.display = "block";
          }
          sessionStorage.removeItem("rettbase_login_error");
        }
        
        console.log(`✅ Nutzer ${user.email} angemeldet für Company ID: ${authData.companyId} mit Rolle: ${authData.role}`);

        // ⚡ OPTIMIERT: Lade Module, Menüstruktur und Mitarbeiter-Daten parallel
        console.log("🔄 [AUTH] Starte paralleles Laden von Module, Menüstruktur und Mitarbeiter-Daten...");
        
        // 🔥 WICHTIG: Automatische Initialisierung für Admin-Kunde
        // Stelle sicher, dass das Dokument kunden/admin existiert und initialisiert ist
        if (authData.companyId === 'admin') {
            try {
                const adminRef = doc(db, "kunden", "admin");
                const adminSnap = await getDoc(adminRef);
                
                if (!adminSnap.exists()) {
                    console.log("🔧 Dokument kunden/admin existiert nicht - erstelle es...");
                    await setDoc(adminRef, {
                        name: "RettBase Admin",
                        subdomain: "admin",
                        status: "active",
                        createdAt: serverTimestamp(),
                        isSystem: true
                    }, { merge: true });
                    console.log("✅ Dokument kunden/admin erstellt");
                }
            } catch (initError) {
                console.warn("⚠️ Konnte kunden/admin nicht initialisieren:", initError);
            }
            
            // Automatische Initialisierung für Superadmin (falls Datenbankstruktur fehlt) - nur wenn nötig
            if (authData.role === 'superadmin') {
                // Initialisierung im Hintergrund, blockiert nicht
                initializeDatabaseIfNeeded(authData.companyId, authData.uid).catch(err => {
                    console.warn("⚠️ Initialisierung fehlgeschlagen:", err);
                });
                
                // 🔥 WICHTIG: Stelle sicher, dass "menueverwaltung" auch nachträglich freigeschaltet wird
                // (falls es bereits initialisiert wurde, aber noch nicht freigeschaltet ist)
                setCompanyModules(authData.companyId, {
                    'menueverwaltung': true
                }).catch(err => {
                    console.warn("⚠️ Konnte menueverwaltung nicht freischalten:", err);
                });
            }
        }
        
        // ⚡ OPTIMIERT: Lade Module, Menüstruktur und Mitarbeiter-Daten parallel
        const [modulesResult, menuResult, mitarbeiterResult] = await Promise.allSettled([
            // 1. Lade Module
            (async () => {
                try {
                    const modules = await getUserModules(authData.companyId, authData.role);
                    console.log(`📋 Verfügbare Module für ${user.email}:`, modules.map(m => `${m.label} (${m.id})`));
                    return modules;
                } catch (moduleError) {
                    console.error("❌ [AUTH] Fehler beim Laden der Module:", moduleError);
                    return getDefaultModulesForRole(authData.role);
                }
            })(),
            // 2. Lade Menüstruktur
            (async () => {
                menuStructure = null; // Reset für Neuladen
                try {
                    const structure = await loadMenuStructure();
                    console.log("📋 [AUTH] Menüstruktur geladen:", Array.isArray(structure) ? `${structure.length} Items` : "leer");
                    return structure;
                } catch (menuError) {
                    console.error("❌ [AUTH] Fehler beim Laden der Menüstruktur:", menuError);
                    return [];
                }
            })(),
            // 3. Lade Mitarbeiter-Daten (für schnelleres Anzeigen des Namens)
            loadMitarbeiterData(authData.uid, authData.companyId)
        ]);
        
        // Verarbeite Module-Ergebnis
        if (modulesResult.status === 'fulfilled') {
            userModules = modulesResult.value || getDefaultModulesForRole(authData.role);
        } else {
            userModules = getDefaultModulesForRole(authData.role);
            console.warn("⚠️ Module-Laden fehlgeschlagen – nutze Default-Module");
        }
        
        // Fallback für Module
        if (!userModules || userModules.length === 0) {
            userModules = getDefaultModulesForRole(authData.role);
            console.warn("⚠️ Keine Module geladen – nutze Default-Module für Rolle:", authData.role);
        }
        
        // Verarbeite Mitarbeiter-Daten-Ergebnis
        if (mitarbeiterResult.status === 'fulfilled' && mitarbeiterResult.value) {
            userAuthData.mitarbeiterData = mitarbeiterResult.value.data;
            userAuthData.mitarbeiterDocId = mitarbeiterResult.value.docId;
            console.log("✅ Mitarbeiter-Daten parallel geladen und gespeichert");
        }
        
        console.log("🔄 [AUTH] ====== STARTE MENÜ-RENDERN ======");
        console.log("🔄 [AUTH] Firma:", authData.companyId, "Rolle:", authData.role);
        console.log("🔄 [AUTH] Verfügbare Module:", userModules.length, userModules.map(m => m.id).join(', '));
        console.log("📋 [AUTH] Menüstruktur:", Array.isArray(menuStructure) ? `${menuStructure.length} Items` : `Typ: ${typeof menuStructure}`);
        
        // Rendere Menü mit bereits geladenen Daten
        try {
            if (Array.isArray(menuStructure)) {
                if (menuStructure.length > 0) {
                    console.log("✅ [AUTH] Menüstruktur wurde erfolgreich geladen mit", menuStructure.length, "Items");
                } else {
                    console.warn("⚠️ [AUTH] Menüstruktur ist ein leeres Array (0 Items)");
                    console.warn("⚠️ [AUTH] Mögliche Ursachen:");
                    console.warn("   1. Menüstruktur wurde noch nicht in Firestore gespeichert");
                    console.warn("   2. Menüstruktur wurde gelöscht");
                    console.warn("   3. Firestore-Dokument existiert, aber items-Array ist leer");
                }
            } else {
                console.error("❌ [AUTH] Menüstruktur ist kein Array:", typeof menuStructure, menuStructure);
            }
            
            console.log("🎨 [AUTH] Rufe renderMenu() auf...");
            await safeRenderMenu();
            console.log("✅ [AUTH] renderMenu() abgeschlossen");
        } catch (error) {
            console.error("❌ [AUTH] Fehler beim Rendern des Menüs:", error);
            console.error("   Details:", error.message);
            console.error("   Stack:", error.stack);
            // Auch bei Fehler: Versuche Fallback-Menü zu rendern
            console.log("🔄 [AUTH] Versuche Fallback-Menü zu rendern...");
            try {
                await safeRenderMenu();
            } catch (fallbackError) {
                console.error("❌ [AUTH] Auch Fallback-Menü fehlgeschlagen:", fallbackError);
            }
        }
        
        // Setze Standard-Seite auf Home (falls verfügbar)
        console.log("🔄 [AUTH] Setze Standard-Seite auf Home...");
        const homeModule = userModules.find(m => m.id === 'home');
        if (homeModule) {
            console.log(`🔄 Lade Standard-Modul: ${homeModule.label} (${homeModule.url})`);
            contentFrame.src = homeModule.url;
        } else {
            console.warn("⚠️ Home-Modul nicht gefunden");
        }

        // ⚡ OPTIMIERT: Aktualisiere Benutzernamen sofort (Daten wurden bereits parallel geladen)
        updateUserNameDisplay().catch(err => {
            console.warn("⚠️ Fehler beim Aktualisieren des Benutzernamens:", err);
        });
        
        // Nach erfolgreichem Abruf der AuthData, sende die Daten an alle wartenden iFrames.
        console.log("🔄 [AUTH] Sende Auth-Daten an iFrame...");
        sendAuthDataToIframe();
        console.log("🔄 [AUTH] Auth-Daten gesendet");
        
        // 🔒 Starte Session-Timeouts-Überwachung
        startInactivityTimer();

        // Chat-Unread-Badge: Nur wenn Chat-Modul verfügbar
        if (userModules.some(m => m.id === "chat")) {
          subscribeToChatUnread(authData.companyId, authData.uid);
        }

    } catch (err) {
        console.error("❌ [AUTH] Fehler beim Abrufen der Auth-Daten im Dashboard:", err);
        console.error("   Details:", err.message);
        console.error("   Stack:", err.stack);
        // Fallback: Nur Home anzeigen
        userModules = getDefaultModulesForRole("user");
        console.log("🔄 [AUTH] Fallback: Verwende Default-Module für 'user'");
        await safeRenderMenu();
        
        // 🔥 NEU: Sende Menüpunkte an iframe nach dem Rendern
        sendAuthDataToIframe();
    }
});

// 🔒 SESSION-TIMEOUT-FUNKTIONEN

/**
 * Startet den Inaktivitäts-Timer
 * Wird bei jeder Benutzeraktivität zurückgesetzt
 */
function startInactivityTimer() {
    if (!userAuthData || !userAuthData.uid) {
        return; // Kein Timer, wenn kein Benutzer angemeldet ist
    }
    
    // Lösche vorhandene Timer
    if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
    }
    if (warningTimer) {
        clearTimeout(warningTimer);
        warningTimer = null;
    }
    
    // Warnung nach 25 Minuten (5 Minuten vor Timeout)
    const warningTime = INACTIVITY_TIMEOUT - (5 * 60 * 1000); // 25 Minuten
    
    // Setze Timer für Warnung
    warningTimer = setTimeout(() => {
        if (userAuthData && userAuthData.uid) {
            // Zeige Warnung nur wenn noch eingeloggt
            const warningBanner = document.createElement('div');
            warningBanner.id = 'session-warning';
            warningBanner.style.cssText = `
                position: fixed;
                top: 20px;
                left: 50%;
                transform: translateX(-50%);
                background: #ff9800;
                color: white;
                padding: 15px 20px;
                border-radius: 8px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                z-index: 10001;
                font-family: 'Segoe UI', sans-serif;
                font-size: 14px;
                max-width: 90%;
                text-align: center;
            `;
            warningBanner.textContent = '⚠️ Warnung: Ihre Session läuft in 5 Minuten ab. Bitte aktiv werden, um angemeldet zu bleiben.';
            document.body.appendChild(warningBanner);
            
            // Entferne Warnung nach 30 Sekunden
            setTimeout(() => {
                if (warningBanner.parentNode) {
                    warningBanner.remove();
                }
            }, 30000);
        }
    }, warningTime);
    
    // Setze neuen Timer für Timeout
    inactivityTimer = setTimeout(() => {
        console.warn("⏰ Session-Timeout: 30 Minuten Inaktivität erreicht. Abmelden...");
        handleSessionTimeout();
    }, INACTIVITY_TIMEOUT);
    
    console.log("🔒 Session-Timeouts-Überwachung gestartet (30 Minuten)");
}

/**
 * Setzt den Inaktivitäts-Timer zurück
 * Wird bei jeder Benutzeraktivität aufgerufen
 */
function resetInactivityTimer() {
    if (userAuthData && userAuthData.uid) {
        startInactivityTimer();
    }
}

/**
 * Behandelt das Session-Timeout
 * Meldet den Benutzer ab und zeigt eine Nachricht
 */
async function handleSessionTimeout() {
    // Stoppe alle Timer
    if (inactivityTimer) {
        clearTimeout(inactivityTimer);
        inactivityTimer = null;
    }
    if (warningTimer) {
        clearTimeout(warningTimer);
        warningTimer = null;
    }
    
    // Entferne Warnungs-Banner falls vorhanden
    const warningBanner = document.getElementById('session-warning');
    if (warningBanner) {
        warningBanner.remove();
    }
    
    // Zeige Warnung
    alert("⏰ Ihre Session ist abgelaufen (30 Minuten Inaktivität). Sie werden jetzt abgemeldet.");
    
    // Melde ab
    await logout();
}

/**
 * Initialisiert Event-Listener für Benutzeraktivität
 * Wird nur einmal aufgerufen, um mehrfache Registrierungen zu vermeiden
 */
function setupActivityListeners() {
    // Verhindere mehrfache Registrierung
    if (activityListenersSetup) {
        return;
    }
    activityListenersSetup = true;
    
    // Liste aller Events, die als Aktivität zählen
    const activityEvents = [
        'mousedown',
        'mousemove',
        'keypress',
        'scroll',
        'touchstart',
        'click',
        'keydown'
    ];
    
    // Füge Event-Listener für alle Aktivitäts-Events hinzu
    activityEvents.forEach(eventType => {
        document.addEventListener(eventType, resetInactivityTimer, { passive: true });
    });
    
    // Überwache auch iframe-Aktivitäten
    const contentFrame = document.getElementById("contentFrame");
    if (contentFrame && contentFrame.contentWindow) {
        try {
            // Versuche, auf iframe-Events zuzugreifen (nur wenn gleiche Domain)
            contentFrame.addEventListener('load', resetInactivityTimer);
        } catch (e) {
            // CORS-Beschränkung - kann nicht auf iframe-Events zugreifen
            console.log("⚠️ Kann iframe-Aktivitäten nicht überwachen (CORS)");
        }
    }
    
    // Überwache auch Navigation im iframe über postMessage
    // Hinweis: Dieser Listener wird bereits in Zeile 39 registriert, daher nicht doppelt
    // window.addEventListener('message', ...) ist bereits vorhanden
    
    console.log("👂 Aktivitäts-Überwachung initialisiert");
}

// Initialisiere Activity-Listener beim Laden (nur einmal)
if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', () => {
        setupActivityListeners();
        initializeServiceWorker();
    });
} else {
    // DOM ist bereits geladen
    setupActivityListeners();
    initializeServiceWorker();
}

// 🔥 Service Worker Registrierung (aus dashboard.html verschoben)
function initializeServiceWorker() {
    if ('serviceWorker' in navigator) {
        let refreshing = false;
        
        // 📱 TABLET/WEBAPP: Service Worker-Registrierung für zuverlässige Updates
        // 🔥 IPAD-SPEZIFISCH: Service Worker mit Cache-Busting für iPad Safari
        // iPad Safari cached den Service Worker aggressiver als iPhone
        const swUrl = '/service-worker.js';
        const swWithCacheBust = `${swUrl}?v=${Date.now()}&cb=${Math.random().toString(36).substring(7)}`;
        
        // Versuche zuerst mit Cache-Busting, dann ohne
        navigator.serviceWorker.register(swUrl, { 
            updateViaCache: 'none' // 📱 WICHTIG: Verhindert Caching des Service Workers selbst
        })
            .then((registration) => {
                console.log('✅ Service Worker registriert:', registration.scope);
                
                // Prüfe auf Updates beim Laden
                registration.addEventListener('updatefound', () => {
                    console.log('🔄 Neuer Service Worker gefunden!');
                    const newWorker = registration.installing;
                    
                    newWorker.addEventListener('statechange', () => {
                        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                            // Neuer Service Worker ist bereit, aber noch nicht aktiv
                            console.log('📦 Neuer Service Worker bereit. Zeige Update-Benachrichtigung...');
                            showUpdateNotification();
                        }
                    });
                });
                
                // 📱 TABLET/WEBAPP: Aggressivere Update-Prüfung für zuverlässige Updates
                // 🔥 IPAD-SPEZIFISCH: Häufigere Update-Prüfung (iPad Safari prüft seltener)
                // Prüfe regelmäßig auf Updates (alle 15 Sekunden - sehr häufig für iPad)
                setInterval(() => {
                    registration.update();
                }, 15000);
                
                // 📱 IPAD-SPEZIFISCH: Zusätzliche Update-Prüfung über Message Channel
                // iPad Safari erkennt Updates manchmal nicht über normale update()
                setInterval(() => {
                    if (registration.active) {
                        const messageChannel = new MessageChannel();
                        messageChannel.port1.onmessage = (event) => {
                            const swVersion = event.data?.version;
                            const cachedVersion = localStorage.getItem('sw_version');
                            
                            if (swVersion && cachedVersion && swVersion !== cachedVersion) {
                                console.log(`🔄 IPAD: Versionskonflikt erkannt: SW=${swVersion}, Cache=${cachedVersion} - Reload`);
                                localStorage.setItem('sw_version', swVersion);
                                if (!window.isReloading) {
                                    window.isReloading = true;
                                    window.location.reload();
                                }
                            }
                        };
                        
                        try {
                            registration.active.postMessage({ type: 'GET_VERSION' }, [messageChannel.port2]);
                        } catch (error) {
                            // Ignoriere Fehler
                        }
                    }
                }, 20000); // Alle 20 Sekunden Versionscheck
                
                // 📱 Zusätzlich: Prüfe auf Updates beim Fokus-Wechsel (wichtig für WebApp)
                document.addEventListener('visibilitychange', () => {
                    if (!document.hidden) {
                        console.log('📱 App sichtbar - prüfe auf Service Worker Updates...');
                        registration.update();
                        
                        // Zusätzlich: Versionscheck über Message Channel
                        if (registration.active) {
                            const messageChannel = new MessageChannel();
                            messageChannel.port1.onmessage = (event) => {
                                const swVersion = event.data?.version;
                                const cachedVersion = localStorage.getItem('sw_version');
                                
                                if (swVersion && cachedVersion && swVersion !== cachedVersion) {
                                    console.log(`🔄 Versionskonflikt beim Fokus: SW=${swVersion}, Cache=${cachedVersion} - Reload`);
                                    localStorage.setItem('sw_version', swVersion);
                                    if (!window.isReloading) {
                                        window.isReloading = true;
                                        window.location.reload();
                                    }
                                }
                            };
                            
                            try {
                                registration.active.postMessage({ type: 'GET_VERSION' }, [messageChannel.port2]);
                            } catch (error) {
                                console.warn('⚠️ Versionscheck beim Fokus fehlgeschlagen:', error);
                            }
                        }
                    }
                });
                
        // 📱 Zusätzlich: Prüfe auf Updates beim App-Wechsel zurück (WebApp)
        window.addEventListener('focus', () => {
            console.log('📱 App fokussiert - prüfe auf Service Worker Updates...');
            registration.update();
        });
        
        // 🔥 IPAD-SPEZIFISCH: bfcache-Handling für iPad Safari
        // iPad Safari nutzt bfcache aggressiver, was Updates verhindern kann
        window.addEventListener('pageshow', (event) => {
            if (event.persisted) {
                console.log('🔄 IPAD: Seite aus bfcache wiederhergestellt - prüfe auf Updates...');
                registration.update();
                
                // Zusätzlicher Versionscheck nach bfcache-Restore
                setTimeout(() => {
                    if (registration.active) {
                        const messageChannel = new MessageChannel();
                        messageChannel.port1.onmessage = (event) => {
                            const swVersion = event.data?.version;
                            const cachedVersion = localStorage.getItem('sw_version');
                            
                            if (swVersion && cachedVersion && swVersion !== cachedVersion) {
                                console.log(`🔄 IPAD: Versionskonflikt nach bfcache: SW=${swVersion}, Cache=${cachedVersion} - Reload`);
                                localStorage.setItem('sw_version', swVersion);
                                if (!window.isReloading) {
                                    window.isReloading = true;
                                    window.location.reload();
                                }
                            }
                        };
                        
                        try {
                            registration.active.postMessage({ type: 'GET_VERSION' }, [messageChannel.port2]);
                        } catch (error) {
                            console.warn('⚠️ Versionscheck nach bfcache fehlgeschlagen:', error);
                        }
                    }
                }, 1000);
            }
        });
            })
            .catch((error) => {
                console.error('❌ Service Worker Registrierung fehlgeschlagen:', error);
            });
        
        // Listener für Service Worker Updates
        // 🔥 IPAD-SPEZIFISCH: Mehrfache Listener für zuverlässige Update-Erkennung
        navigator.serviceWorker.addEventListener('controllerchange', () => {
            console.log('🔄 IPAD: controllerchange erkannt - Reload');
            if (!refreshing && !window.isReloading) {
                refreshing = true;
                window.isReloading = true;
                // Sofortiger Reload ohne Timeout für iPad
                window.location.reload();
            }
        });
        
        // 📱 IPAD-SPEZIFISCH: Zusätzlicher Listener für Service Worker State Changes
        navigator.serviceWorker.addEventListener('message', (event) => {
            if (!event.data) return;
            
            // Zusätzliche Logs für iPad-Debugging
            if (event.data.type === 'SW_ACTIVATED' || event.data.type === 'SW_SKIP_WAITING') {
                console.log('🔄 IPAD: SW_ACTIVATED/SW_SKIP_WAITING erkannt');
            }
        });
        
        // ✅ Erzwungener Reload nach SW-Aktivierung (KRITISCH für Tablet/PWA)
        // 📱 TABLET/WEBAPP: Ohne diesen Reload bleiben Tablets auf alter Version!
        navigator.serviceWorker.addEventListener('message', (event) => {
            if (!event.data) return;
            
            // SW_ACTIVATED oder SW_SKIP_WAITING → SOFORT Reload
            if (event.data.type === 'SW_ACTIVATED' || event.data.type === 'SW_SKIP_WAITING') {
                const version = event.data.version || 'unbekannt';
                console.log(`🔄 Service Worker Version ${version} aktiviert - Seite wird SOFORT neu geladen...`);
                
                // Verhindere doppelte Reloads
                if (!refreshing && !window.isReloading) {
                    refreshing = true;
                    window.isReloading = true;
                    
                    // Speichere Version in localStorage für Versionscheck
                    if (version !== 'unbekannt') {
                        localStorage.setItem('sw_version', version);
                    }
                    
                    // Sofortiger Reload (kritisch für Tablet/PWA)
                    setTimeout(() => {
                        window.location.reload();
                    }, 100);
                }
            }
        });
        
        // 📱 TABLET/WEBAPP: Versionscheck beim Start (wichtig für Apps, die tagelang offen bleiben)
        // 🔥 IPAD-SPEZIFISCH: Mehrfacher Versionscheck mit Fallback
        navigator.serviceWorker.ready.then((registration) => {
            if (registration.active) {
                // Frage aktuelle SW-Version ab
                const messageChannel = new MessageChannel();
                let versionReceived = false;
                
                // Timeout für iPad: Falls Message Channel nicht funktioniert
                const timeout = setTimeout(() => {
                    if (!versionReceived) {
                        console.warn('⚠️ IPAD: Versionscheck-Timeout - verwende Fallback');
                        // Fallback: Prüfe Service Worker-Datei direkt
                        fetch('/service-worker.js?v=' + Date.now())
                            .then(response => response.text())
                            .then(text => {
                                const versionMatch = text.match(/CACHE_VERSION\s*=\s*['"]([^'"]+)['"]/);
                                if (versionMatch) {
                                    const swVersion = versionMatch[1];
                                    const cachedVersion = localStorage.getItem('sw_version');
                                    
                                    if (cachedVersion && swVersion !== cachedVersion) {
                                        console.log(`🔄 IPAD: Versionskonflikt (Fallback): SW=${swVersion}, Cache=${cachedVersion} - Reload`);
                                        localStorage.setItem('sw_version', swVersion);
                                        if (!window.isReloading) {
                                            window.isReloading = true;
                                            window.location.reload();
                                        }
                                    } else if (swVersion) {
                                        localStorage.setItem('sw_version', swVersion);
                                    }
                                }
                            })
                            .catch(() => {
                                console.warn('⚠️ IPAD: Fallback-Versionscheck fehlgeschlagen');
                            });
                    }
                }, 2000);
                
                messageChannel.port1.onmessage = (event) => {
                    versionReceived = true;
                    clearTimeout(timeout);
                    
                    const swVersion = event.data?.version;
                    const cachedVersion = localStorage.getItem('sw_version');
                    
                    if (swVersion && cachedVersion && swVersion !== cachedVersion) {
                        console.log(`🔄 IPAD: Versionskonflikt erkannt: SW=${swVersion}, Cache=${cachedVersion} - Reload`);
                        localStorage.setItem('sw_version', swVersion);
                        if (!window.isReloading) {
                            window.isReloading = true;
                            window.location.reload();
                        }
                    } else if (swVersion) {
                        // Speichere aktuelle Version
                        localStorage.setItem('sw_version', swVersion);
                    }
                };
                
                try {
                    registration.active.postMessage({ type: 'GET_VERSION' }, [messageChannel.port2]);
                } catch (error) {
                    clearTimeout(timeout);
                    console.warn('⚠️ Versionscheck fehlgeschlagen:', error);
                }
            }
        });
        
        // Funktion zum Anzeigen der Update-Benachrichtigung
        function showUpdateNotification() {
            // Erstelle ein Update-Banner
            const banner = document.createElement('div');
            banner.id = 'update-banner';
            banner.className = 'update-banner';
            
            banner.innerHTML = `
                <span>🔄 Neue Version verfügbar!</span>
                <button id="update-btn" class="update-btn">Jetzt aktualisieren</button>
                <button id="dismiss-btn" class="dismiss-btn">Später</button>
            `;
            
            document.body.appendChild(banner);
            
            // Update-Button
            document.getElementById('update-btn').addEventListener('click', () => {
                if (navigator.serviceWorker.controller) {
                    navigator.serviceWorker.controller.postMessage({ type: 'SKIP_WAITING' });
                }
                banner.remove();
            });
            
            // Dismiss-Button
            document.getElementById('dismiss-btn').addEventListener('click', () => {
                banner.remove();
            });
            
            // Auto-Entfernen nach 10 Sekunden (optional)
            // setTimeout(() => banner.remove(), 10000);
        }
    } else {
        console.warn('⚠️ Service Worker wird nicht unterstützt');
    }
}