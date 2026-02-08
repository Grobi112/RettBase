// schichtplan.js
import { db } from "../../firebase-config.js"; // Relativer Pfad zum Root
import {
  collection,
  doc,
  setDoc,
  query,
  orderBy,
  onSnapshot,
    serverTimestamp,
    deleteDoc,
    getDoc,
    getDocs,
    writeBatch,
    updateDoc
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --- GLOBALE KONSTANTEN FÜR FARBEN UND STRUKTUR ---

/**
 * Prüft, ob eine Schicht eine Bereitschaft ist
 * @param {string} shiftId - Die Schicht-ID
 * @returns {boolean}
 */
function isBereitschaft(shiftId) {
    if (!shiftId) return false;
    const bereitschaftsSchichten = ['BTRK', 'BNRK', 'BTK', 'BNK'];
    return bereitschaftsSchichten.includes(shiftId.toUpperCase());
}

/**
 * Bestimmt die Icon-Farbe basierend auf der Hintergrundfarbe
 * @param {string} backgroundColor - Hex-Farbe (z.B. "#ffffff")
 * @returns {string} - "white" oder "black"
 */
function getIconColorForBackground(backgroundColor) {
    if (!backgroundColor) return "black";
    
    const color = backgroundColor.toLowerCase().trim();
    
    // Gelb und Weiß → schwarzes Icon
    if (color === '#ffef94' || color === '#fffbe6' || color === '#ffffff' || color === 'white' || color === '#fff' || color === '#ffff') {
        return 'black';
    }
    
    // Konvertiere Hex zu RGB für bessere Analyse
    let r = 0, g = 0, b = 0;
    if (color.startsWith('#')) {
        const hex = color.slice(1);
        if (hex.length === 3) {
            r = parseInt(hex[0] + hex[0], 16);
            g = parseInt(hex[1] + hex[1], 16);
            b = parseInt(hex[2] + hex[2], 16);
        } else if (hex.length === 6) {
            r = parseInt(hex.slice(0, 2), 16);
            g = parseInt(hex.slice(2, 4), 16);
            b = parseInt(hex.slice(4, 6), 16);
        }
    }
    
    // Berechne Helligkeit (Luminanz)
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    
    // Wenn die Farbe sehr hell ist (fast weiß/gelb) → schwarzes Icon
    if (luminance > 0.85) {
        return 'black';
    }
    
    // Bestimme dominante Farbe (Rot, Grün oder Blau)
    const max = Math.max(r, g, b);
    const isRed = r === max && r > 100;
    const isGreen = g === max && g > 100;
    const isBlue = b === max && b > 100;
    
    // Blau, Rot, Grün → weißes Icon
    if (isRed || isGreen || isBlue) {
        return 'white';
    }
    
    // Dunkle Farben → weißes Icon
    if (luminance < 0.5) {
        return 'white';
    }
    
    // Standard: schwarzes Icon für helle, nicht dominante Farben
    return 'black';
}

/**
 * Erstellt ein SVG-Trash-Icon mit angepasster Farbe
 * @param {string} iconColor - "white" oder "black"
 * @returns {string} - SVG-HTML
 */
function getTrashIcon(iconColor = 'black') {
    const color = iconColor === 'white' ? '#ffffff' : '#000000';
    return `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle;">
        <polyline points="3 6 5 6 21 6"></polyline>
        <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
        <line x1="10" y1="11" x2="10" y2="17"></line>
        <line x1="14" y1="11" x2="14" y2="17"></line>
    </svg>`;
}
let currentWache = "default";
let dayUnsubscribe = null; 
let ovdUnsubscribes = []; // Array von Unsubscribe-Funktionen für OVD
let isOVD = false;

// 🔥 MULTI-TENANT: Auth-Daten vom Parent
let userAuthData = null; // { role, companyId, uid }

// Die Hex-Farbe für "Gelb (Highlight)". Dies ist der SCHLÜSSEL zur Identifizierung von Springern.
const YELLOW_HIGHLIGHT_COLOR = "#fffbe6"; 

// Alle möglichen Schichten pro Wache
const WACHEN_SCHICHTEN = {
    RW_Holzwickede: ["RH1", "RH1T", "RH1N", "RH2", "RH2T", "RH2N"],
    RW_Fröndenberg: ["RF1", "RF1T", "RF1N", "RF2", "RF2T", "RF2N"],
    RW_Königsborn: ["RU1", "RU1T", "RU1N"],
    RW_Menden: ["RM1", "RM1T", "RM1N", "RM2", "RM2T", "RM2N"],
    KTW_Wache: ["KTW1T", "KTW1N", "KTW2T", "KTW2N", "KTW3", "KTW3F", "KTW3S", "KTW4", "KTW5", "KTW6"],
    default: [],
    OVD: []
};

const QUALIFIKATIONEN = ["RH", "RS", "RA", "NFS"];

// 🔥 MULTI-TENANT: Hole Auth-Daten vom Parent (Dashboard)
async function waitForAuthData() {
    return new Promise((resolve) => {
        // 1. Sende "Ich bin bereit" Nachricht an das Parent-Fenster
        if (window.parent) {
            window.parent.postMessage({ type: 'IFRAME_READY' }, '*');
            console.log("➡️ Schichtplan: IFRAME_READY gesendet");
        } else {
            console.error("Fehler: Kein Parent-Fenster gefunden.");
            resolve({ role: 'user', companyId: 'guest', uid: 'unknown' });
        }

        // 2. Erwarte die AUTH_DATA Nachricht vom Parent
        window.addEventListener('message', (event) => {
            if (event.data && event.data.type === 'AUTH_DATA') {
                console.log("⬅️ Schichtplan: AUTH_DATA empfangen");
                resolve(event.data.data); // event.data.data enthält { role, companyId, uid }
            }
        });
    });
}

// 🔥 MULTI-TENANT: Initialisiere Auth-Daten beim Laden
window.addEventListener('DOMContentLoaded', async () => {
    userAuthData = await waitForAuthData();
    console.log(`✅ Schichtplan: Auth-Daten geladen - Company: ${userAuthData.companyId}, Role: ${userAuthData.role}`);
    
    // Initialisiere die App erst nach dem Erhalt der Auth-Daten
    initializeApp();
});

// DOM-Elemente
const wacheSelect = document.getElementById("wacheSelect");
const addDayBtn = document.getElementById("addDayBtn");
const daysArea = document.getElementById("daysArea");
const initialMessage = document.getElementById("initialMessage");
const loadingIndicator = document.getElementById("loadingIndicator");
const ovdMessage = document.getElementById("ovdMessage");

// DOM-Elemente für die Gelb-Liste 
const showYellowListBtn = document.getElementById("showYellowListBtn");
const yellowListArea = document.getElementById("yellowListArea");

// Datum Popup
const datePopupOverlay = document.getElementById("datePopupOverlay");
const datePopupForm = document.getElementById("datePopupForm");
const newDayDateInput = document.getElementById("newDayDate");
const saveDayBtn = document.getElementById("saveDayBtn");

// Personal Popup
const personnelPopupOverlay = document.getElementById("personnelPopupOverlay");
const personnelPopupForm = document.getElementById("personnelPopupForm");
const savePersonnelBtn = document.getElementById("savePersonnelBtn");
const personnelMitarbeiterSelect = document.getElementById("personnelMitarbeiterSelect");
const qualGroup = document.getElementById("qualificationGroup");
const colorInput = document.getElementById("personnelColor");

// --- POPUP FUNKTIONEN ---

/**
 * Öffnet das Datum-Popup und setzt das Datum auf den nächsten Tag, falls vorhanden.
 */
function openDatePopup() {
    let targetDateValue;
    
    // Prüft, ob das Feld bereits einen Wert (vom letzten Speichern) hat
    if (newDayDateInput.value) {
        targetDateValue = newDayDateInput.value; 
    } else {
        // Falls leer, setze auf das heutige Datum
        const today = new Date();
        targetDateValue = today.getFullYear() + '-' + 
                          String(today.getMonth() + 1).padStart(2, '0') + '-' + 
                          String(today.getDate()).padStart(2, '0');
    }

    newDayDateInput.value = targetDateValue; 
    
    datePopupOverlay.style.display = "block";
    datePopupForm.style.display = "block";
}

window.closeDatePopup = function() {
    datePopupOverlay.style.display = "none";
    datePopupForm.style.display = "none";
}

/**
 * Öffnet das Personal-Popup
 */
// Globale Variable für gefilterte Mitarbeiter
let filteredMitarbeiter = [];

window.openPersonnelPopup = async function(dayId, shiftId, slotIndex, currentData = null, wacheId = null) {
    // Hole Elemente dynamisch, falls sie noch nicht geladen sind
    const mitarbeiterSelect = document.getElementById("personnelMitarbeiterSelect");
    const mitarbeiterSearch = document.getElementById("personnelMitarbeiterSearch");
    const qualGroupEl = document.getElementById("qualificationGroup");
    const colorInputEl = document.getElementById("personnelColor");
    
    if (!mitarbeiterSelect || !mitarbeiterSearch) {
        console.error("Personnel-Formular Elemente nicht gefunden");
        alert("Fehler: Personal-Formular nicht gefunden. Bitte laden Sie die Seite neu.");
        return;
    }
    
    if (!qualGroupEl) {
        console.error("qualificationGroup Element nicht gefunden");
        return;
    }
    
    if (!colorInputEl) {
        console.error("personnelColor Element nicht gefunden");
        return;
    }
    
    // Prüfe ZUERST, ob es eine Bereitschaft ist (BEVOR wir die dataset-Werte setzen)
    const isBereitschaftBefore = personnelPopupForm.dataset.isBereitschaft === 'true';
    console.log('🔍 openPersonnelPopup - isBereitschaft VOR setzen:', isBereitschaftBefore, 'dataset:', personnelPopupForm.dataset.isBereitschaft);
    
    // Speichere isBereitschaft Flag, falls es gesetzt ist
    const wasBereitschaft = personnelPopupForm.dataset.isBereitschaft === 'true';
    
    // Setze dataset-Werte
    personnelPopupForm.dataset.dayId = dayId;
    if (shiftId !== null && shiftId !== undefined) {
        personnelPopupForm.dataset.shiftId = shiftId;
        } else {
        delete personnelPopupForm.dataset.shiftId;
    }
    if (slotIndex !== null && slotIndex !== undefined) {
        personnelPopupForm.dataset.slotIndex = slotIndex;
    } else {
        delete personnelPopupForm.dataset.slotIndex;
    }
    if (wacheId !== null && wacheId !== undefined) {
        personnelPopupForm.dataset.wacheId = wacheId || currentWache;
    } else {
        delete personnelPopupForm.dataset.wacheId;
    }
    
    // Stelle sicher, dass isBereitschaft Flag erhalten bleibt
    if (wasBereitschaft) {
        personnelPopupForm.dataset.isBereitschaft = 'true';
    }
    
    // Prüfe NOCHMAL nach dem Setzen
    const isBereitschaft = personnelPopupForm.dataset.isBereitschaft === 'true';
    console.log('🔍 openPersonnelPopup - isBereitschaft NACH setzen:', isBereitschaft, 'dataset:', personnelPopupForm.dataset.isBereitschaft, 'wasBereitschaft:', wasBereitschaft); 

    // Lade Mitarbeiter, falls noch nicht geladen
    if (!allMitarbeiter || allMitarbeiter.length === 0) {
        await loadMitarbeiter();
    }

    // Funktion zum Filtern und Anzeigen der Mitarbeiter
    function filterAndRenderMitarbeiter(searchTerm = '') {
        filteredMitarbeiter = allMitarbeiter
            .filter(m => m.active !== false)
            .filter(m => {
                if (!searchTerm) return true;
                const searchLower = searchTerm.toLowerCase();
                return m.nachname.toLowerCase().includes(searchLower) || 
                       m.vorname.toLowerCase().includes(searchLower);
            })
            .sort((a, b) => {
                const nameA = `${a.nachname}, ${a.vorname}`;
                const nameB = `${b.nachname}, ${b.vorname}`;
                return nameA.localeCompare(nameB);
            });
        
        mitarbeiterSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
        filteredMitarbeiter.forEach(mitarbeiter => {
            const option = document.createElement('option');
            option.value = mitarbeiter.id;
            option.textContent = `${mitarbeiter.nachname}, ${mitarbeiter.vorname}`;
            if (currentData?.mitarbeiterId === mitarbeiter.id) {
                option.selected = true;
            }
            mitarbeiterSelect.appendChild(option);
        });
    }

    // Initial: Alle Mitarbeiter anzeigen
    filterAndRenderMitarbeiter();
    
    // Suchfunktion
    mitarbeiterSearch.value = '';
    mitarbeiterSearch.oninput = function() {
        filterAndRenderMitarbeiter(this.value);
    };

    // Event Listener für Mitarbeiter-Auswahl
    mitarbeiterSelect.onchange = function() {
        const selectedMitarbeiterId = this.value;
        const selectedMitarbeiter = allMitarbeiter.find(m => m.id === selectedMitarbeiterId);
        
        // Prüfe, ob es eine Bereitschaft ist (verwende die bereits deklarierte Variable aus dem äußeren Scope)
        const isBereitschaftInChange = personnelPopupForm.dataset.isBereitschaft === 'true';
        
        if (selectedMitarbeiter) {
            if (isBereitschaftInChange) {
                // Bei Bereitschaften: Zeige nur Qualifikationen als readonly, aber behalte das Bereitschafts-Typ-Dropdown
                const typSelect = document.getElementById("bereitschaftsTypSelect");
                if (typSelect) {
                    // Bereitschafts-Typ-Dropdown ist bereits vorhanden, nur Qualifikationen anzeigen
                    const qualSection = document.createElement('div');
                    qualSection.style.marginTop = '15px';
                    qualSection.innerHTML = `
                        <label style="display: block; margin-bottom: 8px; font-weight: 500;">Qualifikation (nur Anzeige):</label>
                        <div style="display: flex; flex-wrap: wrap; gap: 10px;">
                            ${QUALIFIKATIONEN.map(q => `
                                <label class="readonly-label" style="display: flex; align-items: center; gap: 5px;">
                                    <input type="checkbox" value="${q}" ${selectedMitarbeiter.qualifikation?.includes(q) ? 'checked' : ''} disabled>
                                    <span>${q}</span>
                                </label>
                            `).join('')}
                        </div>
                    `;
                    // Füge Qualifikationen nach dem Bereitschafts-Typ-Dropdown ein
                    if (typSelect.parentNode) {
                        typSelect.parentNode.appendChild(qualSection);
                    }
                }
            } else {
                // Normale Schicht: Zeige Qualifikationen als readonly an
                qualGroupEl.innerHTML = QUALIFIKATIONEN.map(q => `
                    <label class="readonly-label">
                        <input type="checkbox" name="qual" value="${q}" ${selectedMitarbeiter.qualifikation?.includes(q) ? 'checked' : ''} disabled>
                        <span>${q}</span>
                    </label>
                `).join('');
            }
        }
    };

    // Verwende die bereits deklarierte Variable isBereitschaft (Zeile 274)
    console.log('🔍 openPersonnelPopup - isBereitschaft:', isBereitschaft, 'dataset:', personnelPopupForm.dataset.isBereitschaft);
    
    // Wenn es eine Bereitschaft ist, zeige das Bereitschafts-Typ-Dropdown
    if (isBereitschaft) {
        console.log('✅ Bereitschaft erkannt - lade Bereitschafts-Typen');
        // Lade Bereitschafts-Typen, falls noch nicht geladen
        if (!allBereitschaftsTypen || allBereitschaftsTypen.length === 0) {
            await loadBereitschaftsTypen();
        }
        
        console.log('📋 Bereitschafts-Typen geladen:', allBereitschaftsTypen.length);
        
        if (allBereitschaftsTypen && allBereitschaftsTypen.length > 0) {
            // Verstecke qualificationGroup
            qualGroupEl.style.display = 'none';
            const qualLabel = document.getElementById("qualificationGroupLabel");
            if (qualLabel) {
                qualLabel.style.display = 'none';
            }
            
            // Zeige Bereitschafts-Typ-Dropdown
            const bereitschaftsTypLabel = document.getElementById("bereitschaftsTypLabel");
            const bereitschaftsTypSelect = document.getElementById("bereitschaftsTypSelect");
            
            if (bereitschaftsTypLabel && bereitschaftsTypSelect) {
                // Fülle das Dropdown
                bereitschaftsTypSelect.innerHTML = `
                    <option value="">-- Bitte auswählen --</option>
                    ${allBereitschaftsTypen.map(typ => `<option value="${typ.id}">${typ.name}${typ.beschreibung ? ' - ' + typ.beschreibung : ''}</option>`).join('')}
                `;
                bereitschaftsTypSelect.required = true;
                
                // Zeige Label und Dropdown
                bereitschaftsTypLabel.style.display = 'block';
                bereitschaftsTypSelect.style.display = 'block';
                bereitschaftsTypSelect.style.visibility = 'visible';
                bereitschaftsTypSelect.style.opacity = '1';
                
                console.log('✅ Bereitschafts-Typ-Dropdown angezeigt in openPersonnelPopup');
            } else {
                console.error('❌ Bereitschafts-Typ-Dropdown Elemente nicht gefunden!');
            }
        } else {
            qualGroupEl.innerHTML = `
                <div style="padding: 10px; background-color: #fff3cd; border: 1px solid #ffc107; border-radius: 4px; margin-bottom: 15px;">
                    <strong>Hinweis:</strong> Bitte legen Sie zuerst mindestens einen Bereitschafts-Typ in den Einstellungen an.
                </div>
            `;
            console.warn('⚠️ Keine Bereitschafts-Typen vorhanden');
        }
        
        // Verstecke Hintergrundfarbe für Bereitschaften
        const colorLabel = colorInputEl.closest('label');
        if (colorLabel) {
            colorLabel.style.display = 'none';
        }
    } else {
        console.log('ℹ️ Normale Schicht - kein Bereitschafts-Typ-Dropdown');
    }
    
    // Wenn bereits Daten vorhanden sind, fülle die Felder
    if (currentData) {
        if (currentData.mitarbeiterId) {
            mitarbeiterSelect.value = currentData.mitarbeiterId;
            // Trigger change event, um Qualifikationen zu füllen
            mitarbeiterSelect.dispatchEvent(new Event('change'));
        } else {
            // Fallback für alte Daten ohne mitarbeiterId
            if (!isBereitschaft) {
                qualGroupEl.innerHTML = QUALIFIKATIONEN.map(q => `
                    <label class="readonly-label">
                        <input type="checkbox" name="qual" value="${q}" ${currentData?.qualifikationen?.includes(q) ? 'checked' : ''} disabled>
                        <span>${q}</span>
                    </label>
                `).join('');
            }
        }
        if (!isBereitschaft) {
            colorInputEl.value = currentData.farbe || '#ffffff';
        }
    } else {
        // Reset für neue Eingabe - NUR wenn es KEINE Bereitschaft ist
        if (!isBereitschaft) {
            qualGroupEl.innerHTML = '';
            colorInputEl.value = '#ffffff';
        }
        // Bei Bereitschaften wird das Dropdown in openAddBereitschaftPopup erstellt
    }

    personnelPopupOverlay.style.display = "block";
    personnelPopupForm.style.display = "block";
}

window.closePersonnelPopup = function() {
    personnelPopupOverlay.style.display = "none";
    personnelPopupForm.style.display = "none";
    
    // Reset Bereitschafts-Flag
    delete personnelPopupForm.dataset.isBereitschaft;
    
    // Reset Qualifikationen-Gruppe und Label
    const qualGroup = document.getElementById("qualificationGroup");
    if (qualGroup) {
        qualGroup.style.display = '';
        qualGroup.innerHTML = '';
    }
    
    const qualLabel = document.getElementById("qualificationGroupLabel");
    if (qualLabel) {
        qualLabel.style.display = '';
    }
    
    // Verstecke Bereitschafts-Typ-Dropdown
    const bereitschaftsTypLabel = document.getElementById("bereitschaftsTypLabel");
    const bereitschaftsTypSelect = document.getElementById("bereitschaftsTypSelect");
    if (bereitschaftsTypLabel) {
        bereitschaftsTypLabel.style.display = 'none';
    }
    if (bereitschaftsTypSelect) {
        bereitschaftsTypSelect.style.display = 'none';
        bereitschaftsTypSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
    }
    
    // Zeige Hintergrundfarbe wieder an
    const colorLabel = document.getElementById("personnelColorLabel");
    if (colorLabel) {
        colorLabel.style.display = '';
    }
}

// --- HILFSFUNKTIONEN ---

/**
 * 🔥 MULTI-TENANT: Erstellt den korrekten Firestore-Pfad für Schichtplan-Daten
 * Pfad: kunden/{companyId}/schichtplan/{wacheId}/tage/{dayId}/schichten/{shiftId}
 */
function getSchichtplanPath(wacheId, dayId = null, shiftId = null) {
    if (!userAuthData || !userAuthData.companyId) {
        console.error("❌ Keine Auth-Daten verfügbar für Schichtplan-Pfad");
        throw new Error("Keine Auth-Daten verfügbar");
    }
    
    const companyId = userAuthData.companyId;
    let path = ["kunden", companyId, "schichtplan", wacheId];
    
    if (dayId) {
        path.push("tage", dayId);
        if (shiftId) {
            path.push("schichten", shiftId);
        }
    }
    
    return path;
}

/**
 * Gibt den Firestore-Pfad für Bereitschaften zurück
 * Pfad: kunden/{companyId}/schichtplanBereitschaften/{dayId}/bereitschaften/{bereitschaftId}
 * @param {string} dayId - Der Tag-ID (DD.MM.YYYY)
 * @param {string} bereitschaftId - Optional: Die Bereitschaft-ID
 * @returns {Array} Firestore-Pfad als Array
 */
function getBereitschaftenPath(dayId, bereitschaftId = null) {
    const companyId = getCompanyId();
    const path = ['kunden', companyId, 'schichtplanBereitschaften', dayId, 'bereitschaften'];
    if (bereitschaftId) path.push(bereitschaftId);
    return path;
}

/**
 * Gibt die Company-ID zurück
 */
function getCompanyId() {
    if (!userAuthData || !userAuthData.companyId) {
        console.error("❌ Keine Auth-Daten verfügbar");
        throw new Error("Keine Auth-Daten verfügbar");
    }
    return userAuthData.companyId;
}

/**
 * Firestore-Pfad für Bereitschafts-Typen
 * Pfad: kunden/{companyId}/schichtplanBereitschaftsTypen/{typId}
 */
function getBereitschaftsTypenPath(typId = null) {
    const companyId = getCompanyId();
    const path = ['kunden', companyId, 'schichtplanBereitschaftsTypen'];
    if (typId) path.push(typId);
    return path;
}

/**
 * Lädt alle Bereitschafts-Typen
 */
async function loadBereitschaftsTypen() {
    try {
        const typenRef = collection(db, ...getBereitschaftsTypenPath());
        const q = query(typenRef, orderBy('name'));
        const snapshot = await getDocs(q);
        
        allBereitschaftsTypen = [];
        snapshot.forEach(doc => {
            allBereitschaftsTypen.push({
                id: doc.id,
                ...doc.data()
            });
        });
        
        renderBereitschaftsTypenList();
        return allBereitschaftsTypen;
    } catch (error) {
        console.error("Fehler beim Laden der Bereitschafts-Typen:", error);
        return [];
    }
}

/**
 * Rendert die Liste der Bereitschafts-Typen
 */
function renderBereitschaftsTypenList() {
    const list = document.getElementById("bereitschaftsTypenList");
    if (!list) return;
    
    if (allBereitschaftsTypen.length === 0) {
        list.innerHTML = '<p class="empty-message">Keine Bereitschafts-Typen vorhanden.</p>';
        return;
    }
    
    list.innerHTML = allBereitschaftsTypen.map(typ => `
        <div class="settings-item">
            <div class="settings-item-info">
                <strong>${typ.name}</strong>
                ${typ.beschreibung ? `<span class="settings-item-desc">${typ.beschreibung}</span>` : ''}
            </div>
            <div class="settings-item-actions">
                <button class="control-btn" onclick="editBereitschaftsTyp('${typ.id}')" title="Bearbeiten">✏️</button>
                <button class="control-btn" onclick="deleteBereitschaftsTyp('${typ.id}')" title="Löschen">${getTrashIcon('black')}</button>
            </div>
        </div>
    `).join('');
}

/**
 * Speichert einen Bereitschafts-Typ
 */
async function saveBereitschaftsTyp() {
    const nameInput = document.getElementById("bereitschaftsTypName");
    const beschreibungInput = document.getElementById("bereitschaftsTypBeschreibung");
    
    if (!nameInput || !nameInput.value.trim()) {
        alert("Bitte geben Sie einen Namen ein.");
        return;
    }
    
    try {
        const typData = {
            name: nameInput.value.trim(),
            beschreibung: beschreibungInput?.value?.trim() || '',
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp()
        };
        
        if (currentEditingBereitschaftsTypId) {
            const typRef = doc(db, ...getBereitschaftsTypenPath(currentEditingBereitschaftsTypId));
            await updateDoc(typRef, {
                ...typData,
                updatedAt: serverTimestamp()
            });
        } else {
            const typRef = doc(collection(db, ...getBereitschaftsTypenPath()));
            await setDoc(typRef, typData);
        }
        
        closeBereitschaftsTypForm();
        await loadBereitschaftsTypen();
    } catch (error) {
        console.error("Fehler beim Speichern des Bereitschafts-Typs:", error);
        alert("Fehler beim Speichern: " + error.message);
    }
}

/**
 * Bearbeitet einen Bereitschafts-Typ
 */
window.editBereitschaftsTyp = function(typId) {
    const typ = allBereitschaftsTypen.find(t => t.id === typId);
    if (!typ) return;
    
    currentEditingBereitschaftsTypId = typId;
    const nameInput = document.getElementById("bereitschaftsTypName");
    const beschreibungInput = document.getElementById("bereitschaftsTypBeschreibung");
    const formTitle = document.getElementById("bereitschaftsTypFormTitle");
    
    if (nameInput) nameInput.value = typ.name || '';
    if (beschreibungInput) beschreibungInput.value = typ.beschreibung || '';
    if (formTitle) formTitle.textContent = "Bereitschafts-Typ bearbeiten";
    
    openBereitschaftsTypForm();
}

/**
 * Löscht einen Bereitschafts-Typ
 */
window.deleteBereitschaftsTyp = async function(typId) {
    if (!confirm("Möchten Sie diesen Bereitschafts-Typ wirklich löschen?")) return;
    
    try {
        const typRef = doc(db, ...getBereitschaftsTypenPath(typId));
        await deleteDoc(typRef);
        await loadBereitschaftsTypen();
    } catch (error) {
        console.error("Fehler beim Löschen des Bereitschafts-Typs:", error);
        alert("Fehler beim Löschen: " + error.message);
    }
}

/**
 * Öffnet das Formular für Bereitschafts-Typen
 */
window.openBereitschaftsTypForm = function() {
    const overlay = document.getElementById("bereitschaftsTypFormOverlay");
    const form = document.getElementById("bereitschaftsTypForm");
    const formTitle = document.getElementById("bereitschaftsTypFormTitle");
    const nameInput = document.getElementById("bereitschaftsTypName");
    const beschreibungInput = document.getElementById("bereitschaftsTypBeschreibung");
    
    if (!overlay || !form) return;
    
    if (!currentEditingBereitschaftsTypId) {
        if (formTitle) formTitle.textContent = "Bereitschafts-Typ hinzufügen";
        if (nameInput) nameInput.value = '';
        if (beschreibungInput) beschreibungInput.value = '';
    }
    
    overlay.style.display = 'block';
    form.style.display = 'block';
}

/**
 * Schließt das Formular für Bereitschafts-Typen
 */
window.closeBereitschaftsTypForm = function() {
    const overlay = document.getElementById("bereitschaftsTypFormOverlay");
    const form = document.getElementById("bereitschaftsTypForm");
    
    if (overlay) overlay.style.display = 'none';
    if (form) form.style.display = 'none';
    
    currentEditingBereitschaftsTypId = null;
}

/**
 * Öffnet die Bereitschaften-Ansicht
 */
window.openBereitschaftenView = async function() {
    const overlay = document.getElementById("bereitschaftenViewOverlay");
    const form = document.getElementById("bereitschaftenViewForm");
    const dateInput = document.getElementById("bereitschaftenDateSelect");
    
    if (!overlay || !form) return;
    
    if (dateInput) {
        const today = new Date();
        dateInput.value = today.toISOString().split('T')[0];
        
        // Entferne alte Event Listener und füge einen neuen hinzu
        const newDateInput = dateInput.cloneNode(true);
        dateInput.parentNode.replaceChild(newDateInput, dateInput);
        document.getElementById("bereitschaftenDateSelect").addEventListener('change', (e) => {
            loadBereitschaftenForDate(e.target.value);
        });
    }
    
    overlay.style.display = 'block';
    form.style.display = 'block';
    
    // Lade Daten für das aktuelle Datum
    if (dateInput) {
        await loadBereitschaftenForDate(dateInput.value);
    }
}

/**
 * Schließt die Bereitschaften-Ansicht
 */
window.closeBereitschaftenView = function() {
    const overlay = document.getElementById("bereitschaftenViewOverlay");
    const form = document.getElementById("bereitschaftenViewForm");
    
    if (overlay) overlay.style.display = 'none';
    if (form) form.style.display = 'none';
}

/**
 * Lädt Bereitschaften für ein bestimmtes Datum
 */
async function loadBereitschaftenForDate(dateString) {
    if (!dateString) return;
    
    const dayId = formatDayId(new Date(dateString));
    const content = document.getElementById("bereitschaftenViewContent");
    if (!content) return;
    
    content.innerHTML = '<p>Lade Bereitschaften...</p>';
    
    try {
        // Stelle sicher, dass Mitarbeiter und Bereitschafts-Typen geladen sind
        if (!allMitarbeiter || allMitarbeiter.length === 0) {
            await loadMitarbeiter();
        }
        if (!allBereitschaftsTypen || allBereitschaftsTypen.length === 0) {
            await loadBereitschaftsTypen();
        }
        
        const bereitschaftenRef = collection(db, ...getBereitschaftenPath(dayId));
        const snapshot = await getDocs(bereitschaftenRef);
        
        const bereitschaften = [];
        snapshot.forEach(doc => {
            bereitschaften.push({
                id: doc.id,
                ...doc.data()
            });
        });
        
        console.log(`📋 Geladene Bereitschaften für ${dayId}:`, bereitschaften.length);
        renderBereitschaftenList(dayId, bereitschaften);
    } catch (error) {
        console.error("Fehler beim Laden der Bereitschaften:", error);
        content.innerHTML = '<p class="error">Fehler beim Laden der Bereitschaften: ' + error.message + '</p>';
    }
}

/**
 * Rendert die Liste der Bereitschaften für einen Tag
 */
function renderBereitschaftenList(dayId, bereitschaften) {
    const content = document.getElementById("bereitschaftenViewContent");
    if (!content) return;
    
    if (bereitschaften.length === 0) {
        content.innerHTML = '<p class="empty-message">Keine Bereitschaften für diesen Tag.</p>';
        return;
    }
    
    content.innerHTML = bereitschaften.map(bereitschaft => {
        const mitarbeiter = allMitarbeiter.find(m => m.id === bereitschaft.mitarbeiterId);
        const typ = allBereitschaftsTypen.find(t => t.id === bereitschaft.typId);
        const mitarbeiterName = mitarbeiter ? `${mitarbeiter.nachname}, ${mitarbeiter.vorname}` : 'Unbekannt';
        const typName = typ ? typ.name : 'Unbekannt';
        
        return `
            <div class="bereitschaft-item-view" data-bereitschaft-id="${bereitschaft.id}" data-day-id="${dayId}" data-mitarbeiter-id="${bereitschaft.mitarbeiterId}">
                <div class="bereitschaft-item-info">
                    <strong>${mitarbeiterName}</strong>
                    <span class="bereitschaft-typ">${typName}</span>
                </div>
                <div class="bereitschaft-item-actions">
                    <button class="control-btn" onclick="deleteBereitschaft('${dayId}', '${bereitschaft.id}')" title="Löschen">${getTrashIcon('black')}</button>
                </div>
            </div>
        `;
    }).join('');
    
    setupBereitschaftenContextMenu();
}

/**
 * Öffnet das Popup zum Hinzufügen einer Bereitschaft
 * @param {string} dayId - Optional: Wenn nicht angegeben, wird das Datum aus dem Input-Feld gelesen
 */
window.openAddBereitschaftPopup = async function(dayId = null) {
    // Wenn dayId nicht übergeben wurde, lese es aus dem Input-Feld
    if (!dayId) {
        const dateInput = document.getElementById("bereitschaftenDateSelect");
        if (!dateInput || !dateInput.value) {
            alert("Bitte wählen Sie zuerst ein Datum aus.");
            return;
        }
        dayId = formatDayId(new Date(dateInput.value));
    }
    
    // Lade Daten, falls noch nicht geladen
    if (!allMitarbeiter || allMitarbeiter.length === 0) {
        await loadMitarbeiter();
    }
    if (!allBereitschaftsTypen || allBereitschaftsTypen.length === 0) {
        await loadBereitschaftsTypen();
    }
    
    // Prüfe, ob Bereitschafts-Typen vorhanden sind
    if (!allBereitschaftsTypen || allBereitschaftsTypen.length === 0) {
        alert("Bitte legen Sie zuerst mindestens einen Bereitschafts-Typ in den Einstellungen an.");
        return;
    }
    
    // Setze das Flag VOR dem Öffnen des Popups
    personnelPopupForm.dataset.isBereitschaft = 'true';
    personnelPopupForm.dataset.dayId = dayId;
    delete personnelPopupForm.dataset.shiftId;
    delete personnelPopupForm.dataset.slotIndex;
    delete personnelPopupForm.dataset.wacheId;
    
    // Ändere das Label SOFORT
    const qualLabel = document.getElementById("qualificationGroupLabel");
    if (qualLabel) {
        qualLabel.textContent = "Bereitschafts-Typ:";
        qualLabel.style.display = 'block';
    }
    
    // Verstecke Hintergrundfarbe SOFORT
    const colorLabel = document.getElementById("personnelColorLabel");
    if (colorLabel) {
        colorLabel.style.display = 'none';
    }
    
    // Öffne das Personal-Popup
    await openPersonnelPopup(dayId, null, null, null, null);
    
    // Stelle sicher, dass das Dropdown angezeigt wird
    setTimeout(() => {
        console.log('🔍 setTimeout - Suche Dropdown-Elemente...');
        const bereitschaftsTypLabel = document.getElementById("bereitschaftsTypLabel");
        const bereitschaftsTypSelect = document.getElementById("bereitschaftsTypSelect");
        
        console.log('🔍 Label gefunden:', !!bereitschaftsTypLabel);
        console.log('🔍 Select gefunden:', !!bereitschaftsTypSelect);
        console.log('🔍 Bereitschafts-Typen:', allBereitschaftsTypen?.length || 0);
        
        if (bereitschaftsTypLabel && bereitschaftsTypSelect && allBereitschaftsTypen && allBereitschaftsTypen.length > 0) {
            // Fülle das Dropdown
            bereitschaftsTypSelect.innerHTML = `
                <option value="">-- Bitte auswählen --</option>
                ${allBereitschaftsTypen.map(typ => `<option value="${typ.id}">${typ.name}${typ.beschreibung ? ' - ' + typ.beschreibung : ''}</option>`).join('')}
            `;
            bereitschaftsTypSelect.required = true;
            
            // Zeige Label und Dropdown - mit !important
            bereitschaftsTypLabel.style.setProperty('display', 'block', 'important');
            bereitschaftsTypSelect.style.setProperty('display', 'block', 'important');
            bereitschaftsTypSelect.style.setProperty('visibility', 'visible', 'important');
            bereitschaftsTypSelect.style.setProperty('opacity', '1', 'important');
            
            // Prüfe ob es wirklich sichtbar ist
            const computedDisplay = window.getComputedStyle(bereitschaftsTypSelect).display;
            const computedVisibility = window.getComputedStyle(bereitschaftsTypSelect).visibility;
            console.log('✅ Bereitschafts-Typ-Dropdown angezeigt in setTimeout');
            console.log('✅ Computed display:', computedDisplay);
            console.log('✅ Computed visibility:', computedVisibility);
            
            // Falls es immer noch nicht sichtbar ist, versuche es anders
            if (computedDisplay === 'none' || computedVisibility === 'hidden') {
                console.warn('⚠️ Dropdown ist immer noch versteckt, versuche alternative Methode...');
                bereitschaftsTypSelect.removeAttribute('style');
                bereitschaftsTypSelect.style.cssText = 'display: block !important; visibility: visible !important; opacity: 1 !important; width: 100%; padding: 12px; border: 2px solid #007bff; border-radius: 8px; font-size: 16px; margin-bottom: 15px; background-color: white;';
            }
        } else {
            console.error('❌ Bereitschafts-Typ-Dropdown Elemente nicht gefunden oder keine Typen vorhanden!', {
                label: !!bereitschaftsTypLabel,
                select: !!bereitschaftsTypSelect,
                typen: allBereitschaftsTypen?.length || 0
            });
        }
    }, 200);
}

/**
 * Speichert eine neue Bereitschaft
 */
window.saveBereitschaft = async function(dayId, mitarbeiterId, typId) {
    if (!dayId || !mitarbeiterId || !typId) {
        alert("Bitte füllen Sie alle Felder aus.");
        return;
    }
    
    try {
        // Stelle sicher, dass das dayId-Document existiert (wird automatisch erstellt)
        const companyId = getCompanyId();
        const dayDocPath = ['kunden', companyId, 'schichtplanBereitschaften', dayId];
        const dayDocRef = doc(db, ...dayDocPath);
        
        // Erstelle das dayId-Document, falls es nicht existiert
        const dayDocSnap = await getDoc(dayDocRef);
        if (!dayDocSnap.exists()) {
            await setDoc(dayDocRef, {
                dayId: dayId,
                createdAt: serverTimestamp()
            });
        }
        
        // Jetzt speichere die Bereitschaft in der Subcollection
        const bereitschaftRef = doc(collection(db, ...getBereitschaftenPath(dayId)));
        await setDoc(bereitschaftRef, {
            mitarbeiterId: mitarbeiterId,
            typId: typId,
            createdAt: serverTimestamp()
        });
        
        closePersonnelPopup();
        
        // Aktualisiere die Bereitschaften-Liste
        const dateInput = document.getElementById("bereitschaftenDateSelect");
        if (dateInput && dateInput.value) {
            await loadBereitschaftenForDate(dateInput.value);
        }
        
        console.log(`✅ Bereitschaft gespeichert für ${dayId}`);
    } catch (error) {
        console.error("Fehler beim Speichern der Bereitschaft:", error);
        alert("Fehler beim Speichern: " + error.message);
    }
}

/**
 * Löscht eine Bereitschaft
 */
window.deleteBereitschaft = async function(dayId, bereitschaftId) {
    if (!confirm("Möchten Sie diese Bereitschaft wirklich löschen?")) return;
    
    try {
        const bereitschaftRef = doc(db, ...getBereitschaftenPath(dayId, bereitschaftId));
        await deleteDoc(bereitschaftRef);
        
        // Aktualisiere die Bereitschaften-Liste
        const dateInput = document.getElementById("bereitschaftenDateSelect");
        if (dateInput && dateInput.value) {
            await loadBereitschaftenForDate(dateInput.value);
        }
        
        console.log(`✅ Bereitschaft gelöscht: ${bereitschaftId}`);
    } catch (error) {
        console.error("Fehler beim Löschen der Bereitschaft:", error);
        alert("Fehler beim Löschen: " + error.message);
    }
}

/**
 * Richtet das Context-Menu für Bereitschaften ein
 */
function setupBereitschaftenContextMenu() {
    document.removeEventListener('contextmenu', handleBereitschaftenContextMenu);
    document.removeEventListener('touchstart', handleBereitschaftenTouchStart);
    document.removeEventListener('touchend', handleBereitschaftenTouchEnd);
    
    document.addEventListener('contextmenu', handleBereitschaftenContextMenu, true);
    document.addEventListener('touchstart', handleBereitschaftenTouchStart, { passive: false });
    document.addEventListener('touchend', handleBereitschaftenTouchEnd, { passive: false });
}

let bereitschaftenTouchStartTime = null;
let bereitschaftenTouchTarget = null;

function handleBereitschaftenContextMenu(e) {
    if (!e.target || typeof e.target.closest !== 'function') return;
    const item = e.target.closest('.bereitschaft-item-view');
    if (!item) return;
    
    e.preventDefault();
    e.stopImmediatePropagation();
    
    const bereitschaftId = item.dataset.bereitschaftId;
    const dayId = item.dataset.dayId;
    const mitarbeiterId = item.dataset.mitarbeiterId;
    
    showBereitschaftAssignmentMenu(bereitschaftId, dayId, mitarbeiterId, e.clientX, e.clientY);
}

function handleBereitschaftenTouchStart(e) {
    if (!e.target || typeof e.target.closest !== 'function') return;
    const item = e.target.closest('.bereitschaft-item-view');
    if (!item) return;
    
    bereitschaftenTouchStartTime = Date.now();
    bereitschaftenTouchTarget = item;
    e.preventDefault();
}

function handleBereitschaftenTouchEnd(e) {
    if (!bereitschaftenTouchTarget) return;
    
    const touchDuration = Date.now() - bereitschaftenTouchStartTime;
    if (touchDuration > 500) {
        e.preventDefault();
        const item = bereitschaftenTouchTarget;
        const bereitschaftId = item.dataset.bereitschaftId;
        const dayId = item.dataset.dayId;
        const mitarbeiterId = item.dataset.mitarbeiterId;
        
        const touch = e.changedTouches[0];
        showBereitschaftAssignmentMenu(bereitschaftId, dayId, mitarbeiterId, touch.clientX, touch.clientY);
    }
    
    bereitschaftenTouchStartTime = null;
    bereitschaftenTouchTarget = null;
}

/**
 * Zeigt das Zuweisungs-Menü für Bereitschaften
 */
async function showBereitschaftAssignmentMenu(bereitschaftId, dayId, mitarbeiterId, x, y) {
    const openShifts = await getAllOpenShifts();
    
    if (openShifts.length === 0) {
        alert("Keine offenen Schichten gefunden.");
    return;
    }
    
    const menu = document.createElement('div');
    menu.className = 'context-menu';
    menu.style.position = 'fixed';
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;
    menu.style.zIndex = '10000';
    menu.style.backgroundColor = 'white';
    menu.style.border = '1px solid #ccc';
    menu.style.borderRadius = '4px';
    menu.style.padding = '8px 0';
    menu.style.boxShadow = '0 2px 8px rgba(0,0,0,0.15)';
    menu.style.maxHeight = '300px';
    menu.style.overflowY = 'auto';
    
    menu.innerHTML = `
        <div style="padding: 8px 16px; font-weight: bold; border-bottom: 1px solid #eee;">Schicht zuweisen:</div>
        ${openShifts.map(shift => `
            <div class="context-menu-item" style="padding: 8px 16px; cursor: pointer;" 
                 onclick="assignBereitschaftToShift('${bereitschaftId}', '${dayId}', '${mitarbeiterId}', '${shift.dayId}', '${shift.wacheId}', '${shift.shiftId}', '${shift.slotIndex}')">
                ${shift.standortName} - ${shift.schichtName} (Slot ${shift.slotIndex})
            </div>
        `).join('')}
    `;
    
    document.body.appendChild(menu);
    
    const closeMenu = (e) => {
        if (!menu.contains(e.target)) {
            menu.remove();
            document.removeEventListener('click', closeMenu);
        }
    };
    
    setTimeout(() => {
        document.addEventListener('click', closeMenu);
    }, 100);
}

/**
 * Lädt alle offenen Schichten
 */
async function getAllOpenShifts() {
    const openShifts = [];
    const companyId = getCompanyId();
    
    try {
        if (!allStandorte || allStandorte.length === 0) {
            await loadStandorte();
        }
        
        for (const standort of allStandorte.filter(s => s.active !== false)) {
            const tageRef = collection(db, 'kunden', companyId, 'schichtplan', standort.id, 'tage');
            const tageSnapshot = await getDocs(tageRef);
            
            for (const tagDoc of tageSnapshot.docs) {
                const dayId = tagDoc.id;
                const schichtenRef = collection(db, 'kunden', companyId, 'schichtplan', standort.id, 'tage', dayId, 'schichten');
                const schichtenSnapshot = await getDocs(schichtenRef);
                
                for (const schichtDoc of schichtenSnapshot.docs) {
                    const schichtData = schichtDoc.data();
                    
                    if (!schichtData.personal1 || !schichtData.personal1.mitarbeiterId) {
                        openShifts.push({
                            dayId: dayId,
                            wacheId: standort.id,
                            shiftId: schichtDoc.id,
                            standortName: standort.name,
                            schichtName: schichtData.schichtName || schichtDoc.id,
                            slotIndex: 1
                        });
                    }
                    
                    if (!isBereitschaft(schichtData.schichtName || schichtDoc.id)) {
                        if (!schichtData.personal2 || !schichtData.personal2.mitarbeiterId) {
                            openShifts.push({
                                dayId: dayId,
                                wacheId: standort.id,
                                shiftId: schichtDoc.id,
                                standortName: standort.name,
                                schichtName: schichtData.schichtName || schichtDoc.id,
                                slotIndex: 2
                            });
                        }
                    }
                }
            }
        }
    } catch (error) {
        console.error("Fehler beim Laden der offenen Schichten:", error);
    }
    
    return openShifts;
}

/**
 * Weist eine Bereitschaft einer Schicht zu
 */
window.assignBereitschaftToShift = async function(bereitschaftId, bereitDayId, mitarbeiterId, targetDayId, targetWacheId, targetShiftId, targetSlotIndex) {
    try {
        const shiftPath = getSchichtplanPath(targetWacheId, targetDayId, targetShiftId);
        const shiftRef = doc(db, ...shiftPath);
        
        const personalField = `personal${targetSlotIndex}`;
        const mitarbeiter = allMitarbeiter.find(m => m.id === mitarbeiterId);
        
        if (!mitarbeiter) {
            alert("Mitarbeiter nicht gefunden.");
      return;
    }
    
        await updateDoc(shiftRef, {
            [personalField]: {
                mitarbeiterId: mitarbeiterId,
                name: `${mitarbeiter.nachname}, ${mitarbeiter.vorname}`,
                qualifikation: mitarbeiter.qualifikation || [],
                telefon: mitarbeiter.telefon || '',
                fuehrerschein: mitarbeiter.fuehrerschein || ''
            }
        });
        
        await deleteBereitschaft(bereitDayId, bereitschaftId);
        
        document.querySelectorAll('.context-menu').forEach(menu => menu.remove());
        
        alert("Bereitschaft erfolgreich zugewiesen!");
    } catch (error) {
        console.error("Fehler beim Zuweisen der Bereitschaft:", error);
        alert("Fehler beim Zuweisen: " + error.message);
    }
}

let currentEditingBereitschaftsTypId = null;

/**
 * Ruft die Schicht-Dokumente für einen Tag ab. (HILFSFUNKTION)
 */
async function getShiftDocs(dayId, wacheId) {
    const path = getSchichtplanPath(wacheId, dayId);
    const shiftsColRef = collection(db, ...path, "schichten");
    const q = query(shiftsColRef); 
    const snapshot = await getDocs(q); 
    return snapshot.docs.map(doc => ({ 
        id: doc.id
    }));
}

/**
 * Hilfsfunktion zur Berechnung des nächsten Tages
 */
function getNextDay(dateString) {
    // dateString kommt im Format YYYY-MM-DD
    const parts = dateString.split('-');
    // Erstellt ein Datumsobjekt: new Date(YYYY, MM - 1, DD)
    const date = new Date(parts[0], parts[1] - 1, parts[2]); 
    date.setDate(date.getDate() + 1); // Erhöht den Tag um 1
    
    // Formatiert das Datum zurück in YYYY-MM-DD (für input type="date")
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
}


// --- LÖSCH FUNKTIONEN ---

/**
 * Personal löschen/leeren: Setzt das Personal-Feld auf null.
 */
window.removePersonnel = async function(dayId, shiftId, slotIndex, wacheId) {
    if (!confirm("Sicher, dass Sie diesen Personal-Eintrag entfernen möchten?")) return;

    const updateField = `personal${slotIndex}`;
    
    try {
        const path = getSchichtplanPath(wacheId, dayId, shiftId);
        const shiftRef = doc(db, ...path);
        
        await setDoc(shiftRef, {
            [updateField]: null
        }, { merge: true }); 

        console.log(`Personal aus Slot ${slotIndex} von Schicht ${shiftId} für Wache ${wacheId} entfernt.`);
    } catch (error) {
        console.error("Fehler beim Entfernen des Personals:", error);
        alert("Fehler beim Entfernen des Personals: " + error.message);
    }
}

/**
 * Schicht löschen: Löscht das Schicht-Dokument.
 */
window.deleteShift = async function(dayId, shiftId, wacheId, skipConfirm = false) { 
    if (!skipConfirm && !confirm(`Sicher, dass Sie die Schicht ${shiftId} am ${dayId} für ${wacheId} löschen möchten?`)) return;

    try {
        const path = getSchichtplanPath(wacheId, dayId, shiftId);
        const shiftRef = doc(db, ...path);
        await deleteDoc(shiftRef);
        console.log(`Schicht ${shiftId} gelöscht.`);
    } catch (error) {
        console.error("Fehler beim Löschen der Schicht:", error);
        alert("Fehler beim Löschen der Schicht: " + error.message);
        throw error; 
    }
}


/**
 * Tag löschen: Führt kaskadierendes Löschen durch.
 */
window.deleteDay = async function(dayId, wacheId) {
    if (!confirm(`Sicher, dass Sie den Tag ${dayId} für ${wacheId} löschen möchten? Alle Schichten gehen verloren!`)) return; 

    try {
        // 1. Alle Unterschicht-Dokumente abrufen
        const shiftDocs = await getShiftDocs(dayId, wacheId);
        
        console.log(`Lösche ${shiftDocs.length} Schichten für Tag ${dayId}...`);

        // 2. Jede Schicht einzeln löschen (mit skipConfirm = true)
        for (const doc of shiftDocs) {
             await deleteShift(dayId, doc.id, wacheId, true); // Stille Löschung
        }

        // 3. Erst jetzt das übergeordnete Tages-Dokument löschen
        const dayPath = getSchichtplanPath(wacheId, dayId);
        const dayRef = doc(db, ...dayPath);
        await deleteDoc(dayRef);
        console.log(`Tag ${dayId} und alle Schichten gelöscht.`);
        
        // FIX: Auslösen des Change-Events auf dem Wachen-Selector, um den Zustand
        wacheSelect.dispatchEvent(new Event('change'));

    } catch (error) {
        console.error("Fehler beim Löschen des Tages (Kaskade fehlgeschlagen):", error);
        alert("Fehler beim Löschen des Tages: " + error.message);
    }
}


// --- FIRESTORE LOGIK: TAGE & SCHICHTEN ---

/**
 * Erstellt einen Tag und eine Standardschicht.
 */
saveDayBtn.addEventListener("click", async () => {
    const dateValue = newDayDateInput.value;
    if (!dateValue) {
        alert("Bitte ein Datum auswählen.");
        return;
    }

    // dateValue ist YYYY-MM-DD, dayId ist DD.MM.YYYY
    const [year, month, day] = dateValue.split('-');
    const dayId = `${day}.${month}.${year}`; 
    
    try {
        const dayPath = getSchichtplanPath(currentWache, dayId);
        const dayRef = doc(db, ...dayPath);
        
        await setDoc(dayRef, {
            datum: dayId,
            timestamp: serverTimestamp() 
        }, { merge: true });

        // Nur die ERSTE Schicht aus der Liste der verfügbaren Schichten erstellen
        // Lade Schichten, falls noch nicht geladen oder undefined
        if (!allSchichten || allSchichten.length === 0) {
            await loadSchichten();
        }
        
        // Prüfe erneut, ob Schichten vorhanden sind
        if (!allSchichten || allSchichten.length === 0) {
            console.warn("Keine Schichten verfügbar. Tag wird ohne Standard-Schicht erstellt.");
            closeDatePopup();
            if (dayUnsubscribe) dayUnsubscribe();
            daysArea.innerHTML = '';
            loadingIndicator.classList.remove('hidden'); 
            listenForDays();
            return;
        }
        
        // Filtere Schichten nach dem aktuellen Standort
        const activeShifts = allSchichten.filter(s => s.active !== false && s.standortId === currentWache);
        if (activeShifts.length > 0) {
            const defaultShiftName = activeShifts[0].name; 
            
            // FIX: Der erste Shift wird IMMER als temporär angelegt.
            const tempShiftId = 'temp-initial-' + Date.now(); 
            const shiftPath = getSchichtplanPath(currentWache, dayId, tempShiftId);
            const shiftRef = doc(db, ...shiftPath);
            
            await setDoc(shiftRef, {
                shiftName: defaultShiftName, 
                isTemporary: true, // Muss als temporär markiert werden
                personal1: null,
                personal2: null,
            });
            
            console.log(`Tag ${dayId} mit Standard-Shift (temporär) erstellt.`);
      } else {
            console.warn(`Keine Schichten für Wache ${currentWache} definiert.`);
        }
        
        // FIX: Setzt das Datum-Feld auf den nächsten Tag
        const nextDayValue = getNextDay(dateValue);
        newDayDateInput.value = nextDayValue;
        
        closeDatePopup(); // Popup schließen

        // FIX: Erzwingt nach der Erstellung einen sauberen Neuaufbau, um den OVD-Anzeigefehler zu vermeiden.
        if (dayUnsubscribe) dayUnsubscribe(); // Alte Listener stoppen
        daysArea.innerHTML = ''; // Fläche leeren
        loadingIndicator.classList.remove('hidden'); 
        listenForDays(); // Sauberen Listener neu starten


    } catch (error) {
        console.error("Fehler beim Erstellen des Tages:", error);
        alert("Fehler beim Erstellen des Tages: " + error.message);
    }
});

/**
 * Fügt eine temporäre, leere Schicht hinzu.
 */
window.addShiftToDay = async function(dayId, wacheId) {
    // Lade Schichten, falls noch nicht geladen oder undefined
    if (!allSchichten || allSchichten.length === 0) {
        await loadSchichten();
    }
    
    // Prüfe erneut, ob Schichten vorhanden sind
    if (!allSchichten || allSchichten.length === 0) {
        alert("Für diese Wache sind keine Schichten definiert. Bitte legen Sie zuerst Schichten in den Einstellungen an.");
        return;
    }
    
    // Filtere Schichten nach dem aktuellen Standort
    const activeShifts = allSchichten.filter(s => s.active !== false && s.standortId === wacheId);
    if (activeShifts.length === 0) {
        alert("Für diesen Standort sind keine aktiven Schichten definiert. Bitte legen Sie Schichten für diesen Standort in den Einstellungen an.");
        return;
    }
    
    const tempShiftId = 'temp-' + Date.now(); 
    const defaultShiftName = activeShifts[0].name; 

    try {
        const shiftPath = getSchichtplanPath(wacheId, dayId, tempShiftId);
        const shiftRef = doc(db, ...shiftPath);
        
        await setDoc(shiftRef, {
      shiftName: defaultShiftName,
            isTemporary: true, 
            personal1: null,
            personal2: null,
        });

        console.log(`Temporäre Schicht ${tempShiftId} zu Tag ${dayId} hinzugefügt.`);
        
    } catch (error) {
        console.error("Fehler beim Hinzufügen der Schicht:", error);
        alert("Fehler beim Hinzufügen der Schicht: " + error.message);
    }
}

/**
 * Verschiebt/benennt eine Schicht um (mit Batch-Write zur Vermeidung von Flackern).
 */
window.handleShiftSelection = async function(dayId, oldShiftId, newShiftName, wacheId) {
    if (oldShiftId === newShiftName) return; 

    if (newShiftName === 'TEMPORARY_SELECT') {
      return;
    }

    try {
        const batch = writeBatch(db); // Firestore Batch erstellen

        const oldPath = getSchichtplanPath(wacheId, dayId, oldShiftId);
        const newPath = getSchichtplanPath(wacheId, dayId, newShiftName);
        const oldRef = doc(db, ...oldPath);
        const newRef = doc(db, ...newPath);
        
        // 1. Prüfen, ob Zieldokument bereits existiert
        const newSnap = await getDoc(newRef);
        if (newSnap.exists()) {
            alert(`Die Schicht "${newShiftName}" existiert bereits an diesem Tag. Bitte wählen Sie eine andere Schicht oder löschen Sie die bestehende.`);
            return;
        }

        // 2. Daten des alten Shifts abrufen (wichtig für die Personal-Übernahme)
        const oldSnap = await getDoc(oldRef);
        const oldData = oldSnap.data() || { personal1: null, personal2: null };
        
        const isBereitschaftShift = isBereitschaft(newShiftName);
        const dataToSet = {
            shiftName: newShiftName,
            isTemporary: false,
            // Personal übertragen
            personal1: oldData.personal1, 
            personal2: isBereitschaftShift ? null : oldData.personal2, // Bei Bereitschaften Personal2 immer null
        };
        
        // 3. Batch-Operationen hinzufügen
        batch.set(newRef, dataToSet); // Neuen Shift mit Daten erstellen
        batch.delete(oldRef);       // Alten Shift löschen (inklusive temporärem Shift)

        // 4. Batch ausführen (gleichzeitiges Senden beider Operationen)
        await batch.commit(); 
        
        console.log(`Schicht erfolgreich von ${oldShiftId} nach ${newShiftName} verschoben (Batch-Write).`);

    } catch (error) {
        console.error("Fehler beim Verschieben/Umbenennen der Schicht:", error);
        alert("Fehler beim Verschieben/Umbenennen der Schicht: " + error.message);
    }
}

savePersonnelBtn.addEventListener("click", async () => {
    const dayId = personnelPopupForm.dataset.dayId;
    const shiftId = personnelPopupForm.dataset.shiftId;
    const slotIndex = personnelPopupForm.dataset.slotIndex;
    const wacheId = personnelPopupForm.dataset.wacheId;
    const isBereitschaft = personnelPopupForm.dataset.isBereitschaft === 'true';
    
    // Hole Element dynamisch
    const mitarbeiterSelect = document.getElementById("personnelMitarbeiterSelect");
    if (!mitarbeiterSelect) {
        alert("Fehler: Mitarbeiter-Auswahl nicht gefunden.");
      return;
    }

    const mitarbeiterId = mitarbeiterSelect.value;

    if (!mitarbeiterId) {
        alert("Bitte wählen Sie einen Mitarbeiter aus.");
      return;
    }
    
    // Wenn es eine Bereitschaft ist, verwende die spezielle Funktion
    if (isBereitschaft) {
        const typSelect = document.getElementById("bereitschaftsTypSelect");
        if (!typSelect || !typSelect.value) {
            alert("Bitte wählen Sie einen Bereitschafts-Typ aus.");
      return;
    }
        
        await saveBereitschaft(dayId, mitarbeiterId, typSelect.value);
        closePersonnelPopup();
      return;
    }

    // Normale Schicht-Logik
    // Hole weitere Elemente dynamisch
    const colorInputEl = document.getElementById("personnelColor");
    const qualGroupEl = document.getElementById("qualificationGroup");
    
    if (!colorInputEl || !qualGroupEl) {
        alert("Fehler: Formular-Elemente nicht gefunden.");
      return;
    }

    const farbe = colorInputEl.value;
    const selectedQuals = Array.from(qualGroupEl.querySelectorAll('input[name="qual"]:checked')).map(el => el.value);
    
    // Hole Mitarbeiter-Daten aus der Datenbank
    const mitarbeiter = allMitarbeiter.find(m => m.id === mitarbeiterId);
    if (!mitarbeiter) {
        alert("Mitarbeiter nicht gefunden. Bitte laden Sie die Seite neu.");
        return;
    }
    
    // 🔥 DOPPELBELEGUNGS-PRÜFUNG
    // dayId, wacheId, shiftId, slotIndex sind bereits oben deklariert
    const isDoubleBooked = await checkDoubleBooking(mitarbeiterId, dayId, wacheId, shiftId, slotIndex);
    if (isDoubleBooked) {
        const confirmMessage = `⚠️ WARNUNG: Dieser Mitarbeiter ist bereits an diesem Tag (${dayId}) verplant!\n\nMöchten Sie trotzdem fortfahren?`;
        if (!confirm(confirmMessage)) {
            return; // Benutzer hat abgebrochen
        }
    }
    
    closePersonnelPopup();

    // Prüfe, ob es eine Bereitschafts-Schicht ist
    // shiftId ist bereits oben deklariert
    const isBereitschaftShift = isBereitschaft(shiftId);
    
    // Bei Bereitschaften: Farbe immer blau
    const finalFarbe = isBereitschaftShift ? '#3b82f6' : farbe;

    const personalData = {
        mitarbeiterId: mitarbeiterId,
        name: `${mitarbeiter.vorname} ${mitarbeiter.nachname}`,
        qualifikationen: selectedQuals.length > 0 ? selectedQuals : (mitarbeiter.qualifikation || []),
        farbe: finalFarbe
    };

    const updateField = `personal${slotIndex}`;
    
    // Bei Bereitschaften: Personal2 immer auf null setzen
    const updateData = {
        [updateField]: personalData
    };
    
    if (isBereitschaftShift && slotIndex === 1) {
        updateData.personal2 = null; // Stelle sicher, dass Personal2 leer ist
    }

    try {
        const shiftPath = getSchichtplanPath(wacheId, dayId, shiftId);
        const shiftRef = doc(db, ...shiftPath);
        
        await setDoc(shiftRef, {
            [updateField]: personalData
        }, { merge: true });

        console.log(`Personal in Slot ${slotIndex} von Schicht ${shiftId} für Wache ${wacheId} gespeichert.`);
    } catch (error) {
        console.error("Fehler beim Speichern des Personals:", error);
        alert("Fehler beim Speichern des Personals: " + error.message);
    }
});


// --- RENDERING & LISTENERS ---

wacheSelect.addEventListener("change", (e) => {
    currentWache = e.target.value;
    isOVD = false; // OVD wird jetzt über separaten Button gesteuert

    initialMessage.classList.add('hidden');
    addDayBtn.classList.add('hidden');
    daysArea.innerHTML = ''; 
    ovdMessage.classList.add('hidden');
    loadingIndicator.classList.remove('hidden');
    
    // Aktiviere die Gelb-Liste nur, wenn eine Wache ausgewählt ist (nicht "default")
    if (yellowListArea) yellowListArea.innerHTML = ''; 
    if (showYellowListBtn) showYellowListBtn.classList.remove('hidden'); // Der Button ist immer sichtbar, aber die Liste wird erst auf Klick geladen

    if (currentWache === "default") {
        initialMessage.classList.remove('hidden');
        loadingIndicator.classList.add('hidden');
        if (dayUnsubscribe) dayUnsubscribe(); 
        if (showYellowListBtn) showYellowListBtn.classList.add('hidden'); // Bei Default verstecken
        return;
    }

    // Normale Standort-Ansicht
    addDayBtn.classList.remove('hidden');
    listenForDays();
});

addDayBtn.addEventListener("click", openDatePopup);

/**
 * Allgemeine Hilfsfunktion zum robusten Parsen von DD.MM.YYYY
 */
const parseGermanDateRobust = (dayId) => {
    if (!dayId || typeof dayId !== 'string') {
        return 0;
    }
    const parts = dayId.split('.'); 
    if (parts.length === 3 && parts[2].length === 4) {
        // new Date(YYYY, MM - 1, DD)
        const date = new Date(parts[2], parts[1] - 1, parts[0]);
        // Prüfen, ob das Datum gültig ist, bevor getTime verwendet wird
        return isNaN(date.getTime()) ? 0 : date.getTime(); 
    }
    return 0;
};


function listenForDays() {
    if (dayUnsubscribe) {
        dayUnsubscribe(); 
    }
    
    daysArea.innerHTML = '';
    
    if (isOVD) {
        listenForOVDSummary();
        return;
    }

    // Normaler Wachen-Modus
    const daysPath = getSchichtplanPath(currentWache);
    const daysColRef = collection(db, ...daysPath, "tage");
    // Sortierung auf den Zeitstempel umgestellt
    const q = query(daysColRef, orderBy("timestamp", "asc")); 

    dayUnsubscribe = onSnapshot(q, (snapshot) => {
        loadingIndicator.classList.add('hidden');
        
        if (snapshot.empty) {
            daysArea.innerHTML = '<div class="info-card">Keine Schichten für diese Wache vorhanden. Erstelle einen neuen Tag.</div>';
            return;
        }
        
        snapshot.docChanges().forEach(change => {
            const dayData = change.doc.data();
            const dayId = change.doc.id; 

            if (change.type === "added" || change.type === "modified") {
                renderDayCard(dayId, dayData);
            }
            if (change.type === "removed") {
                document.getElementById(`day-${dayId}-${currentWache}`)?.remove(); 
            }
        });
        
        // Stellt die endgültige Sortierung der Cards nach dem Datum sicher (Fallback)
        const sortedDayCards = Array.from(daysArea.children)
            .sort((a, b) => {
                const idA = a.id?.split('-')[1]; // dayId
                const idB = b.id?.split('-')[1]; // dayId
                
                if (!idA || !idB) return 0;
                
                const dateA = parseGermanDateRobust(idA);
                const dateB = parseGermanDateRobust(idB);
                return dateA - dateB;
            });
        
        // Fügt die sortierten Karten wieder ein
        daysArea.innerHTML = '';
        sortedDayCards.forEach(card => daysArea.appendChild(card));

    }, (error) => {
        console.error("Fehler beim Laden der Tage:", error);
        daysArea.innerHTML = `<div class="info-card error">Fehler beim Laden: ${error.message}</div>`;
    });
}


/**
 * Rendert eine einzelne Tages-Card und startet den Schicht-Listener.
 */
function renderDayCard(dayId, dayData, wacheId = null) {
    const actualWacheId = wacheId || currentWache;
    let dayCard = document.getElementById(`day-${dayId}-${actualWacheId}`);
    
    if (!dayCard) {
        dayCard = document.createElement("div");
        dayCard.className = "day-card";
        dayCard.id = `day-${dayId}-${actualWacheId}`;
        
        // Hole den Standort-Namen aus allStandorte (mit Original-Groß-/Kleinschreibung)
        let wacheName = '';
        if (wacheId) {
            const standort = allStandorte.find(s => s.id === wacheId);
            wacheName = standort ? standort.name : wacheId;
        }
        const wacheInfo = wacheId ? `<span class="wache-info">(${wacheName})</span>` : '';
        
        const deleteDayBtn = `<button class="control-btn delete-day-btn" onclick="deleteDay('${dayId}', '${actualWacheId}')" title="Tag löschen">${getTrashIcon('white')}</button>`;
        
        const addShiftBtn = !isOVD ? `<button class="control-btn add-shift-btn" onclick="addShiftToDay('${dayId}', '${actualWacheId}')" title="Schicht hinzufügen">+ Schicht</button>` : '';


        dayCard.innerHTML = `
            <div class="day-header">
                <span class="day-date">${dayData.datum} ${wacheInfo}</span>
                <div class="day-controls">
                    ${addShiftBtn}
                    ${deleteDayBtn} 
                </div>
            </div>
            <div class="day-content" id="shift-list-${dayId}-${actualWacheId}">
                <!-- Schichten werden hier dynamisch geladen -->
            </div>
        `;
        // Temporäre Platzierung, die später in listenForDays sortiert wird
        if (!document.getElementById(`day-${dayId}-${actualWacheId}`)) {
             daysArea.appendChild(dayCard);
        }
    }
    
    listenForShifts(dayId, document.getElementById(`shift-list-${dayId}-${actualWacheId}`), actualWacheId);
}


function listenForShifts(dayId, containerElement, wacheId) {
    if (!containerElement) {
        console.error(`Container-Element für Tag ${dayId} nicht gefunden`);
        return;
    }
    
    const shiftsPath = getSchichtplanPath(wacheId, dayId);
    const shiftsColRef = collection(db, ...shiftsPath, "schichten");
    const q = query(shiftsColRef); 

    onSnapshot(q, (snapshot) => {
        if (!containerElement) return; // Sicherheitsprüfung
        containerElement.innerHTML = ''; 
        
        // Sortiere Schichten: Bereitschaften zuerst, dann alphabetisch
        const shiftsArray = [];
        snapshot.forEach(docSnap => {
            shiftsArray.push({
            id: docSnap.id,
                data: docSnap.data()
          });
        });
        
        shiftsArray.sort((a, b) => {
            const aIsBereitschaft = isBereitschaft(a.id);
            const bIsBereitschaft = isBereitschaft(b.id);
            
            // Bereitschaften zuerst
            if (aIsBereitschaft && !bIsBereitschaft) return -1;
            if (!aIsBereitschaft && bIsBereitschaft) return 1;
            
            // Dann alphabetisch
            return a.id.localeCompare(b.id);
        });
        
        shiftsArray.forEach(shift => {
            const shiftId = shift.id;
            const shiftData = shift.data;
            const isBereitschaftShift = isBereitschaft(shiftId);
            
            // In OVD-Ansicht: Bereitschaften ausschließen und nur unbesetzte Schichten zeigen
            if (isOVD) {
                if (isBereitschaftShift) {
                    return; // Bereitschaften nicht in OVD anzeigen
                }
                const isFullyManned = !!shiftData.personal1 && !!shiftData.personal2;
                if (isFullyManned) {
                    return; // Nur unbesetzte Schichten in OVD
                }
            }
            
            // Normale Schichten (keine Bereitschaften) immer rendern
            // Bereitschaften werden jetzt separat in der Bereitschaften-Sektion angezeigt, nicht mehr als Schichten
            if (!isBereitschaftShift) {
                renderShiftRow(dayId, shiftId, shiftData, containerElement, wacheId);
            }
        });
        
        const dayCard = document.getElementById(`day-${dayId}-${wacheId}`);
        if (dayCard && isOVD && containerElement.innerHTML === '') {
             dayCard.remove(); 
        }

    }, (error) => {
        console.error(`Fehler beim Laden der Schichten für Tag ${dayId}:`, error);
        containerElement.innerHTML = `<div style="padding: 15px; color: red;">Fehler beim Laden der Schichten.</div>`;
    });
}


/**
 * Rendert eine einzelne Schicht-Zeile mit Personal-Slots.
 */
function renderShiftRow(dayId, shiftId, data, containerElement, wacheId) {
    const isBereitschaftShift = isBereitschaft(shiftId);
    const isSlot1Manned = !!data.personal1;
    const isSlot2Manned = !!data.personal2;
    
    // Status-Klassen für Schichten (rot/grün)
    let mannedStatusClass = 'unmanned';
    if (isSlot1Manned && isSlot2Manned) {
        mannedStatusClass = 'fully-manned'; 
    } else if (isSlot1Manned || isSlot2Manned) {
        mannedStatusClass = 'partially-manned';
    }

    const row = document.createElement('div');
    row.id = `shift-${dayId}-${shiftId}-${wacheId}`; 
    row.className = `shift-row ${mannedStatusClass}`;
    
    // Verwende die Schichten aus Firestore für den aktuellen Standort (mit Fallback)
    const shiftsToUse = (allSchichten && allSchichten.length > 0) 
        ? allSchichten.filter(s => s.active !== false && s.standortId === wacheId).map(s => s.name)
        : [];
    
    let shiftOptions;
    // Prüft, ob es sich um einen temporären Shift handelt (beginnt mit 'temp-')
    const isTemporary = shiftId.startsWith('temp-');

    if (isTemporary) {
        shiftOptions = `<option value="TEMPORARY_SELECT" selected>--- Schicht auswählen ---</option>` + shiftsToUse.map(s => 
            `<option value="${s}">${s}</option>`
        ).join('');
    } else {
        // Für benannte Shifts: Nutze die shiftId (die Dokument-ID) für die Auswahl
        shiftOptions = shiftsToUse.map(s => {
            const isSelected = s === shiftId ? 'selected' : '';
            return `<option value="${s}" ${isSelected}>${s}</option>`;
        }).join('');
    }
    
    // FIX: Dropdown deaktivieren nur, wenn es OVD ist.
    const selectDisabled = isOVD ? 'disabled' : ''; 
    
    const deleteShiftBtn = `<button class="control-btn delete-shift-btn" onclick="deleteShift('${dayId}', '${shiftId}', '${wacheId}')" title="Schicht löschen">${getTrashIcon('black')}</button>`;

    // Bei Bereitschaften nur einen Slot anzeigen (Personal1)
    const personnelSlots = isBereitschaftShift 
        ? renderPersonnelSlot(dayId, shiftId, 1, data.personal1, wacheId, true)
        : `${renderPersonnelSlot(dayId, shiftId, 1, data.personal1, wacheId)}${renderPersonnelSlot(dayId, shiftId, 2, data.personal2, wacheId)}`;

    row.innerHTML = `
        <select class="shift-select" ${selectDisabled} data-day-id="${dayId}" data-old-shift-id="${shiftId}" data-wache-id="${wacheId}">
            ${shiftOptions}
        </select>
        <div class="personnel-slot">
            ${personnelSlots}
        </div>
        ${deleteShiftBtn}
    `;
    
    containerElement.appendChild(row);
    
    const selectElement = row.querySelector('.shift-select');
    // Listener für ALLE NICHT-OVD Schichten anfügen (die umbenannt werden dürfen).
    if (selectElement && !isOVD) {
        selectElement.addEventListener('change', (e) => {
            const newShiftName = e.target.value;
            handleShiftSelection(dayId, shiftId, newShiftName, wacheId);
        });
    }
    
    // Event-Listener für Bereitschafts-Personal nach dem Rendern hinzufügen
    if (isBereitschaftShift && data.personal1) {
        const personnelElement = row.querySelector('.personnel-label.bereitschaft-personnel');
        if (personnelElement && data.personal1.mitarbeiterId) {
            personnelElement.addEventListener('contextmenu', (e) => {
                e.preventDefault();
                e.stopPropagation();
                showBereitschaftAssignmentMenu(e, data.personal1.mitarbeiterId, data.personal1.name, dayId);
                return false;
            });
        }
    }
}

/**
 * Rendert einen Personal-Slot (Label).
 * @param {boolean} isBereitschaftParam - Ob dies eine Bereitschafts-Schicht ist (optional, wird sonst aus shiftId ermittelt)
 */
function renderPersonnelSlot(dayId, shiftId, slotIndex, personalData, wacheId, isBereitschaftParam = false) {
    const dataWacheId = wacheId || currentWache;
    const isTemporary = shiftId.startsWith('temp-');
    const isBereitschaftShift = isBereitschaftParam || isBereitschaft(shiftId);

    if (personalData) {
        const quals = personalData.qualifikationen.join('/');
        const text = `${personalData.name} (${quals})`;
        // Bereitschaften haben immer blauen Hintergrund
        const color = isBereitschaftShift ? '#3b82f6' : (personalData.farbe || '#ffffff');
        
        const encodedData = encodeURIComponent(JSON.stringify(personalData));
        
        if (isTemporary) {
             return `<div class="personnel-label unassigned">Schicht noch nicht ausgewählt</div>`;
        }

        // Rechtsklick/Long-Press für Datenblatt oder Bereitschafts-Zuweisung
        let contextMenuHandler = '';
        let touchHandlers = '';
        if (personalData.mitarbeiterId) {
            if (isBereitschaftShift) {
                const uniqueId = `bereitschaft-${dayId}-${shiftId}-${slotIndex}-${personalData.mitarbeiterId}`;
                // Kein inline Handler - wird vom globalen Event-Delegation-Listener behandelt
                touchHandlers = `data-bereitschaft-id="${uniqueId}" data-mitarbeiter-id="${personalData.mitarbeiterId}" data-mitarbeiter-name="${personalData.name}" data-day-id="${dayId}"`;
            } else {
                contextMenuHandler = `oncontextmenu="event.preventDefault(); event.stopPropagation(); showMitarbeiterDatenblatt('${personalData.mitarbeiterId}'); return false;"`;
            }
        }
        
        // Bestimme Icon-Farbe basierend auf Hintergrundfarbe
        const iconColor = getIconColorForBackground(color);
        const trashIcon = getTrashIcon(iconColor);
        
        // Linksklick-Handler: funktioniert für alle (inkl. Bereitschaften zum Bearbeiten)
        // Bei Rechtsklick wird der onclick nicht ausgeführt, da oncontextmenu zuerst kommt
        const clickHandler = `onclick="if(event.button === 0 || !event.button) { openPersonnelPopup('${dayId}', '${shiftId}', ${slotIndex}, JSON.parse(decodeURIComponent('${encodedData}')), '${dataWacheId}'); }"`;
        
        return `
            <div 
                class="personnel-label assigned ${isBereitschaftShift ? 'bereitschaft-personnel' : ''}" 
                style="background-color: ${color} !important; cursor: pointer;" 
                title="${isBereitschaftShift ? 'Linksklick: Bearbeiten | Rechtsklick/Long-Press: Mitarbeiter einer offenen Schicht zuweisen' : 'Linksklick: Bearbeiten | Rechtsklick: Datenblatt anzeigen'}"
                ${clickHandler}
                ${contextMenuHandler}
                ${touchHandlers}
            >
                ${text} 
                <span class="remove-btn" onclick="event.stopPropagation(); removePersonnel('${dayId}', '${shiftId}', ${slotIndex}, '${dataWacheId}');" title="Personal entfernen">${trashIcon}</span>
            </div>
        `;
    } else {
         if (isTemporary) {
            return `<div class="personnel-label unassigned">Bitte Schicht auswählen</div>`;
        }

        const labelText = isBereitschaftShift ? 'Bereitschaft eintragen' : `Personal ${slotIndex} eintragen`;

        return `
            <div 
                class="personnel-label unassigned" 
                onclick="openPersonnelPopup('${dayId}', '${shiftId}', ${slotIndex}, null, '${dataWacheId}')"
            >
                ${labelText}
            </div>
        `;
    }
}


function listenForOVDSummary() {
    // Stoppe alle vorherigen OVD-Listener, um Doppelungen zu vermeiden
    ovdUnsubscribes.forEach(unsub => {
        if (unsub) unsub();
    });
    ovdUnsubscribes = [];
    
    // Verwende jetzt die Standorte aus Firestore statt vordefinierte Wachen
    const wachenToQuery = allStandorte.filter(s => s.active !== false).map(s => s.id);
    
    let activeWacheListeners = 0;
    daysArea.innerHTML = ''; 

    const dayDocsMap = new Map(); 

    wachenToQuery.forEach(wache => {
        activeWacheListeners++;
        const daysPath = getSchichtplanPath(wache);
        const daysColRef = collection(db, ...daysPath, "tage");
        // Sortierung auf den Zeitstempel umgestellt
        const q = query(daysColRef, orderBy("timestamp", "asc")); 

        const unsubscribe = onSnapshot(q, (snapshot) => {
            activeWacheListeners--;
            
            snapshot.docChanges().forEach(change => {
                const dayId = change.doc.id;
                const dayData = change.doc.data();
                
                // Füge den Zeitstempel hinzu, um ihn später sortieren zu können
                const timestamp = dayData.timestamp ? dayData.timestamp.toMillis() : null;
                const sortKey = parseGermanDateRobust(dayId); 

                if (change.type !== "removed") {
                    dayDocsMap.set(`${wache}-${dayId}`, { dayId, dayData, wache, timestamp, sortKey });
                } else {
                     dayDocsMap.delete(`${wache}-${dayId}`);
                }
            });
            
            if (activeWacheListeners === 0 || snapshot.docChanges().length > 0) {
                renderOVDCards(dayDocsMap);
                loadingIndicator.classList.add('hidden');
            }

        }, (error) => {
            console.error(`Fehler beim Laden der OVD-Tage für Wache ${wache}:`, error);
        });
        
        // Speichere die Unsubscribe-Funktion
        ovdUnsubscribes.push(unsubscribe);
    });
}


function renderOVDCards(dayDocsMap) {
    daysArea.innerHTML = '';
    
    const sortedDays = Array.from(dayDocsMap.values()).sort((a, b) => {
        // Sortiert ausschließlich nach dem sortKey, der robust aus dem Datumsstring TT.MM.JJJJ gewonnen wird
        return a.sortKey - b.sortKey; // Sortiert aufsteigend (ältestes Datum zuerst)
    });

    if (sortedDays.length === 0) {
        daysArea.innerHTML = '<div class="info-card fully-manned">Keine offenen Schichten im System gefunden.</div>';
      return;
    }

    sortedDays.forEach(({ dayId, dayData, wache }) => {
        renderDayCard(dayId, dayData, wache);
    });
}


// ----------------------------------------------------------------------
// FUNKTIONEN FÜR GELB MARKIERTE LISTE (FEHLTE IN IHRER VERSION)
// ----------------------------------------------------------------------

/**
 * Aggregiert alle Personal-Einträge mit der gelben Markierung über alle Wachen.
 */
async function showYellowPersonnelList() {
    if (!yellowListArea) return; // Sicherheitscheck
    yellowListArea.innerHTML = '<div class="info-card">Lade gelb markiertes Personal...</div>';
    
    const wachenToQuery = Object.keys(WACHEN_SCHICHTEN).filter(w => w !== "OVD" && w !== "default");
    // Map: Name -> { name, qualifikationen, farbe, einsaetze: [...] }
    const yellowPersonnel = new Map(); 
    
    if (showYellowListBtn) showYellowListBtn.disabled = true;

    for (const wache of wachenToQuery) {
        const daysPath = getSchichtplanPath(wache);
        const daysColRef = collection(db, ...daysPath, "tage");
        const daySnap = await getDocs(daysColRef); 
        
        for (const dayDoc of daySnap.docs) {
            const dayId = dayDoc.id;
            const dayData = dayDoc.data();
            
            const shiftsPath = getSchichtplanPath(wache, dayId);
            const shiftsColRef = collection(db, ...shiftsPath, "schichten");
            const shiftSnap = await getDocs(shiftsColRef);

            shiftSnap.forEach(shiftDoc => {
                const shiftData = shiftDoc.data();
                const shiftId = shiftDoc.id;
                
                for (let i = 1; i <= 2; i++) {
                    const personal = shiftData[`personal${i}`];
                    
                    // Verwendet die oben definierte Konstante
                    if (personal && personal.farbe === YELLOW_HIGHLIGHT_COLOR) { 
                        const key = personal.name.trim();
                        
                        if (!yellowPersonnel.has(key)) {
                            yellowPersonnel.set(key, { 
                                name: key, 
                                qualifikationen: personal.qualifikationen,
                                farbe: personal.farbe,
                                einsaetze: []
                            });
                        }
                        yellowPersonnel.get(key).einsaetze.push({
                            wache: wache.replace('RW_', 'RW ').replace('KTW_', 'KTW '),
                            tag: dayData.datum,
                            schicht: shiftId
                        });
                    }
                }
            });
        }
    }
    
    renderYellowPersonnelList(yellowPersonnel);
    if (showYellowListBtn) showYellowListBtn.disabled = false;
}

/**
 * Rendert die aggregierte Liste des gelb markierten Personals.
 */
function renderYellowPersonnelList(personnelMap) {
    if (!yellowListArea) return; 

    if (personnelMap.size === 0) {
        yellowListArea.innerHTML = '<div class="info-card">Kein Personal gelb markiert gefunden.</div>';
        return;
    }
    
    // Sortiert nach Name
    const sortedPersonnel = Array.from(personnelMap.values()).sort((a, b) => a.name.localeCompare(b.name));
    
    let html = '<h2>Gelb markiertes Personal (Springer)</h2><ul class="yellow-list" style="list-style: none; padding: 0;">';
    
    sortedPersonnel.forEach(p => {
        // Sortiert Einsätze chronologisch für bessere Übersicht
        const sortedEinsaetze = p.einsaetze.sort((a, b) => {
            const dateA = parseGermanDateRobust(a.tag);
            const dateB = parseGermanDateRobust(b.tag);
            return dateA - dateB;
        });

        const einsaetzeHtml = sortedEinsaetze.map(e => `
            <span style="display: inline-block; background: rgba(0,0,0,0.05); padding: 2px 6px; margin: 3px; border-radius: 3px; font-size: 0.9em;">
                ${e.wache} am <strong>${e.tag}</strong> (${e.schicht})
            </span>
        `).join('');

        html += `
            <li class="yellow-person-item" style="background-color: ${p.farbe}; border: 1px solid #ccc; padding: 15px; margin-bottom: 10px; border-radius: 5px;">
                <strong>${p.name}</strong> (${p.qualifikationen.join('/')})
                <div style="margin-top: 10px; border-top: 1px solid rgba(0,0,0,0.1); padding-top: 10px; font-size: 0.95em;">
                    ${einsaetzeHtml || 'Keine Einsätze gefunden.'}
                </div>
            </li>
        `;
    });
    
    html += '</ul>';
    yellowListArea.innerHTML = html;
}


// initializeApp wird weiter unten definiert (mit allen neuen Funktionen)

// Popup-Funktionen global verfügbar machen
window.closeDatePopup = closeDatePopup;
window.closePersonnelPopup = closePersonnelPopup;
window.showYellowPersonnelList = showYellowPersonnelList; // Muss global sein

// ============================================================================
// 🔥 NEUE FUNKTIONALITÄT: Einstellungen, Mitarbeiterdatenbank, OVD, etc.
// ============================================================================

// DOM-Elemente für Einstellungen
const settingsBtn = document.getElementById("settingsBtn");
const settingsPopupOverlay = document.getElementById("settingsPopupOverlay");
const settingsPopupForm = document.getElementById("settingsPopupForm");
const calendarBtn = document.getElementById("calendarBtn");
const calendarPopupOverlay = document.getElementById("calendarPopupOverlay");
const calendarPopupForm = document.getElementById("calendarPopupForm");

// DOM-Elemente für Standorte
const addStandortBtn = document.getElementById("addStandortBtn");
const standorteList = document.getElementById("standorteList");
const standortFormOverlay = document.getElementById("standortFormOverlay");
  const standortForm = document.getElementById("standortForm");
  const standortNameInput = document.getElementById("standortName");
  const saveStandortBtn = document.getElementById("saveStandortBtn");

// DOM-Elemente für Schichten
const addSchichtBtn = document.getElementById("addSchichtBtn");
const schichtenList = document.getElementById("schichtenList");
const schichtFormOverlay = document.getElementById("schichtFormOverlay");
  const schichtForm = document.getElementById("schichtForm");
  const schichtNameInput = document.getElementById("schichtName");
  const schichtStandortSelect = document.getElementById("schichtStandort");
  const saveSchichtBtn = document.getElementById("saveSchichtBtn");

// DOM-Elemente für Mitarbeiter
const addMitarbeiterBtn = document.getElementById("addMitarbeiterBtn");
const mitarbeiterList = document.getElementById("mitarbeiterList");
const mitarbeiterFormOverlay = document.getElementById("mitarbeiterFormOverlay");
  const mitarbeiterForm = document.getElementById("mitarbeiterForm");
  const mitarbeiterVornameInput = document.getElementById("mitarbeiterVorname");
  const mitarbeiterNachnameInput = document.getElementById("mitarbeiterNachname");
const mitarbeiterQualifikationenGroup = document.getElementById("mitarbeiterQualifikationen");
  const mitarbeiterFuehrerscheinInput = document.getElementById("mitarbeiterFuehrerschein");
  const mitarbeiterTelefonInput = document.getElementById("mitarbeiterTelefon");
  const saveMitarbeiterBtn = document.getElementById("saveMitarbeiterBtn");

// Globale Variablen
let currentEditingStandortId = null;
let currentEditingSchichtId = null;
let currentEditingMitarbeiterId = null;
let allStandorte = [];
let allSchichten = [];
let allMitarbeiter = [];
let allBereitschaftsTypen = [];

/**
 * 🔥 MULTI-TENANT: Firestore-Pfad für Standorte (Collection)
 * Pfad: kunden/{companyId}/schichtplanStandorte/{standortId}
 */
function getStandortePath() {
    if (!userAuthData || !userAuthData.companyId) {
        throw new Error("Keine Auth-Daten verfügbar");
    }
    return ["kunden", userAuthData.companyId, "schichtplanStandorte"];
}

/**
 * 🔥 MULTI-TENANT: Firestore-Pfad für Schichten (Collection)
 * Pfad: kunden/{companyId}/schichtplanSchichten/{schichtId}
 */
function getSchichtenPath() {
    if (!userAuthData || !userAuthData.companyId) {
        throw new Error("Keine Auth-Daten verfügbar");
    }
    return ["kunden", userAuthData.companyId, "schichtplanSchichten"];
}

/**
 * 🔥 MULTI-TENANT: Firestore-Pfad für Mitarbeiter (Collection)
 * Pfad: kunden/{companyId}/schichtplanMitarbeiter/{mitarbeiterId}
 */
function getMitarbeiterPath() {
    if (!userAuthData || !userAuthData.companyId) {
        throw new Error("Keine Auth-Daten verfügbar");
    }
    return ["kunden", userAuthData.companyId, "schichtplanMitarbeiter"];
}

/**
 * Lädt alle Standorte aus Firestore
 */
async function loadStandorte() {
    try {
        const path = getStandortePath();
        const standorteRef = collection(db, ...path);
        const q = query(standorteRef, orderBy("order", "asc"));
        const snapshot = await getDocs(q);
        
        allStandorte = [];
        snapshot.forEach(doc => {
            allStandorte.push({
                id: doc.id,
                ...doc.data()
            });
        });
        
        renderStandorteList();
        updateWacheSelect();
        return allStandorte;
    } catch (error) {
        console.error("Fehler beim Laden der Standorte:", error);
        return [];
    }
}

/**
 * Lädt alle Schichten aus Firestore
 */
async function loadSchichten() {
    try {
        const path = getSchichtenPath();
        const schichtenRef = collection(db, ...path);
        const q = query(schichtenRef, orderBy("order", "asc"));
        const snapshot = await getDocs(q);
        
        allSchichten = [];
        snapshot.forEach(doc => {
            allSchichten.push({
                id: doc.id,
                ...doc.data()
            });
        });
        
        renderSchichtenList();
        return allSchichten;
    } catch (error) {
        console.error("Fehler beim Laden der Schichten:", error);
        return [];
    }
}

/**
 * Lädt alle Mitarbeiter aus Firestore
 */
async function loadMitarbeiter() {
    try {
        const path = getMitarbeiterPath();
        const mitarbeiterRef = collection(db, ...path);
        const q = query(mitarbeiterRef, orderBy("nachname", "asc"));
        const snapshot = await getDocs(q);
        
        allMitarbeiter = [];
        snapshot.forEach(doc => {
            allMitarbeiter.push({
                id: doc.id,
                ...doc.data()
            });
        });
        
        renderMitarbeiterList();
        return allMitarbeiter;
    } catch (error) {
        console.error("Fehler beim Laden der Mitarbeiter:", error);
        return [];
    }
}

/**
 * Rendert die Standorte-Liste
 */
function renderStandorteList() {
    if (!standorteList) return;
    
    if (allStandorte.length === 0) {
        standorteList.innerHTML = '<p style="color: #666;">Keine Standorte vorhanden.</p>';
        return;
    }
    
    standorteList.innerHTML = allStandorte
        .filter(s => s.active !== false)
        .map(standort => `
            <div class="settings-item">
                <span>${standort.name}</span>
                <div class="settings-item-actions">
                    <button class="btn-small" onclick="editStandort('${standort.id}')">Bearbeiten</button>
                    <button class="btn-small btn-danger" onclick="deleteStandort('${standort.id}')">Löschen</button>
                </div>
            </div>
        `).join('');
}

/**
 * Rendert die Schichten-Liste
 */
function renderSchichtenList() {
    if (!schichtenList) return;
    
    if (allSchichten.length === 0) {
        schichtenList.innerHTML = '<p style="color: #666;">Keine Schichten vorhanden.</p>';
        return;
      }

    schichtenList.innerHTML = allSchichten
        .filter(s => s.active !== false)
        .map(schicht => {
            const standort = allStandorte.find(s => s.id === schicht.standortId);
            const standortName = standort ? standort.name : 'Kein Standort';
            return `
            <div class="settings-item">
                <span><strong>${schicht.name}</strong><br><small>Standort: ${standortName}</small></span>
                <div class="settings-item-actions">
                    <button class="btn-small" onclick="editSchicht('${schicht.id}')">Bearbeiten</button>
                    <button class="btn-small btn-danger" onclick="deleteSchicht('${schicht.id}')">Löschen</button>
                </div>
            </div>
        `;
        }).join('');
}

/**
 * Rendert die Mitarbeiter-Liste
 */
function renderMitarbeiterList() {
    if (!mitarbeiterList) return;
    
    if (allMitarbeiter.length === 0) {
        mitarbeiterList.innerHTML = '<p style="color: #666;">Keine Mitarbeiter vorhanden.</p>';
        return;
    }
    
    mitarbeiterList.innerHTML = allMitarbeiter
        .filter(m => m.active !== false)
        .map(mitarbeiter => `
            <div class="settings-item">
                <span><strong>${mitarbeiter.vorname} ${mitarbeiter.nachname}</strong><br>
                <small>Qualifikation: ${mitarbeiter.qualifikation?.join(', ') || 'Keine'}</small><br>
                <small>Führerschein: ${mitarbeiter.fuehrerschein || 'Keine'}</small><br>
                <small>Tel: ${mitarbeiter.telefonnummer || 'Keine'}</small></span>
                <div class="settings-item-actions">
                    <button class="btn-small" onclick="editMitarbeiter('${mitarbeiter.id}')">Bearbeiten</button>
                    <button class="btn-small btn-danger" onclick="deleteMitarbeiter('${mitarbeiter.id}')">Löschen</button>
                </div>
            </div>
        `).join('');
}

/**
 * Aktualisiert das Wache-Select mit den geladenen Standorten
 */
function updateWacheSelect() {
    if (!wacheSelect) return;
    
    // Entferne alle Optionen außer "default"
    const defaultOption = wacheSelect.querySelector('option[value="default"]');
    
    wacheSelect.innerHTML = '';
    if (defaultOption) wacheSelect.appendChild(defaultOption);
    
    // Füge Standorte hinzu
    allStandorte
        .filter(s => s.active !== false)
        .forEach(standort => {
            const option = document.createElement('option');
            option.value = standort.id;
            option.textContent = standort.name;
            wacheSelect.appendChild(option);
        });
}

// Event Listeners für Einstellungen
if (settingsBtn) {
    settingsBtn.addEventListener('click', () => {
        settingsPopupOverlay.style.display = 'block';
        settingsPopupForm.style.display = 'block';
        loadStandorte();
        loadSchichten();
        loadMitarbeiter();
        loadBereitschaftsTypen(); // Lade auch Bereitschafts-Typen
    });
}

// Event Listener für "Offene Schichten" Button
if (offeneSchichtenBtn) {
    offeneSchichtenBtn.addEventListener('click', () => {
        // Setze OVD-Modus
        currentWache = "OVD";
        isOVD = true;
        wacheSelect.value = "default";
        
        // Verstecke "Tag erstellen" Button
        if (addDayBtn) addDayBtn.classList.add('hidden');
        
        // Zeige OVD-Message
        if (ovdMessage) ovdMessage.classList.remove('hidden');
        if (initialMessage) initialMessage.classList.add('hidden');
        
        // Lade OVD-Übersicht
        daysArea.innerHTML = '';
        loadingIndicator.classList.remove('hidden');
        listenForOVDSummary();
    });
}

// Event Listener für "Bereitschaften" Button
if (bereitschaftenBtn) {
    bereitschaftenBtn.addEventListener('click', () => {
        openBereitschaftenView();
    });
}

if (settingsPopupOverlay) {
    settingsPopupOverlay.addEventListener('click', (e) => {
        if (e.target === settingsPopupOverlay) {
            closeSettingsPopup();
      }
    });
  }

// Tab-Wechsel in Einstellungen
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
        
        btn.classList.add('active');
        const tabId = btn.dataset.tab;
        document.getElementById(`tab-${tabId}`).classList.add('active');
        
        // Lade Daten für den aktiven Tab
        if (tabId === 'standorte') {
            loadStandorte();
        } else if (tabId === 'schichten') {
            loadSchichten();
        } else if (tabId === 'mitarbeiter') {
            loadMitarbeiter();
        } else if (tabId === 'bereitschaften') {
            loadBereitschaftsTypen();
        }
    });
});

