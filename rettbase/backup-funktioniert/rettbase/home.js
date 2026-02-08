// Importiere auth und db aus der auth.js des Parent-Verzeichnisses
// HINWEIS: Wir verwenden './auth.js', da home.html in derselben Ebene wie auth.js liegt.
import { auth, db, logout } from "./auth.js"; 
import { collection, query, where, getDocs, doc, getDoc, setDoc } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// 🔥 NEUE GLOBALE ZUSTÄNDE für Multi-Tenancy
let userAuthData = null; // Speichert { role, companyId, uid }
let hasLoaded = false;    // Hilfsvariable, um Firestore nur einmal zu laden
let emailCheckInterval = null; // Für E-Mail-Badge-Prüfung
let timeUpdateInterval = null; // Für Uhrzeit-Update
let greetingUpdateInterval = null; // Für Begrüßungs-Update (bei Tageszeitwechsel)
const EMAIL_CHECK_INTERVAL = 30000; // 30 Sekunden

window.addEventListener("DOMContentLoaded", () => {
  const grid = document.getElementById("homeGrid");
  const contextMenu = document.getElementById("contextMenu");
  const totalTiles = 16;
  let currentTileIndex = null;
  let tiles = Array(totalTiles).fill(null);

  // Menü-Optionen werden dynamisch aus den verfügbaren Modulen generiert
  let menuOptions = [];
  let availableModules = []; // Verfügbare Module vom Dashboard
  let visibleMenuItems = []; // Tatsächlich angezeigte Menüpunkte aus dem Hamburger-Menü

  // Icons für verschiedene Module (kann erweitert werden)
  const icons = {
      Home: `<path d="M3 9.5L12 3l9 6.5V21a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1V9.5z"/>`,
      "Schichtplan": `<rect x="9" y="2" width="6" height="4" rx="1" ry="1"></rect><path d="M9 2H5a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2h-4"></path>`,
      Admin: `<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>`,
      "Mitgliederverwaltung": `<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path>`,
      "Mitarbeiterverwaltung": `<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path>`,
      "Kundenverwaltung": `<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path><polyline points="9 22 9 12 15 12 15 22"></polyline><path d="M17 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2"></path><circle cx="10" cy="7" r="4"></circle><path d="M20 21v-2a4 4 0 0 0-3-3.87"></path><path d="M14 3.13a4 4 0 0 1 0 7.75"></path>`,
      "Modul-Verwaltung": `<rect x="3" y="3" width="7" height="7" rx="1"></rect><rect x="14" y="3" width="7" height="7" rx="1"></rect><rect x="3" y="14" width="7" height="7" rx="1"></rect><rect x="14" y="14" width="7" height="7" rx="1"></rect>`,
      "Menü-Verwaltung": `<line x1="3" y1="12" x2="21" y2="12"></line><line x1="3" y1="6" x2="21" y2="6"></line><line x1="3" y1="18" x2="21" y2="18"></line><circle cx="18" cy="6" r="1.5"></circle><circle cx="18" cy="12" r="1.5"></circle><circle cx="18" cy="18" r="1.5"></circle>`,
      "Einsatztagebuch - OVD": `<path d="M4 19.5A2.5 2.5 0 0 0 6.5 17H20"></path><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"></path><line x1="9" y1="7" x2="15" y2="7"></line><line x1="9" y1="11" x2="15" y2="11"></line><line x1="9" y1="15" x2="13" y2="15"></line><path d="M16 2l4 4-4 4"></path><line x1="20" y1="2" x2="20" y2="6"></line><line x1="18" y1="4" x2="20" y2="4"></line><line x1="19" y1="3" x2="19" y2="5"></line>`,
      Office: `<path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"></path>`,
      "E-Mail": `<rect x="2" y="4" width="20" height="16" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path>`,
      "Telefonliste": `<path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path>`,
      Logout: `<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path><polyline points="16 17 21 12 16 7"></polyline><line x1="21" y1="12" x2="9" y2="12"></line>`,
      Plus: `<circle cx="12" cy="12" r="9"></circle><line x1="12" y1="8" x2="12" y2="16"></line><line x1="8" y1="12" x2="16" y2="12"></line>`
  };
  
  // Funktion zum Abrufen des Icons für ein Label
  function getIconForLabel(label) {
    return icons[label] || icons.Plus; // Fallback zu Plus-Icon
  }
  
  // ✅ Hole die Authentifizierungsdaten vom Parent, bevor irgendetwas passiert
  waitForAuthData().then(async data => {
      userAuthData = data;
      console.log(`✅ Home.html hat Auth-Daten empfangen: Company ${data.companyId}`);
      
      // Lade Vorname und aktualisiere Begrüßung
      await updateGreeting();
      
      // Starte Uhrzeit- und Datum-Update (jede Sekunde)
      updateTime();
      timeUpdateInterval = setInterval(updateTime, 1000);
      
      // Starte Begrüßungs-Update (jede Minute, um Tageszeitwechsel zu erkennen)
      greetingUpdateInterval = setInterval(async () => {
        await updateGreeting();
      }, 60000); // Jede Minute prüfen
      
      // Führe die gesamte Initialisierungslogik erst jetzt aus!
      initializeHome();
      
      // 📧 Starte E-Mail-Badge-Prüfung
      startEmailChecking();
  }).catch(err => {
      console.error("Home.html konnte Auth-Daten nicht vom Parent empfangen:", err);
      // Optional: Weiterleitung zur Login-Seite, falls die Daten fehlen
      // window.location.href = "login.html"; 
  });

  // --- WARTEN AUF AUTH-DATEN VOM PARENT (HANDSHAKE) ---
  function waitForAuthData() {
    return new Promise((resolve) => {
      
      // 1. Sende "Ich bin bereit" Nachricht an das Parent-Fenster
      if (window.parent) {
         window.parent.postMessage({ type: 'IFRAME_READY' }, '*');
         console.log("➡️ Gesendet: IFRAME_READY");
      } else {
         console.error("Fehler: Kein Parent-Fenster gefunden.");
         resolve({ role: 'user', companyId: 'guest', uid: 'unknown' });
      }

      // 2. Erwarte die AUTH_DATA Nachricht vom Parent
      window.addEventListener('message', (event) => {
        if (event.data && event.data.type === 'AUTH_DATA') {
          console.log("⬅️ Empfangen: AUTH_DATA");
          // Speichere die verfügbaren Module
          if (event.data.modules) {
            availableModules = event.data.modules;
          }
          
          // 🔥 NEU: Speichere die tatsächlich angezeigten Menüpunkte aus dem Hamburger-Menü
          if (event.data.menuItems && Array.isArray(event.data.menuItems)) {
            visibleMenuItems = event.data.menuItems;
            console.log(`📋 Empfangen: ${visibleMenuItems.length} sichtbare Menüpunkte aus Hamburger-Menü`);
          }
          
          updateMenuOptions(); // Aktualisiere Menü-Optionen basierend auf Menüpunkten
          
          // 🔥 NEU: Wenn Kacheln bereits geladen wurden, filtere ungültige Kacheln
          if (hasLoaded && tiles && tiles.length > 0) {
            filterInvalidTiles();
            renderGrid(); // Rendere neu mit bereinigten Kacheln
          }
          
          resolve(event.data.data); // event.data.data enthält { role, companyId, uid }
        }
      });
    });
  }


  // 🔥 NEU: Generiere Menü-Optionen dynamisch aus den tatsächlich angezeigten Menüpunkten des Hamburger-Menüs
  function updateMenuOptions() {
    menuOptions = [];
    
    // 🔥 WICHTIG: Verwende die sichtbaren Menüpunkte aus dem Hamburger-Menü als Maßstab
    if (visibleMenuItems && visibleMenuItems.length > 0) {
      console.log("🔍 updateMenuOptions: Verwende sichtbare Menüpunkte aus Hamburger-Menü:", visibleMenuItems.length, "Items");
      
      // Konvertiere die Menüpunkte in Kachel-Optionen
      visibleMenuItems.forEach(menuItem => {
        menuOptions.push({
          label: menuItem.label,
          page: menuItem.url,
          id: menuItem.id
        });
        console.log(`  → Füge Menüpunkt hinzu: ${menuItem.label} (${menuItem.url})`);
      });
    } else {
      // Fallback: Verwende verfügbare Module (wenn Menüpunkte noch nicht geladen wurden)
      console.log("🔍 updateMenuOptions: Keine Menüpunkte verfügbar, verwende Fallback (verfügbare Module):", availableModules.length, "Module");
      
      availableModules.forEach(module => {
        console.log(`🔍 Prüfe Modul: ${module.label} (${module.id}), hat submenu:`, module.submenu ? `Ja (${Array.isArray(module.submenu) ? module.submenu.length : 'kein Array'})` : 'Nein');
        
        // Prüfe, ob Modul Submenüs hat
        if (module.submenu && Array.isArray(module.submenu) && module.submenu.length > 0) {
          // Modul mit Submenüs: Füge nur die Submenü-Punkte hinzu
          console.log(`  ✅ Modul '${module.label}' hat ${module.submenu.length} Submenü(s), füge nur diese hinzu`);
          module.submenu.forEach(subItem => {
            const subOption = {
              label: subItem.label,
              page: subItem.url || subItem.page,
              id: subItem.id || `${module.id}_${subItem.label.toLowerCase().replace(/\s+/g, '_')}`
            };
            console.log(`    → Füge Submenü hinzu: ${subOption.label} (${subOption.page})`);
            menuOptions.push(subOption);
          });
        } else {
          // Normales Modul ohne Submenüs
          console.log(`  → Füge Hauptmodul hinzu: ${module.label} (${module.url})`);
          menuOptions.push({
            label: module.label,
            page: module.url,
            id: module.id
          });
        }
      });
    }
    
    // Füge immer "Logout" und "Leeren" hinzu
    menuOptions.push(
      { label: "Logout", page: "logout", id: "logout" },
      { label: "Leeren", page: null, id: "clear" }
    );
    
    console.log(`📋 Menü-Optionen aktualisiert: ${menuOptions.length} Optionen verfügbar`);
    console.log("📋 Menü-Optionen Details:", menuOptions.map(opt => `${opt.label} (${opt.page || 'null'})`));
  }

  // --- NEUE HAUPTINITIALISIERUNG NACH ERFOLGREICHEM HANDSHAKE ---
  async function initializeHome() {
    if (hasLoaded) return;
    hasLoaded = true;

    // 🔥 WICHTIG: Lade zuerst von Firestore (wenn verfügbar), dann von localStorage
    // Dies stellt sicher, dass die neuesten Kacheln sofort angezeigt werden
    try {
      await mergeFromFirestore();
      // Nach dem Laden von Firestore: Prüfe und entferne ungültige Kacheln
      if (visibleMenuItems && visibleMenuItems.length > 0) {
        filterInvalidTiles();
      }
      renderGrid();
    } catch (e) {
      console.warn("⚠️ Firestore-Laden fehlgeschlagen, verwende localStorage:", e);
      
      // Fallback: Lade aus localStorage
      const cachedTiles = localStorage.getItem(`userTiles_${userAuthData.uid}`);
      if (cachedTiles) {
        try {
          const parsedTiles = JSON.parse(cachedTiles);
          // Stelle sicher, dass Array die richtige Länge hat
          if (Array.isArray(parsedTiles) && parsedTiles.length === totalTiles) {
            tiles = parsedTiles;
          } else {
            // Array-Länge anpassen
            tiles = Array(totalTiles).fill(null);
            if (parsedTiles.length > 0) {
              for (let i = 0; i < Math.min(parsedTiles.length, totalTiles); i++) {
                tiles[i] = parsedTiles[i] || null;
              }
            }
          }
          // Prüfe und entferne ungültige Kacheln (Module die nicht mehr verfügbar sind)
          if (visibleMenuItems && visibleMenuItems.length > 0) {
            filterInvalidTiles();
          }
          // Sofort rendern für schnelle Anzeige
          renderGrid();
        } catch (parseError) {
          console.warn("Fehler beim Laden aus localStorage:", parseError);
          tiles = Array(totalTiles).fill(null);
          renderGrid();
        }
      } else {
        // Keine gecachten Daten: Starte mit leeren Kacheln
        tiles = Array(totalTiles).fill(null);
        renderGrid();
      }
    }
  }

  /**
   * Normalisiert eine URL für den Vergleich (entfernt führende/trailing Slashes, normalisiert)
   */
  function normalizeUrl(url) {
    if (!url) return '';
    // Entferne führende und trailing Slashes (außer bei absoluten URLs)
    let normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      // Entferne führende Slashes
      normalized = normalized.replace(/^\/+/, '');
      // Entferne auch trailing Slashes
      normalized = normalized.replace(/\/+$/, '');
    }
    return normalized;
  }

  // 🔥 NEU: Filtert ungültige Kacheln (basierend auf den tatsächlich angezeigten Menüpunkten)
  function filterInvalidTiles() {
    // 🔥 WICHTIG: Verwende die sichtbaren Menüpunkte als Maßstab
    let availableUrls = new Set();
    let removedCount = 0; // 🔥 FIX: Variable initialisieren
    
    if (visibleMenuItems && visibleMenuItems.length > 0) {
      // Verwende die URLs aus den sichtbaren Menüpunkten
      visibleMenuItems.forEach(item => {
        // dashboard.js sendet 'url', aber für Kompatibilität auch 'page' unterstützen
        const url = item.url || item.page;
        if (url) {
          // Normalisiere URL für Vergleich
          const normalizedUrl = normalizeUrl(url);
          availableUrls.add(normalizedUrl);
          // Füge auch die Original-URL hinzu (für Kompatibilität)
          availableUrls.add(url);
        }
      });
      console.log(`🔍 Filtere Kacheln basierend auf ${visibleMenuItems.length} sichtbaren Menüpunkten`);
      console.log(`   Verfügbare URLs:`, Array.from(availableUrls));
    } else if (availableModules && availableModules.length > 0) {
      // Fallback: Verwende verfügbare Module
      availableModules.forEach(m => {
        if (m.url) {
          const normalizedUrl = normalizeUrl(m.url);
          availableUrls.add(normalizedUrl);
          availableUrls.add(m.url);
        }
      });
      availableModules.forEach(module => {
        if (module.submenu && Array.isArray(module.submenu)) {
          module.submenu.forEach(sub => {
            if (sub.url || sub.page) {
              const url = sub.url || sub.page;
              const normalizedUrl = normalizeUrl(url);
              availableUrls.add(normalizedUrl);
              availableUrls.add(url);
            }
          });
        }
      });
      console.log(`🔍 Filtere Kacheln basierend auf ${availableModules.length} verfügbaren Modulen (Fallback)`);
    } else {
      console.warn("⚠️ Keine Menüpunkte oder Module verfügbar - kann Kacheln nicht validieren");
      return;
    }
    
    tiles = tiles.map((tile, index) => {
      if (!tile || !tile.page) {
        return tile; // Leere Kacheln bleiben
      }

      // Normalisiere Kachel-URL für Vergleich
      const normalizedTileUrl = normalizeUrl(tile.page);
      
      // Prüfe ob die Seite noch verfügbar ist (mit normalisierter und originaler URL)
      // Prüfe auch mit/ohne führendem Slash (für Kompatibilität)
      const tileWithSlash = tile.page.startsWith('/') ? tile.page : '/' + tile.page;
      const tileWithoutSlash = tile.page.startsWith('/') ? tile.page.substring(1) : tile.page;
      
      const isAvailable = availableUrls.has(tile.page) || 
                          availableUrls.has(normalizedTileUrl) ||
                          availableUrls.has(tileWithSlash) ||
                          availableUrls.has(tileWithoutSlash);
      
      if (!isAvailable) {
        console.log(`🗑️ Entferne ungültige Kachel [${index}]: ${tile.label} (${tile.page}) - nicht mehr verfügbar für Rolle ${userAuthData.role}`);
        console.log(`   Verfügbare URLs:`, Array.from(availableUrls));
        console.log(`   Kachel-URL (normalisiert): ${normalizedTileUrl}, mit Slash: ${tileWithSlash}, ohne Slash: ${tileWithoutSlash}`);
        removedCount++;
        return null; // Entferne ungültige Kachel
      }

      return tile; // Gültige Kachel behalten
    });

    if (removedCount > 0) {
      console.log(`✅ ${removedCount} ungültige Kachel(n) entfernt`);
      // Speichere bereinigte Kacheln
      localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(tiles));
      // Speichere auch in Firestore (im Hintergrund)
      saveToFirestore().catch(e => {
        console.warn("⚠️ Konnte bereinigte Kacheln nicht in Firestore speichern:", e);
      });
    }
  }

  // --- WEITERE FUNKTIONEN (ANGEPASST FÜR MULTI-TENANCY) ---
  
  function renderGrid() {
    grid.innerHTML = "";
    for (let i = 0; i < totalTiles; i++) {
      const tile = tiles[i];
      
      // Container für Kachel und Beschriftung
      const container = document.createElement("div");
      container.classList.add("grid-item-container");
      
      const div = document.createElement("div");
      div.classList.add("grid-item");
      if (!tile) div.classList.add("placeholder");
      div.dataset.index = i;
      div.dataset.tilePage = tile?.page || ""; // Speichere die Seite für Badge-Prüfung

      // Nur Icon in der Kachel (mittig)
      div.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-linecap="round" stroke-linejoin="round">
          ${getIconForLabel(tile?.label || "Plus")}
        </svg>
      `;

      // Beschriftung außerhalb der Kachel
      const labelDiv = document.createElement("div");
      labelDiv.classList.add("grid-item-label");
      labelDiv.textContent = tile?.label || "+";

      container.appendChild(div);
      container.appendChild(labelDiv);

      div.addEventListener("click", () => {
        if (tile && tile.page) navigate(tile.page);
      });

      // Kontextmenü-Logik: ALLE Benutzer können ihre Kacheln belegen!
      // Nicht nur Admin/Superadmin, sondern auch normale Benutzer (user, supervisor)
      if (userAuthData && userAuthData.uid) {
          div.addEventListener("contextmenu", (e) => {
            e.preventDefault();
            e.stopPropagation(); // verhindert sofortiges Schließen durch den globalen Click-Listener
            currentTileIndex = i;
            showContextMenu(e.pageX, e.pageY, true); // Immer true, da alle Benutzer konfigurieren können
          });

          let pressTimer;
          let longPressFired = false;
          let startX = 0, startY = 0;

          div.addEventListener("touchstart", (e) => {
            longPressFired = false;
            const t = e.touches[0];
            startX = t.clientX;
            startY = t.clientY;

            pressTimer = setTimeout(() => {
              longPressFired = true;
              currentTileIndex = i;
              showContextMenu(t.pageX, t.pageY, true); // Immer true, da alle Benutzer konfigurieren können
            }, 600);
          }, { passive: true });

          div.addEventListener("touchmove", (e) => {
            const t = e.touches[0];
            if (Math.abs(t.clientX - startX) > 10 || Math.abs(t.clientY - startY) > 10)
              clearTimeout(pressTimer);
          }, { passive: true });

          div.addEventListener("touchend", (e) => {
            clearTimeout(pressTimer);
            if (!longPressFired) {
              e.preventDefault();
              if (tile && tile.page) navigate(tile.page);
            }
          });
      }

      grid.appendChild(container);
    }
    
    // 📧 Aktualisiere E-Mail-Badges nach dem Rendern
    if (userAuthData && userAuthData.uid) {
      updateEmailBadgesOnTiles();
    }
  }

  function showContextMenu(x, y) {
    contextMenu.innerHTML = "";
    
    // Zeige alle verfügbaren Optionen (Submenü-Punkte sind bereits direkt enthalten)
    menuOptions.forEach(opt => {
      const btn = document.createElement("button");
      btn.textContent = opt.label;
      btn.addEventListener("click", () => setTile(opt));
      contextMenu.appendChild(btn);
    });
    
    contextMenu.style.left = `${x}px`;
    contextMenu.style.top = `${y}px`;
    contextMenu.style.display = "flex";
  }

  document.addEventListener("click", (e) => {
    if (!contextMenu.contains(e.target)) contextMenu.style.display = "none";
  });
  document.addEventListener("contextmenu", (e) => {
    // Kontextmenü nur schließen, wenn außerhalb geklickt wird
    if (!contextMenu.contains(e.target)) contextMenu.style.display = "none";
  });

  async function setTile(option) {
    // Jeder Benutzer kann seine eigenen Kacheln belegen
    if (option.page === null) tiles[currentTileIndex] = null;
    else tiles[currentTileIndex] = option;

    localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(tiles));
    await saveToFirestore();
    renderGrid();
    contextMenu.style.display = "none";
  }

  function navigate(page) {
    if (!page) return;
    if (page === "logout") {
      // Ruft die Logout-Funktion des Parent-Verzeichnisses auf
      import("./auth.js").then(mod => mod.logout());
      return;
    }
    
    // 🔥 NEU: Prüfe ob die Seite noch für die aktuelle Rolle verfügbar ist
    // Verwende die gleiche Logik wie filterInvalidTiles() - basierend auf visibleMenuItems
    let isAvailable = false;
    const normalizedPageUrl = normalizeUrl(page);
    
    if (visibleMenuItems && visibleMenuItems.length > 0) {
      // Prüfe gegen visibleMenuItems (wie in filterInvalidTiles)
      visibleMenuItems.forEach(item => {
        const url = item.url || item.page;
        if (url) {
          const normalizedItemUrl = normalizeUrl(url);
          if (url === page || normalizedItemUrl === normalizedPageUrl || 
              url === normalizedPageUrl || normalizedItemUrl === page) {
            isAvailable = true;
          }
        }
      });
    } else if (availableModules && availableModules.length > 0) {
      // Fallback: Prüfe gegen availableModules
      availableModules.forEach(m => {
        if (m.url) {
          const normalizedModuleUrl = normalizeUrl(m.url);
          if (m.url === page || normalizedModuleUrl === normalizedPageUrl ||
              m.url === normalizedPageUrl || normalizedModuleUrl === page) {
            isAvailable = true;
          }
        }
      });
      availableModules.forEach(module => {
        if (module.submenu && Array.isArray(module.submenu)) {
          module.submenu.forEach(sub => {
            const subUrl = sub.url || sub.page;
            if (subUrl) {
              const normalizedSubUrl = normalizeUrl(subUrl);
              if (subUrl === page || normalizedSubUrl === normalizedPageUrl ||
                  subUrl === normalizedPageUrl || normalizedSubUrl === page) {
                isAvailable = true;
              }
            }
          });
        }
      });
    }
    
    if (!isAvailable) {
      console.warn(`⚠️ Zugriff verweigert: Seite '${page}' ist nicht mehr für Rolle '${userAuthData.role}' verfügbar`);
      alert(`Diese Seite ist nicht mehr für Ihre Rolle verfügbar. Die Kachel wurde entfernt.`);
      // Entferne die Kachel, die zu dieser Seite führt
      const tileIndex = tiles.findIndex(t => t && t.page === page);
      if (tileIndex !== -1) {
        tiles[tileIndex] = null;
        localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(tiles));
        saveToFirestore();
        renderGrid();
      }
      return;
    }
    
    // Navigiere im Parent-iFrame
    const frame = window.parent?.document.getElementById("contentFrame");
    if (frame) frame.src = page;
    else window.location.href = page;
  }

  // 🔥 ANGEPASST: Speicherpfad verwendet die CompanyId und ist benutzerspezifisch
  async function mergeFromFirestore() {
    if (!userAuthData || !userAuthData.companyId || !userAuthData.uid) {
      console.warn("⚠️ Keine Auth-Daten verfügbar für mergeFromFirestore");
      return;
    }

    try {
      // Pfad: /kunden/{companyId}/users/{uid}/userTiles/config
      // JEDER Benutzer hat seine eigenen Kacheln!
      const ref = doc(db, "kunden", userAuthData.companyId, "users", userAuthData.uid, "userTiles", "config");
      const snap = await getDoc(ref);

      // Falls noch nichts existiert: Leere Kacheln (neuer Benutzer)
      // Jeder Benutzer startet mit leeren Kacheln und kann sie selbst belegen
      if (!snap.exists()) {
        console.log(`📝 Keine Kacheln gefunden für Benutzer ${userAuthData.uid}. Starte mit leeren Kacheln.`);
        // Speichere leere Kacheln in Firestore (damit sie geräteübergreifend synchronisiert werden)
        const emptyTiles = Array(totalTiles).fill(null);
        await setDoc(ref, { tiles: emptyTiles }, { merge: true });
        localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(emptyTiles));
        // Nur neu rendern, wenn aktuell leere Kacheln angezeigt werden
        if (tiles.every(t => t === null)) {
          return; // Bereits korrekt angezeigt
        }
        tiles = emptyTiles;
        renderGrid();
        return;
      }

      const remote = snap.data().tiles;
      if (!remote || !Array.isArray(remote)) {
        // Keine Remote-Daten: Verwende leere 16-Kacheln-Array
        const emptyTiles = Array(totalTiles).fill(null);
        await setDoc(ref, { tiles: emptyTiles }, { merge: true });
        localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(emptyTiles));
        if (tiles.every(t => t === null)) {
          return; // Bereits korrekt angezeigt
        }
        tiles = emptyTiles;
        renderGrid();
        return;
      }
      
      // Normiere remote Array auf totalTiles
      let normalizedRemote = [...remote];
      if (normalizedRemote.length < totalTiles) {
        normalizedRemote = [...normalizedRemote, ...Array(totalTiles - normalizedRemote.length).fill(null)];
      } else if (normalizedRemote.length > totalTiles) {
        normalizedRemote = normalizedRemote.slice(0, totalTiles);
      }
      
      // Prüfe, ob sich die Daten geändert haben
      const tilesChanged = JSON.stringify(tiles) !== JSON.stringify(normalizedRemote);
      
      if (tilesChanged) {
        // Aktualisiere tiles mit Remote-Daten
        tiles = normalizedRemote;
        // 🔥 NEU: Filtere ungültige Kacheln (Module die nicht mehr verfügbar sind)
        filterInvalidTiles();
        // Aktualisiere localStorage
        localStorage.setItem(`userTiles_${userAuthData.uid}`, JSON.stringify(tiles));
        // Rendere nur neu, wenn sich die Daten tatsächlich geändert haben
        renderGrid();
      } else {
        // Auch wenn keine Änderung: Prüfe auf ungültige Kacheln (falls sich Rollen geändert haben)
        filterInvalidTiles();
        renderGrid();
      }
      
      // Stelle sicher, dass Firestore die aktuelle Version hat (im Hintergrund)
      // Nur wenn Remote-Daten fehlen oder veraltet sind
      if (tilesChanged && tiles.some(t => t !== null)) {
        await setDoc(ref, { tiles: tiles }, { merge: true });
      }
    } catch (e) {
      console.warn("⚠️ Firestore Ladefehler (Home):", e);
    }
  }

  // 🔥 ANGEPASST: Speicherpfad verwendet die CompanyId
  async function saveToFirestore() {
    if (!userAuthData || !userAuthData.companyId) return;

    try {
      // Pfad auf Kunden-Struktur angleichen: /kunden/{companyId}/users/{uid}/userTiles/config
      const ref = doc(db, "kunden", userAuthData.companyId, "users", userAuthData.uid, "userTiles", "config");
      await setDoc(ref, { tiles: tiles }, { merge: true });
    } catch (e) {
      console.warn("⚠️ Firestore Speicherfehler (Home):", e);
    }
  }

  // 📧 E-MAIL-BADGE-FUNKTIONEN

  /**
   * Zählt ungelesene E-Mails für den aktuellen Benutzer
   */
  async function checkUnreadEmails() {
    if (!userAuthData || !userAuthData.uid || !userAuthData.companyId) {
      return 0;
    }
    
    try {
      const emailsRef = collection(db, "kunden", userAuthData.companyId, "emails");
      const q = query(
        emailsRef,
        where("to", "==", userAuthData.uid)
      );
      
      const snapshot = await getDocs(q);
      
      // Zähle ungelesene E-Mails (read !== true und nicht gelöscht und keine Entwürfe)
      let unreadCount = 0;
      snapshot.forEach(doc => {
        const data = doc.data();
        if (data.deleted !== true && data.draft !== true && data.read !== true) {
          unreadCount++;
        }
      });
      
      return unreadCount;
    } catch (error) {
      console.error("Fehler beim Prüfen ungelesener E-Mails:", error);
      return 0;
    }
  }

  /**
   * Aktualisiert den Badge auf E-Mail-Kacheln
   */
  async function updateEmailBadgesOnTiles() {
    if (!userAuthData || !userAuthData.uid) return;
    
    const unreadCount = await checkUnreadEmails();
    
    // Finde alle Kacheln, die auf die E-Mail-Seite zeigen
    const emailTiles = grid.querySelectorAll('.grid-item[data-tile-page*="email.html"]');
    
    emailTiles.forEach(tileDiv => {
      // Entferne vorhandenen Badge
      const existingBadge = tileDiv.querySelector('.email-badge');
      if (existingBadge) {
        existingBadge.remove();
      }
      
      // Füge Badge hinzu, wenn ungelesene E-Mails vorhanden sind
      if (unreadCount > 0) {
        const badge = document.createElement('span');
        badge.className = 'email-badge';
        badge.textContent = unreadCount > 99 ? '99+' : unreadCount.toString();
        tileDiv.appendChild(badge);
      }
    });
  }

  /**
   * Startet die regelmäßige Prüfung auf neue E-Mails
   */
  function startEmailChecking() {
    if (emailCheckInterval) {
      clearInterval(emailCheckInterval);
    }
    
    // Prüfe sofort beim Start
    updateEmailBadgesOnTiles();
    
    // Prüfe dann regelmäßig
    emailCheckInterval = setInterval(() => {
      updateEmailBadgesOnTiles();
    }, EMAIL_CHECK_INTERVAL);
  }

  /**
   * Stoppt die regelmäßige Prüfung auf neue E-Mails
   */
  function stopEmailChecking() {
    if (emailCheckInterval) {
      clearInterval(emailCheckInterval);
      emailCheckInterval = null;
    }
  }

  // 🕐 BEGRÜSSUNG UND UHRZEIT-FUNKTIONEN

  /**
   * Ermittelt die Tageszeit-basierte Begrüßung
   */
  function getGreeting() {
    const now = new Date();
    const hour = now.getHours();
    const minutes = now.getMinutes();
    const totalMinutes = hour * 60 + minutes;
    
    // 11:30 - 12:30 Uhr: Mahlzeit
    if (totalMinutes >= 11 * 60 + 30 && totalMinutes < 12 * 60 + 30) {
      return "Mahlzeit";
    } else if (hour >= 5 && hour < 12) {
      return "Guten Morgen";
    } else if (hour >= 12 && hour < 18) {
      return "Guten Nachmittag";
    } else {
      return "Guten Abend";
    }
  }

  /**
   * Lädt den Vorname des Benutzers aus Firestore
   */
  async function loadUserVorname() {
    if (!userAuthData || !userAuthData.uid || !userAuthData.companyId) {
      return null;
    }

    try {
      // Versuche 1: Direkte Abfrage mit UID als Dokument-ID
      const mitarbeiterRef = doc(db, "kunden", userAuthData.companyId, "mitarbeiter", userAuthData.uid);
      const mitarbeiterSnap = await getDoc(mitarbeiterRef);
      
      if (mitarbeiterSnap.exists()) {
        const mitarbeiterData = mitarbeiterSnap.data();
        const vorname = mitarbeiterData.vorname || null;
        if (vorname) {
          return vorname.trim();
        }
      }
      
      // Versuche 2: Suche nach uid-Feld in der mitarbeiter Collection
      const mitarbeiterCollection = collection(db, "kunden", userAuthData.companyId, "mitarbeiter");
      const uidQuery = query(mitarbeiterCollection, where("uid", "==", userAuthData.uid));
      const uidSnapshot = await getDocs(uidQuery);
      
      if (!uidSnapshot.empty) {
        const mitarbeiterDoc = uidSnapshot.docs[0];
        const mitarbeiterData = mitarbeiterDoc.data();
        const vorname = mitarbeiterData.vorname || null;
        if (vorname) {
          return vorname.trim();
        }
      }
      
      return null;
    } catch (error) {
      console.error("Fehler beim Laden des Vornamens:", error);
      return null;
    }
  }

  /**
   * Aktualisiert die Begrüßung mit Vorname
   */
  async function updateGreeting() {
    const greetingElement = document.getElementById("greetingText");
    if (!greetingElement) return;

    const greeting = getGreeting();
    const vorname = await loadUserVorname();
    
    if (vorname) {
      greetingElement.textContent = `${greeting} ${vorname}`;
    } else {
      greetingElement.textContent = greeting;
    }
  }

  /**
   * Formatiert den Wochentag auf Deutsch
   */
  function getDayName(date) {
    const dayNames = [
      'Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 
      'Donnerstag', 'Freitag', 'Samstag'
    ];
    return dayNames[date.getDay()];
  }

  /**
   * Aktualisiert die angezeigte Uhrzeit und das Datum im Format "Tag, TT. Monat HH:MM"
   */
  function updateTime() {
    const dateTimeElement = document.getElementById("dateTimeDisplay");
    if (!dateTimeElement) return;

    const now = new Date();
    const dayName = getDayName(now);
    const day = String(now.getDate()).padStart(2, '0');
    const monthNames = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];
    const month = monthNames[now.getMonth()];
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');
    
    dateTimeElement.textContent = `${dayName}, ${day}. ${month} - ${hours}:${minutes}`;
  }

});