// Standort-Funktionen
if (addStandortBtn) {
    addStandortBtn.addEventListener('click', () => {
        currentEditingStandortId = null;
        document.getElementById('standortFormTitle').textContent = 'Standort hinzufügen';
        standortNameInput.value = '';
        standortFormOverlay.style.display = 'block';
        standortForm.style.display = 'block';
    });
}

if (saveStandortBtn) {
    saveStandortBtn.addEventListener('click', async () => {
        const name = standortNameInput.value.trim();
        if (!name) {
            alert('Bitte geben Sie einen Namen ein.');
        return;
      }

        try {
            const path = getStandortePath();
            const standortId = currentEditingStandortId || name.toLowerCase().replace(/\s+/g, '-');
            const standortRef = doc(db, ...path, standortId);
            
            const data = {
                id: standortId,
                name: name,
                order: allStandorte.length,
                active: true,
                updatedAt: serverTimestamp()
            };
            
            if (!currentEditingStandortId) {
                data.createdAt = serverTimestamp();
            }
            
            await setDoc(standortRef, data, { merge: true });
            await loadStandorte();
            closeStandortForm();
        } catch (error) {
            console.error("Fehler beim Speichern des Standorts:", error);
            alert("Fehler beim Speichern: " + error.message);
        }
    });
}

window.editStandort = function(standortId) {
    const standort = allStandorte.find(s => s.id === standortId);
    if (!standort) return;
    
    currentEditingStandortId = standortId;
    document.getElementById('standortFormTitle').textContent = 'Standort bearbeiten';
    standortNameInput.value = standort.name;
    standortFormOverlay.style.display = 'block';
    standortForm.style.display = 'block';
};

window.deleteStandort = async function(standortId) {
    if (!confirm(`Möchten Sie den Standort wirklich löschen?`)) return;
    
    try {
        const path = getStandortePath();
        const standortRef = doc(db, ...path, standortId);
        await updateDoc(standortRef, { active: false, updatedAt: serverTimestamp() });
        await loadStandorte();
    } catch (error) {
        console.error("Fehler beim Löschen des Standorts:", error);
        alert("Fehler beim Löschen: " + error.message);
    }
};

window.closeStandortForm = function() {
    standortFormOverlay.style.display = 'none';
    standortForm.style.display = 'none';
    currentEditingStandortId = null;
};

// Schicht-Funktionen
if (addSchichtBtn) {
    addSchichtBtn.addEventListener('click', async () => {
        currentEditingSchichtId = null;
        document.getElementById('schichtFormTitle').textContent = 'Schicht hinzufügen';
        schichtNameInput.value = '';
        
        // Lade Standorte für das Dropdown
        if (allStandorte.length === 0) {
            await loadStandorte();
        }
        
        // Fülle Standort-Dropdown
        schichtStandortSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
        allStandorte
            .filter(s => s.active !== false)
            .forEach(standort => {
                const option = document.createElement('option');
                option.value = standort.id;
                option.textContent = standort.name;
                schichtStandortSelect.appendChild(option);
            });
        
        schichtStandortSelect.value = '';
        schichtFormOverlay.style.display = 'block';
        schichtForm.style.display = 'block';
    });
}

if (saveSchichtBtn) {
    saveSchichtBtn.addEventListener('click', async () => {
        const name = schichtNameInput.value.trim();
        const standortId = schichtStandortSelect.value;
        
      if (!name) {
            alert('Bitte geben Sie einen Namen ein.');
            return;
        }
        
        if (!standortId) {
            alert('Bitte wählen Sie einen Standort aus.');
        return;
      }

      try {
            const path = getSchichtenPath();
            const schichtId = currentEditingSchichtId || name.toUpperCase().replace(/\s+/g, '');
            const schichtRef = doc(db, ...path, schichtId);
            
            const data = {
                id: schichtId,
                name: name,
                standortId: standortId,
                order: allSchichten.length,
          active: true,
                updatedAt: serverTimestamp()
            };
            
            if (!currentEditingSchichtId) {
                data.createdAt = serverTimestamp();
            }
            
            await setDoc(schichtRef, data, { merge: true });
            await loadSchichten();
            closeSchichtForm();
        } catch (error) {
            console.error("Fehler beim Speichern der Schicht:", error);
            alert("Fehler beim Speichern: " + error.message);
        }
    });
}

window.editSchicht = async function(schichtId) {
    const schicht = allSchichten.find(s => s.id === schichtId);
    if (!schicht) return;
    
    // Lade Standorte für das Dropdown
    if (allStandorte.length === 0) {
    await loadStandorte();
    }
    
    // Fülle Standort-Dropdown
    schichtStandortSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
    allStandorte
        .filter(s => s.active !== false)
        .forEach(standort => {
            const option = document.createElement('option');
            option.value = standort.id;
            option.textContent = standort.name;
            if (standort.id === schicht.standortId) {
                option.selected = true;
            }
            schichtStandortSelect.appendChild(option);
        });
    
    currentEditingSchichtId = schichtId;
    document.getElementById('schichtFormTitle').textContent = 'Schicht bearbeiten';
    schichtNameInput.value = schicht.name;
    schichtStandortSelect.value = schicht.standortId || '';
    schichtFormOverlay.style.display = 'block';
    schichtForm.style.display = 'block';
};

window.deleteSchicht = async function(schichtId) {
    if (!confirm(`Möchten Sie die Schicht wirklich löschen?`)) return;
    
    try {
        const path = getSchichtenPath();
        const schichtRef = doc(db, ...path, schichtId);
        await updateDoc(schichtRef, { active: false, updatedAt: serverTimestamp() });
        await loadSchichten();
    } catch (error) {
        console.error("Fehler beim Löschen der Schicht:", error);
        alert("Fehler beim Löschen: " + error.message);
    }
};

window.closeSchichtForm = function() {
    schichtFormOverlay.style.display = 'none';
    schichtForm.style.display = 'none';
    currentEditingSchichtId = null;
};

// Mitarbeiter-Funktionen
if (addMitarbeiterBtn) {
    addMitarbeiterBtn.addEventListener('click', () => {
        currentEditingMitarbeiterId = null;
        document.getElementById('mitarbeiterFormTitle').textContent = 'Mitarbeiter hinzufügen';
        mitarbeiterVornameInput.value = '';
        mitarbeiterNachnameInput.value = '';
        mitarbeiterFuehrerscheinInput.value = '';
        mitarbeiterTelefonInput.value = '';
        renderQualifikationenCheckboxes(mitarbeiterQualifikationenGroup, []);
        mitarbeiterFormOverlay.style.display = 'block';
        mitarbeiterForm.style.display = 'block';
    });
}

function renderQualifikationenCheckboxes(container, selected = []) {
    if (!container) return;
    container.innerHTML = QUALIFIKATIONEN.map(q => `
        <label style="display: flex; align-items: center; gap: 5px;">
            <input type="checkbox" value="${q}" ${selected.includes(q) ? 'checked' : ''}>
            <span>${q}</span>
        </label>
    `).join('');
}

if (saveMitarbeiterBtn) {
    saveMitarbeiterBtn.addEventListener('click', async () => {
        const vorname = mitarbeiterVornameInput.value.trim();
        const nachname = mitarbeiterNachnameInput.value.trim();
        
        if (!vorname || !nachname) {
            alert('Bitte geben Sie Vor- und Nachname ein.');
            return;
        }
        
        const qualifikationen = Array.from(mitarbeiterQualifikationenGroup.querySelectorAll('input[type="checkbox"]:checked'))
            .map(cb => cb.value);
        
        try {
            const path = getMitarbeiterPath();
            const mitarbeiterId = currentEditingMitarbeiterId || `${vorname.toLowerCase()}-${nachname.toLowerCase()}`.replace(/\s+/g, '-');
            const mitarbeiterRef = doc(db, ...path, mitarbeiterId);
            
            const data = {
                id: mitarbeiterId,
                vorname: vorname,
                nachname: nachname,
                qualifikation: qualifikationen,
                fuehrerschein: mitarbeiterFuehrerscheinInput.value.trim() || '',
                telefonnummer: mitarbeiterTelefonInput.value.trim() || '',
                active: true,
                updatedAt: serverTimestamp()
            };
            
            if (!currentEditingMitarbeiterId) {
                data.createdAt = serverTimestamp();
            }
            
            await setDoc(mitarbeiterRef, data, { merge: true });
            await loadMitarbeiter();
            closeMitarbeiterForm();
        } catch (error) {
            console.error("Fehler beim Speichern des Mitarbeiters:", error);
            alert("Fehler beim Speichern: " + error.message);
        }
    });
}

window.editMitarbeiter = function(mitarbeiterId) {
    const mitarbeiter = allMitarbeiter.find(m => m.id === mitarbeiterId);
    if (!mitarbeiter) return;
    
    currentEditingMitarbeiterId = mitarbeiterId;
    document.getElementById('mitarbeiterFormTitle').textContent = 'Mitarbeiter bearbeiten';
    mitarbeiterVornameInput.value = mitarbeiter.vorname || '';
    mitarbeiterNachnameInput.value = mitarbeiter.nachname || '';
    mitarbeiterFuehrerscheinInput.value = mitarbeiter.fuehrerschein || '';
    mitarbeiterTelefonInput.value = mitarbeiter.telefonnummer || '';
    renderQualifikationenCheckboxes(mitarbeiterQualifikationenGroup, mitarbeiter.qualifikation || []);
    mitarbeiterFormOverlay.style.display = 'block';
    mitarbeiterForm.style.display = 'block';
};

window.deleteMitarbeiter = async function(mitarbeiterId) {
    if (!confirm(`Möchten Sie den Mitarbeiter wirklich löschen?`)) return;
    
    try {
        const path = getMitarbeiterPath();
        const mitarbeiterRef = doc(db, ...path, mitarbeiterId);
        await updateDoc(mitarbeiterRef, { active: false, updatedAt: serverTimestamp() });
        await loadMitarbeiter();
    } catch (error) {
        console.error("Fehler beim Löschen des Mitarbeiters:", error);
        alert("Fehler beim Löschen: " + error.message);
    }
};

window.closeMitarbeiterForm = function() {
    mitarbeiterFormOverlay.style.display = 'none';
    mitarbeiterForm.style.display = 'none';
    currentEditingMitarbeiterId = null;
};

window.closeSettingsPopup = function() {
    settingsPopupOverlay.style.display = 'none';
    settingsPopupForm.style.display = 'none';
};

/**
 * Zeigt das Mitarbeiter-Datenblatt an
 */
window.showMitarbeiterDatenblatt = async function(mitarbeiterId) {
    // Lade Mitarbeiter, falls noch nicht geladen
    if (!allMitarbeiter || allMitarbeiter.length === 0) {
        await loadMitarbeiter();
    }
    
    const mitarbeiter = allMitarbeiter.find(m => m.id === mitarbeiterId);
    if (!mitarbeiter) {
        alert("Mitarbeiter nicht gefunden.");
        return;
      }
      
    const overlay = document.getElementById("mitarbeiterDatenblattOverlay");
    const form = document.getElementById("mitarbeiterDatenblattForm");
    const content = document.getElementById("mitarbeiterDatenblattContent");
    
    if (!overlay || !form || !content) {
        alert("Fehler: Datenblatt-Formular nicht gefunden.");
        return;
    }
    
    // Rendere Datenblatt
    content.innerHTML = `
        <div class="datenblatt-section">
            <h3>${mitarbeiter.vorname} ${mitarbeiter.nachname}</h3>
        </div>
        <div class="datenblatt-section">
            <label>Qualifikationen:</label>
            <div class="qualification-group readonly">
                ${QUALIFIKATIONEN.map(q => `
                    <label class="readonly-label">
                        <input type="checkbox" ${mitarbeiter.qualifikation?.includes(q) ? 'checked' : ''} disabled>
                        <span>${q}</span>
                    </label>
                `).join('')}
            </div>
        </div>
        <div class="datenblatt-section">
            <label>Führerschein:</label>
            <p>${mitarbeiter.fuehrerschein || 'Keine Angabe'}</p>
        </div>
        <div class="datenblatt-section">
            <label>Telefonnummer:</label>
            <p><a href="tel:${mitarbeiter.telefonnummer || ''}">${mitarbeiter.telefonnummer || 'Keine Angabe'}</a></p>
        </div>
    `;
    
    overlay.style.display = 'block';
    form.style.display = 'block';
};

window.closeMitarbeiterDatenblatt = function() {
    const overlay = document.getElementById("mitarbeiterDatenblattOverlay");
    const form = document.getElementById("mitarbeiterDatenblattForm");
    if (overlay) overlay.style.display = 'none';
    if (form) form.style.display = 'none';
};

// Schließe Datenblatt beim Klick auf Overlay
if (document.getElementById("mitarbeiterDatenblattOverlay")) {
    document.getElementById("mitarbeiterDatenblattOverlay").addEventListener('click', (e) => {
        if (e.target === document.getElementById("mitarbeiterDatenblattOverlay")) {
            closeMitarbeiterDatenblatt();
        }
    });
}

/**
 * Prüft, ob ein Mitarbeiter bereits an diesem Tag verplant ist
 * @param {string} mitarbeiterId - Die Mitarbeiter-ID
 * @param {string} dayId - Der Tag (DD.MM.YYYY)
 * @param {string} wacheId - Die Standort-ID
 * @param {string} currentShiftId - Die aktuelle Schicht-ID (wird ignoriert)
 * @param {number} currentSlotIndex - Der aktuelle Slot-Index (wird ignoriert)
 * @returns {Promise<boolean>} true wenn doppelt verplant
 */
async function checkDoubleBooking(mitarbeiterId, dayId, wacheId, currentShiftId, currentSlotIndex) {
    try {
        // Durchsuche alle Standorte an diesem Tag
        const allStandorteToCheck = allStandorte.filter(s => s.active !== false);
        
        for (const standort of allStandorteToCheck) {
            const dayPath = getSchichtplanPath(standort.id, dayId);
            const dayRef = doc(db, ...dayPath);
            const daySnap = await getDoc(dayRef);
            
            if (!daySnap.exists()) continue;
            
            // Lade alle Schichten dieses Tages
            const shiftsPath = getSchichtplanPath(standort.id, dayId);
            const shiftsColRef = collection(db, ...shiftsPath, "schichten");
            const shiftsSnap = await getDocs(shiftsColRef);
            
            for (const shiftDoc of shiftsSnap.docs) {
                const shiftData = shiftDoc.data();
                const shiftId = shiftDoc.id;
                
                // Prüfe Personal1
                if (shiftData.personal1 && shiftData.personal1.mitarbeiterId === mitarbeiterId) {
                    // Ignoriere die aktuelle Schicht/Slot-Kombination
                    if (standort.id === wacheId && shiftId === currentShiftId && 1 === currentSlotIndex) {
                        continue; // Das ist der aktuelle Slot, den wir gerade bearbeiten
                    }
                    return true; // Doppelbelegung gefunden
                }
                
                // Prüfe Personal2
                if (shiftData.personal2 && shiftData.personal2.mitarbeiterId === mitarbeiterId) {
                    // Ignoriere die aktuelle Schicht/Slot-Kombination
                    if (standort.id === wacheId && shiftId === currentShiftId && 2 === currentSlotIndex) {
                        continue; // Das ist der aktuelle Slot, den wir gerade bearbeiten
                    }
                    return true; // Doppelbelegung gefunden
                }
            }
        }
        
        return false; // Keine Doppelbelegung
    } catch (error) {
        console.error("Fehler bei Doppelbelegungs-Prüfung:", error);
        return false; // Bei Fehler keine Warnung
    }
}

// Kalender-Funktionen
if (calendarBtn) {
    calendarBtn.addEventListener('click', () => {
        calendarPopupOverlay.style.display = 'block';
        calendarPopupForm.style.display = 'block';
        renderCalendar();
    });
}

window.closeCalendarPopup = function() {
    calendarPopupOverlay.style.display = 'none';
    calendarPopupForm.style.display = 'none';
};

/**
 * Rendert den Kalender mit allen Schichten aller Standorte
 */
async function renderCalendar() {
    const container = document.getElementById('calendarContainer');
    if (!container) return;
    
    container.innerHTML = '<div class="info-card">Lade Kalender...</div>';
    
    try {
        // Lade alle Standorte
        await loadStandorte();
        
        // Erstelle Kalender-Grid
    const today = new Date();
        const currentMonth = today.getMonth();
        const currentYear = today.getFullYear();
        
        // Erstelle Monatsansicht
        const firstDay = new Date(currentYear, currentMonth, 1);
        const lastDay = new Date(currentYear, currentMonth + 1, 0);
        const daysInMonth = lastDay.getDate();
        const startingDayOfWeek = firstDay.getDay();
        
        let calendarHTML = `
            <div class="calendar-header-controls">
                <button id="prevMonthBtn" class="btn-small">← Vorheriger Monat</button>
                <h3>${getMonthName(currentMonth)} ${currentYear}</h3>
                <button id="nextMonthBtn" class="btn-small">Nächster Monat →</button>
            </div>
            <div class="calendar-grid">
                <div class="calendar-weekday">Mo</div>
                <div class="calendar-weekday">Di</div>
                <div class="calendar-weekday">Mi</div>
                <div class="calendar-weekday">Do</div>
                <div class="calendar-weekday">Fr</div>
                <div class="calendar-weekday">Sa</div>
                <div class="calendar-weekday">So</div>
        `;
        
        // Leere Zellen für den ersten Tag
        for (let i = 0; i < startingDayOfWeek; i++) {
            calendarHTML += '<div class="calendar-day empty"></div>';
        }
        
        // Tage des Monats
        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(currentYear, currentMonth, day);
            const dayId = formatDayId(date);
            const isToday = day === today.getDate() && currentMonth === today.getMonth() && currentYear === today.getFullYear();
            
            calendarHTML += `
                <div class="calendar-day ${isToday ? 'today' : ''}" data-day="${dayId}" onclick="showCalendarDayDetails('${dayId}')">
                    <div class="calendar-day-number">${day}</div>
                    <div class="calendar-day-shifts" id="shifts-${dayId}"></div>
                </div>
            `;
        }
        
        calendarHTML += '</div>';
        container.innerHTML = calendarHTML;
        
        // Lade Schichten und Bereitschaften für jeden Tag
        for (let day = 1; day <= daysInMonth; day++) {
            const date = new Date(currentYear, currentMonth, day);
            const dayId = formatDayId(date);
            await loadCalendarDayShifts(dayId);
        }
        
        // Event Listeners für Monatsnavigation
        document.getElementById('prevMonthBtn')?.addEventListener('click', () => {
            // TODO: Vorherigen Monat laden
            console.log('Vorheriger Monat');
        });
        
        document.getElementById('nextMonthBtn')?.addEventListener('click', () => {
            // TODO: Nächsten Monat laden
            console.log('Nächster Monat');
        });
        
    } catch (error) {
        console.error("Fehler beim Laden des Kalenders:", error);
        container.innerHTML = '<div class="info-card" style="color: red;">Fehler beim Laden des Kalenders.</div>';
    }
}

/**
 * Formatiert ein Datum als dayId (DD.MM.YYYY)
 */
function formatDayId(date) {
    const day = String(date.getDate()).padStart(2, '0');
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const year = date.getFullYear();
    return `${day}.${month}.${year}`;
}

/**
 * Gibt den Monatsnamen zurück
 */
function getMonthName(monthIndex) {
    const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 
                    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return months[monthIndex];
}

/**
 * Lädt die Schichten für einen Tag im Kalender
 */
async function loadCalendarDayShifts(dayId) {
    try {
        const shiftsContainer = document.getElementById(`shifts-${dayId}`);
        if (!shiftsContainer) return;
        
        let openShifts = 0;
        let bereitschaftenCount = 0;
        
        // Lade neue Bereitschaften aus der separaten Collection
        try {
            const bereitschaftenRef = collection(db, ...getBereitschaftenPath(dayId));
            const bereitschaftenSnap = await getDocs(bereitschaftenRef);
            bereitschaftenCount = bereitschaftenSnap.size;
        } catch (error) {
            console.error(`Fehler beim Laden der Bereitschaften für ${dayId}:`, error);
        }
        
        // Durchsuche alle Standorte für normale Schichten
        for (const standort of allStandorte.filter(s => s.active !== false)) {
            const dayPath = getSchichtplanPath(standort.id, dayId);
            const dayRef = doc(db, ...dayPath);
            const daySnap = await getDoc(dayRef);
            
            if (daySnap.exists()) {
                const shiftsPath = getSchichtplanPath(standort.id, dayId);
                const shiftsColRef = collection(db, ...shiftsPath, "schichten");
                const shiftsSnap = await getDocs(shiftsColRef);
                
                shiftsSnap.forEach(shiftDoc => {
                    const shiftId = shiftDoc.id;
                    const shiftData = shiftDoc.data();
                    const isBereitschaftShift = isBereitschaft(shiftId);
                    
                    if (!isBereitschaftShift) {
                        // Normale Schichten - nur offene zählen
                        const isFullyManned = shiftData.personal1 && shiftData.personal2;
                        if (!isFullyManned) {
                            openShifts++;
                        }
                    }
                });
            }
        }
        
        let infoHTML = '';
        if (openShifts > 0 || bereitschaftenCount > 0) {
            infoHTML = '<div class="calendar-shift-info">';
            if (openShifts > 0) {
                infoHTML += `<span class="calendar-shift-open">${openShifts} offen</span>`;
            }
            if (bereitschaftenCount > 0) {
                infoHTML += `<span class="calendar-shift-bereitschaft">${bereitschaftenCount} Bereitschaft${bereitschaftenCount > 1 ? 'en' : ''}</span>`;
            }
            infoHTML += '</div>';
        }
        
        shiftsContainer.innerHTML = infoHTML;
    } catch (error) {
        console.error(`Fehler beim Laden der Schichten für ${dayId}:`, error);
    }
}

/**
 * Zeigt Details für einen Tag im Kalender - Gesamtübersicht aller Wachen und Schichten
 */
window.showCalendarDayDetails = async function(dayId) {
    const container = document.getElementById('calendarContainer');
    if (!container) return;
    
    container.innerHTML = '<div class="info-card">Lade Gesamtübersicht...</div>';
    
    try {
        // Lade alle Standorte
        await loadStandorte();
        await loadSchichten();
        await loadMitarbeiter();
        
        let overviewHTML = `
            <div class="calendar-header-controls">
                <button id="backToCalendarBtn" class="btn-small">← Zurück zum Kalender</button>
                <h3>Gesamtübersicht: ${dayId}</h3>
                <div></div>
            </div>
            <div class="calendar-day-overview" id="dayOverviewContent">
        `;
        
        // Durchsuche alle Standorte
        const activeStandorte = allStandorte.filter(s => s.active !== false);
        
        if (activeStandorte.length === 0) {
            overviewHTML += '<div class="info-card">Keine Standorte konfiguriert.</div>';
        } else {
            // Standorte und Schichten (inkl. Bereitschaften als normaler Standort)
            for (const standort of activeStandorte) {
                const dayPath = getSchichtplanPath(standort.id, dayId);
                const dayRef = doc(db, ...dayPath);
                const daySnap = await getDoc(dayRef);
                
                overviewHTML += `
                    <div class="overview-standort-card">
                        <h4 class="standort-header">${standort.name}</h4>
                        <div class="overview-shifts-list" id="shifts-${standort.id}-${dayId}">
                `;
                
                if (daySnap.exists()) {
                    const shiftsPath = getSchichtplanPath(standort.id, dayId);
                    const shiftsColRef = collection(db, ...shiftsPath, "schichten");
                    const shiftsSnap = await getDocs(shiftsColRef);
                    
                    if (shiftsSnap.empty) {
                        overviewHTML += '<div class="info-text">Keine Schichten an diesem Tag.</div>';
                    } else {
                        const shiftsArray = [];
                        shiftsSnap.forEach(shiftDoc => {
                            shiftsArray.push({
                                id: shiftDoc.id,
                                data: shiftDoc.data()
                            });
                        });
                        
                        // Sortiere Schichten: Bereitschaften zuerst, dann alphabetisch
                        shiftsArray.sort((a, b) => {
                            const aIsBereitschaft = isBereitschaft(a.id);
                            const bIsBereitschaft = isBereitschaft(b.id);
                            
                            // Bereitschaften zuerst
                            if (aIsBereitschaft && !bIsBereitschaft) return -1;
                            if (!aIsBereitschaft && bIsBereitschaft) return 1;
                            
                            // Dann alphabetisch
                            const nameA = a.id || '';
                            const nameB = b.id || '';
                            return nameA.localeCompare(nameB);
                        });
                        
                        shiftsArray.forEach(shift => {
                            const shiftData = shift.data;
                            const isBereitschaftShift = isBereitschaft(shift.id);
                            
                            let mannedClass = 'unmanned';
                            if (isBereitschaftShift) {
                                // Bereitschaften: grün wenn besetzt
                                mannedClass = shiftData.personal1 ? 'bereitschaft-manned' : 'bereitschaft';
                            } else {
                                const isFullyManned = shiftData.personal1 && shiftData.personal2;
                                const isPartiallyManned = shiftData.personal1 || shiftData.personal2;
                                mannedClass = isFullyManned ? 'fully-manned' : (isPartiallyManned ? 'partially-manned' : 'unmanned');
                            }
                            
                            // Bei Bereitschaften nur Personal1 anzeigen
                            const personnelSlots = isBereitschaftShift
                                ? renderPersonnelSlotOverview(shiftData.personal1, true, dayId, standort.id, shift.id, 1)
                                : `${renderPersonnelSlotOverview(shiftData.personal1, false, dayId, standort.id, shift.id, 1)}${renderPersonnelSlotOverview(shiftData.personal2, false, dayId, standort.id, shift.id, 2)}`;
                            
                            overviewHTML += `
                                <div class="overview-shift-row ${mannedClass}">
                                    <div class="shift-name">${shift.id}</div>
                                    <div class="shift-personnel">
                                        ${personnelSlots}
                                    </div>
                                </div>
                            `;
                        });
                    }
                } else {
                    overviewHTML += '<div class="info-text">Kein Tag angelegt.</div>';
                }
                
                overviewHTML += `
                        </div>
                    </div>
                `;
            }
        }
        
        // Lade und zeige neue Bereitschaften aus der separaten Collection
        try {
            await loadBereitschaftsTypen();
            await loadMitarbeiter();
            
            const bereitschaftenRef = collection(db, ...getBereitschaftenPath(dayId));
            const bereitschaftenSnap = await getDocs(bereitschaftenRef);
            
            if (!bereitschaftenSnap.empty) {
                overviewHTML += `
                    <div class="overview-standort-card">
                        <h4 class="standort-header">Bereitschaften</h4>
                        <div class="overview-shifts-list" id="bereitschaften-${dayId}">
                `;
                
                bereitschaftenSnap.forEach(bereitschaftDoc => {
                    const bereitschaftData = bereitschaftDoc.data();
                    const mitarbeiter = allMitarbeiter.find(m => m.id === bereitschaftData.mitarbeiterId);
                    const typ = allBereitschaftsTypen.find(t => t.id === bereitschaftData.typId);
                    const mitarbeiterName = mitarbeiter ? `${mitarbeiter.nachname}, ${mitarbeiter.vorname}` : 'Unbekannt';
                    const typName = typ ? typ.name : 'Unbekannt';
                    
                    overviewHTML += `
                        <div class="overview-shift-row bereitschaft-manned">
                            <div class="shift-name">${typName}</div>
                            <div class="shift-personnel">
                                <div class="personnel-slot" style="background-color: #ffffff;">
                                    <span class="personnel-name">${mitarbeiterName}</span>
                                </div>
                            </div>
                        </div>
                    `;
                });
                
                overviewHTML += `
                        </div>
                    </div>
                `;
            }
        } catch (error) {
            console.error(`Fehler beim Laden der Bereitschaften für ${dayId}:`, error);
        }
        
        overviewHTML += '</div>';
        container.innerHTML = overviewHTML;
        
        // Event Listener für Zurück-Button
        document.getElementById('backToCalendarBtn')?.addEventListener('click', () => {
            renderCalendar();
        });
        
    } catch (error) {
        console.error("Fehler beim Laden der Gesamtübersicht:", error);
        container.innerHTML = '<div class="info-card" style="color: red;">Fehler beim Laden der Gesamtübersicht.</div>';
    }
};

/**
 * Rendert einen Personal-Slot für die Übersicht
 * @param {Object} personalData - Die Personal-Daten
 * @param {boolean} isBereitschaft - Ob dies eine Bereitschafts-Schicht ist
 * @param {string} dayId - Der Tag-ID
 * @param {string} standortId - Der Standort-ID
 * @param {string} shiftId - Die Schicht-ID
 * @param {number} slotIndex - Der Slot-Index (1 oder 2)
 */
function renderPersonnelSlotOverview(personalData, isBereitschaft = false, dayId = '', standortId = '', shiftId = '', slotIndex = 0) {
    if (!personalData) {
        return '<div class="personnel-slot-empty">Leer</div>';
    }
    
    const name = personalData.name || 'Unbekannt';
    const quals = personalData.qualifikationen?.join('/') || '';
    const color = personalData.farbe || '#ffffff';
    const mitarbeiterId = personalData.mitarbeiterId || '';
    
    // Rechtsklick-Handler nur für Bereitschaften
    const contextMenuHandler = isBereitschaft && mitarbeiterId 
        ? `oncontextmenu="event.preventDefault(); showBereitschaftAssignmentMenu(event, '${mitarbeiterId}', '${name}', '${dayId}'); return false;"`
        : '';
    
    return `
        <div class="personnel-slot-filled ${isBereitschaft ? 'bereitschaft-personnel' : ''}" 
             style="background-color: ${color};"
             ${contextMenuHandler}
             title="${isBereitschaft ? 'Rechtsklick: Mitarbeiter einer offenen Schicht zuweisen' : ''}">
            <span class="personnel-name">${name}</span>
            ${quals ? `<span class="personnel-quals">(${quals})</span>` : ''}
        </div>
    `;
}

// Initialisiere beim App-Start
/**
 * Zeigt ein Kontextmenü zum Zuweisen eines Bereitschafts-Mitarbeiters zu einer offenen Schicht
 */
window.showBereitschaftAssignmentMenu = async function(event, mitarbeiterId, mitarbeiterName, sourceDayId) {
    await loadStandorte();
    await loadSchichten();
    
    // Finde alle offenen Schichten (alle Standorte, alle Tage)
    const openShifts = [];
    
    // Durchsuche alle Standorte
    for (const standort of allStandorte.filter(s => s.active !== false && s.name !== 'Bereitschaften')) {
        // Lade alle Tage für diesen Standort (vereinfacht: nur aktuelle und zukünftige Tage)
        // Für Demo: Suche in den nächsten 30 Tagen
        const today = new Date();
        for (let i = 0; i < 30; i++) {
            const date = new Date(today);
            date.setDate(today.getDate() + i);
            const dayId = formatDayId(date);
            
            try {
                const dayPath = getSchichtplanPath(standort.id, dayId);
                const dayRef = doc(db, ...dayPath);
                const daySnap = await getDoc(dayRef);
                
                if (daySnap.exists()) {
                    const shiftsPath = getSchichtplanPath(standort.id, dayId);
                    const shiftsColRef = collection(db, ...shiftsPath, "schichten");
                    const shiftsSnap = await getDocs(shiftsColRef);
                    
                    shiftsSnap.forEach(shiftDoc => {
                        const shiftId = shiftDoc.id;
                        const shiftData = shiftDoc.data();
                        const isBereitschaftShift = isBereitschaft(shiftId);
                        
                        // Bereitschaften überspringen (werden separat behandelt)
                        if (isBereitschaftShift) {
                            return;
                        }
                        
                        const isOpen = !shiftData.personal1 || !shiftData.personal2;
                        
                        if (isOpen) {
                            openShifts.push({
                                dayId: dayId,
                                standortId: standort.id,
                                standortName: standort.name,
                                shiftId: shiftDoc.id,
                                hasPersonal1: !!shiftData.personal1,
                                hasPersonal2: !!shiftData.personal2
                            });
                        }
                    });
                }
            } catch (error) {
                // Ignoriere Fehler
            }
        }
    }
    
    // Füge auch Bereitschafts-Schichten hinzu, die auf allen Wachen möglich sind
    // BNRK und BTRK: alle Wachen
    // BTK und BNK: nur KTW-Wache
    const bereitschaftsSchichten = ['BNRK', 'BTRK', 'BTK', 'BNK'];
    
    for (const standort of allStandorte.filter(s => s.active !== false && s.name !== 'Bereitschaften')) {
        const isKTW = standort.name.toLowerCase().includes('ktw');
        
        const today = new Date();
        for (let i = 0; i < 30; i++) {
            const date = new Date(today);
            date.setDate(today.getDate() + i);
            const dayId = formatDayId(date);
            
            for (const bereitschaftShiftId of bereitschaftsSchichten) {
                // BTK und BNK nur für KTW-Wache
                if ((bereitschaftShiftId === 'BTK' || bereitschaftShiftId === 'BNK') && !isKTW) {
                    continue;
                }
                
                try {
                    const dayPath = getSchichtplanPath(standort.id, dayId);
                    const shiftRef = doc(db, ...dayPath, "schichten", bereitschaftShiftId);
                    const shiftSnap = await getDoc(shiftRef);
                    
                    // Wenn Schicht nicht existiert oder nicht besetzt ist, ist sie offen
                    if (!shiftSnap.exists() || !shiftSnap.data().personal1) {
                        openShifts.push({
                            dayId: dayId,
                            standortId: standort.id,
                            standortName: standort.name,
                            shiftId: bereitschaftShiftId,
                            hasPersonal1: false,
                            hasPersonal2: false,
                            isBereitschaft: true
                        });
                    }
                } catch (error) {
                    // Ignoriere Fehler
                }
            }
        }
    }
    
    if (openShifts.length === 0) {
        alert('Keine offenen Schichten gefunden.');
    return;
  }

    // Erstelle Kontextmenü
    const menu = document.createElement('div');
    menu.className = 'context-menu';
    menu.style.position = 'fixed';
    menu.style.left = event.clientX + 'px';
    menu.style.top = event.clientY + 'px';
    menu.style.zIndex = '10000';
    menu.style.background = 'white';
    menu.style.border = '1px solid #ccc';
    menu.style.borderRadius = '4px';
    menu.style.boxShadow = '0 2px 8px rgba(0,0,0,0.2)';
    menu.style.padding = '8px 0';
    menu.style.maxHeight = '300px';
    menu.style.overflowY = 'auto';
    menu.style.minWidth = '250px';
    
    menu.innerHTML = `
        <div style="padding: 8px 16px; font-weight: 600; border-bottom: 1px solid #eee; margin-bottom: 4px;">
            ${mitarbeiterName} zuweisen:
    </div>
  `;

    // Gruppiere nach Tag
    const shiftsByDay = {};
    openShifts.forEach(shift => {
        if (!shiftsByDay[shift.dayId]) {
            shiftsByDay[shift.dayId] = [];
        }
        shiftsByDay[shift.dayId].push(shift);
    });
    
    Object.keys(shiftsByDay).sort().forEach(dayId => {
        const dayShifts = shiftsByDay[dayId];
        const dayHeader = document.createElement('div');
        dayHeader.style.padding = '4px 16px';
        dayHeader.style.fontWeight = '600';
        dayHeader.style.color = '#666';
        dayHeader.style.fontSize = '0.85rem';
        dayHeader.textContent = dayId;
        menu.appendChild(dayHeader);
        
        dayShifts.forEach(shift => {
            const isBereitschaftShift = shift.isBereitschaft || isBereitschaft(shift.shiftId);
            const slotText = isBereitschaftShift ? 'Bereitschaft' : (!shift.hasPersonal1 ? 'Personal1' : (!shift.hasPersonal2 ? 'Personal2' : ''));
            const item = document.createElement('div');
            item.style.padding = '6px 16px';
            item.style.cursor = 'pointer';
            item.style.fontSize = '0.9rem';
            item.textContent = `${shift.standortName} - ${shift.shiftId} (${slotText})`;
            
            item.addEventListener('mouseenter', () => {
                item.style.background = '#f0f0f0';
            });
            item.addEventListener('mouseleave', () => {
                item.style.background = 'white';
            });
            
            item.addEventListener('click', async () => {
                // Bei Bereitschaften immer Slot 1 verwenden
                const slotIndex = isBereitschaftShift ? 1 : (!shift.hasPersonal1 ? 1 : 2);
                await assignBereitschaftToShift(shift.dayId, shift.standortId, shift.shiftId, mitarbeiterId, slotIndex, sourceDayId);
                menu.remove();
            });
            
            menu.appendChild(item);
        });
    });
    
    document.body.appendChild(menu);
    
    // Schließe Menü beim Klick außerhalb
    const closeMenu = (e) => {
        if (!menu.contains(e.target)) {
            menu.remove();
            document.removeEventListener('click', closeMenu);
        }
    };
    setTimeout(() => document.addEventListener('click', closeMenu), 100);
};

/**
 * Weist einen Bereitschafts-Mitarbeiter einer Schicht zu
 */
async function assignBereitschaftToShift(dayId, standortId, shiftId, mitarbeiterId, slotIndex = null, sourceDayId = null) {
    try {
        // Prüfe, ob der Tag existiert, sonst erstelle ihn
        const dayPath = getSchichtplanPath(standortId, dayId);
        const dayRef = doc(db, ...dayPath);
        const daySnap = await getDoc(dayRef);
        
        if (!daySnap.exists()) {
            await setDoc(dayRef, {
                datum: dayId,
                timestamp: serverTimestamp()
            });
        }
        
        // Prüfe, ob die Schicht existiert
        const shiftsPath = getSchichtplanPath(standortId, dayId);
        const shiftRef = doc(db, ...shiftsPath, "schichten", shiftId);
        const shiftSnap = await getDoc(shiftRef);
        
        const mitarbeiter = allMitarbeiter.find(m => m.id === mitarbeiterId);
        if (!mitarbeiter) {
            alert('Mitarbeiter nicht gefunden.');
            return;
        }
        
        if (!shiftSnap.exists()) {
            await setDoc(shiftRef, {
                personal1: null,
                personal2: null,
                isTemporary: false
            });
        }
        
        const shiftData = shiftSnap.data() || {};
        
        // Bestimme Slot
        let slotToFill = null;
        if (slotIndex) {
            slotToFill = slotIndex === 1 ? 'personal1' : 'personal2';
        } else {
            if (!shiftData.personal1) {
                slotToFill = 'personal1';
            } else if (!shiftData.personal2) {
                slotToFill = 'personal2';
            } else {
                alert('Beide Personal-Slots sind bereits belegt.');
            return;
            }
        }
        
        // Speichere Mitarbeiter in den Slot
        await updateDoc(shiftRef, {
            [slotToFill]: {
                mitarbeiterId: mitarbeiterId,
                name: `${mitarbeiter.vorname} ${mitarbeiter.nachname}`,
                qualifikationen: mitarbeiter.qualifikation || [],
                farbe: '#ffffff'
            }
        });
        
        // Entferne Mitarbeiter aus der Bereitschaft (neue Struktur: direkt pro Tag)
        const bereitschaftenPath = getBereitschaftenPath(dayId);
        const bereitschaftenColRef = collection(db, ...bereitschaftenPath);
        const bereitschaftenSnap = await getDocs(bereitschaftenColRef);
        
        for (const bereitschaftDoc of bereitschaftenSnap.docs) {
            const bereitschaftData = bereitschaftDoc.data();
            if (bereitschaftData.mitarbeiterId === mitarbeiterId) {
                await deleteDoc(bereitschaftDoc.ref);
                break;
            }
        }
        
        console.log(`Bereitschaft ${mitarbeiterId} wurde Schicht ${shiftId} zugewiesen`);
        
        // Aktualisiere die Ansicht, falls nötig
        if (sourceDayId) {
            // Wenn wir aus der Kalender-Ansicht kommen, aktualisiere diese
            showCalendarDayDetails(sourceDayId);
        } else {
            // Sonst aktualisiere die normale Ansicht
            const currentWache = wacheSelect.value;
            if (currentWache && currentWache !== 'default') {
                listenForDays(currentWache);
            }
        }
    } catch (error) {
        console.error('Fehler beim Zuweisen der Bereitschaft:', error);
        alert('Fehler beim Zuweisen der Bereitschaft: ' + error.message);
    }
}

/**
 * Lädt und rendert Bereitschaften für einen Tag
 */
function listenForBereitschaften(dayId) {
    const container = document.getElementById(`bereitschaften-list-${dayId}`);
    if (!container) return;
    
    const bereitschaftenPath = getBereitschaftenPath(dayId);
    const bereitschaftenColRef = collection(db, ...bereitschaftenPath);
    const q = query(bereitschaftenColRef, orderBy('createdAt', 'asc'));
    
    onSnapshot(q, (snapshot) => {
        container.innerHTML = '';
        
        if (snapshot.empty) {
            container.innerHTML = '<div class="bereitschaft-empty">Keine Bereitschaften</div>';
            return;
        }
        
        snapshot.forEach(docSnap => {
            const bereitschaft = docSnap.data();
            const bereitschaftId = docSnap.id;
            const mitarbeiter = allMitarbeiter.find(m => m.id === bereitschaft.mitarbeiterId);
            
            if (!mitarbeiter) {
                console.warn(`Mitarbeiter ${bereitschaft.mitarbeiterId} nicht gefunden`);
      return;
    }

            const name = `${mitarbeiter.nachname}, ${mitarbeiter.vorname}`;
            const quals = mitarbeiter.qualifikation?.join('/') || '';
            
            const bereitschaftEl = document.createElement('div');
            bereitschaftEl.className = 'bereitschaft-item';
            bereitschaftEl.dataset.bereitschaftId = bereitschaftId;
            bereitschaftEl.dataset.mitarbeiterId = bereitschaft.mitarbeiterId;
            bereitschaftEl.dataset.mitarbeiterName = name;
            bereitschaftEl.dataset.dayId = dayId;
            bereitschaftEl.style.backgroundColor = '#3b82f6';
            bereitschaftEl.style.cursor = 'pointer';
            bereitschaftEl.title = 'Rechtsklick: Mitarbeiter einer offenen Schicht zuweisen';
            
            bereitschaftEl.innerHTML = `
                <span class="bereitschaft-name">${name} (${quals})</span>
                <button class="remove-btn" onclick="event.stopPropagation(); deleteBereitschaft('${dayId}', '${bereitschaftId}');" title="Bereitschaft entfernen">${getTrashIcon('white')}</button>
            `;
            
            container.appendChild(bereitschaftEl);
        });
    }, (error) => {
        console.error(`Fehler beim Laden der Bereitschaften für Tag ${dayId}:`, error);
        container.innerHTML = '<div style="color: red;">Fehler beim Laden der Bereitschaften.</div>';
    });
}

// Diese Funktion wurde entfernt - openAddBereitschaftPopup unterstützt jetzt dayId als optionalen Parameter;

/**
 * Speichert eine neue Bereitschaft
 */
// Diese Funktion wurde entfernt - verwende window.saveBereitschaft(dayId, mitarbeiterId, typId) stattdessen

/**
 * Löscht eine Bereitschaft
 */
window.deleteBereitschaft = async function(dayId, bereitschaftId) {
    if (!confirm('Möchten Sie diese Bereitschaft wirklich löschen?')) {
        return;
    }
    
    try {
        const bereitschaftPath = getBereitschaftenPath(dayId, bereitschaftId);
        const bereitschaftRef = doc(db, ...bereitschaftPath);
        await deleteDoc(bereitschaftRef);
        console.log(`Bereitschaft ${bereitschaftId} gelöscht.`);
    } catch (error) {
        console.error('Fehler beim Löschen der Bereitschaft:', error);
        alert('Fehler beim Löschen der Bereitschaft: ' + error.message);
    }
};

// Long-Press Handler für Touch-Geräte
let longPressTimer = null;
let longPressTarget = null;

function setupLongPressHandlers() {
    // Event-Delegation für Bereitschafts-Personal - Rechtsklick
    document.addEventListener('contextmenu', (e) => {
        if (!e.target || typeof e.target.closest !== 'function') return;
        // Prüfe ob das Ziel oder ein Parent-Element ein Bereitschafts-Element ist
        const target = e.target.closest('.bereitschaft-item');
        if (target) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            
            const mitarbeiterId = target.dataset.mitarbeiterId;
            const mitarbeiterName = target.dataset.mitarbeiterName;
            const dayId = target.dataset.dayId;
            
            if (mitarbeiterId && mitarbeiterName && dayId) {
                showBereitschaftAssignmentMenu(e, mitarbeiterId, mitarbeiterName, dayId);
            }
            return false;
        }
    }, true);
    
    // Event-Delegation für Bereitschafts-Personal - Touch Long-Press
    document.addEventListener('touchstart', (e) => {
        if (!e.target || typeof e.target.closest !== 'function') return;
        const target = e.target.closest('.bereitschaft-item');
        if (target) {
            longPressTarget = target;
            longPressTimer = setTimeout(() => {
                // Verhindere Copy-Logik
                e.preventDefault();
                
                const mitarbeiterId = target.getAttribute('data-mitarbeiter-id');
                const mitarbeiterName = target.getAttribute('data-mitarbeiter-name');
                const dayId = target.getAttribute('data-day-id');
                
                // Erstelle ein MouseEvent-ähnliches Objekt für die Funktion
                const fakeEvent = {
                    clientX: e.touches[0].clientX,
                    clientY: e.touches[0].clientY,
                    preventDefault: () => {},
                    stopPropagation: () => {}
                };
                
                showBereitschaftAssignmentMenu(fakeEvent, mitarbeiterId, mitarbeiterName, dayId);
                longPressTimer = null;
                longPressTarget = null;
            }, 500); // 500ms für Long-Press
        }
    }, { passive: false });
    
    document.addEventListener('touchend', (e) => {
        if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
        }
        longPressTarget = null;
    });
    
    document.addEventListener('touchmove', (e) => {
        if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
        }
        longPressTarget = null;
    });
    
    // Verhindere Copy-Logik bei Bereitschafts-Personal
    document.addEventListener('copy', (e) => {
        if (!e.target || typeof e.target.closest !== 'function') return;
        const target = e.target.closest('[data-bereitschaft-id]');
        if (target) {
            e.preventDefault();
            return false;
        }
    });
    
    // Verhindere Textauswahl bei Bereitschafts-Personal
    document.addEventListener('selectstart', (e) => {
        if (!e.target || typeof e.target.closest !== 'function') return;
        const target = e.target.closest('[data-bereitschaft-id]');
        if (target) {
            e.preventDefault();
            return false;
        }
    });
}

async function initializeApp() {
    // Lade Standorte, Schichten und Mitarbeiter beim Start
    loadStandorte();
    loadSchichten();
    loadMitarbeiter();
    
    // Setup Long-Press Handler
    setupLongPressHandlers();
    
    // Bestehende Initialisierung...
    wacheSelect.value = "default";
    
    // Stelle sicher, dass Kalender-Popup geschlossen ist
    if (calendarPopupOverlay) {
        calendarPopupOverlay.style.display = 'none';
    }
    if (calendarPopupForm) {
        calendarPopupForm.style.display = 'none';
    }
    
    if (showYellowListBtn) {
        showYellowListBtn.addEventListener("click", showYellowPersonnelList);
    }
    
    // Bereitschafts-Typen laden
    await loadBereitschaftsTypen();
    
    // Event Listener für Bereitschafts-Typ-Buttons
    const addBereitschaftsTypBtn = document.getElementById("addBereitschaftsTypBtn");
    if (addBereitschaftsTypBtn) {
        addBereitschaftsTypBtn.addEventListener('click', () => {
            currentEditingBereitschaftsTypId = null;
            openBereitschaftsTypForm();
        });
    }
    
    const saveBereitschaftsTypBtn = document.getElementById("saveBereitschaftsTypBtn");
    if (saveBereitschaftsTypBtn) {
        saveBereitschaftsTypBtn.addEventListener('click', saveBereitschaftsTyp);
    }
    
    // Event Listener für Bereitschaften-View
    const addBereitschaftBtn = document.getElementById("addBereitschaftBtn");
    if (addBereitschaftBtn) {
        addBereitschaftBtn.addEventListener('click', openAddBereitschaftPopup);
    }
    
    const bereitschaftenViewOverlay = document.getElementById("bereitschaftenViewOverlay");
    if (bereitschaftenViewOverlay) {
        bereitschaftenViewOverlay.addEventListener('click', (e) => {
            if (e.target === bereitschaftenViewOverlay) {
                closeBereitschaftenView();
        }
      });
    }
    
    const bereitschaftsTypFormOverlay = document.getElementById("bereitschaftsTypFormOverlay");
    if (bereitschaftsTypFormOverlay) {
        bereitschaftsTypFormOverlay.addEventListener('click', (e) => {
            if (e.target === bereitschaftsTypFormOverlay) {
                closeBereitschaftsTypForm();
            }
        });
    }
}