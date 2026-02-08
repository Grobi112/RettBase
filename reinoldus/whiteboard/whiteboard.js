// whiteboard.js
import { db } from "/firebase-config.js"; // FIX: Absoluter Pfad
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
    writeBatch
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --- GLOBALE KONSTANTEN FÜR FARBEN UND STRUKTUR ---
let currentWache = "default";
let dayUnsubscribe = null; 
let isOVD = false;

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
const nameInput = document.getElementById("personnelName");
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
window.openPersonnelPopup = function(dayId, shiftId, slotIndex, currentData = null, wacheId = null) {
    personnelPopupForm.dataset.dayId = dayId;
    personnelPopupForm.dataset.shiftId = shiftId;
    personnelPopupForm.dataset.slotIndex = slotIndex;
    personnelPopupForm.dataset.wacheId = wacheId || currentWache; 

    // Checkboxen rendern
    qualGroup.innerHTML = QUALIFIKATIONEN.map(q => `
        <label>
            <input type="checkbox" name="qual" value="${q}" ${currentData?.qualifikationen?.includes(q) ? 'checked' : ''}>
            ${q}
        </label>
    `).join('');

    // Daten vorbelegen
    nameInput.value = currentData?.name || '';
    colorInput.value = currentData?.farbe || '#ffffff'; // Stellt sicher, dass #ffffff der Default ist

    personnelPopupOverlay.style.display = "block";
    personnelPopupForm.style.display = "block";
}

window.closePersonnelPopup = function() {
    personnelPopupOverlay.style.display = "none";
    personnelPopupForm.style.display = "none";
}

// --- HILFSFUNKTIONEN ---

/**
 * Ruft die Schicht-Dokumente für einen Tag ab. (HILFSFUNKTION)
 */
async function getShiftDocs(dayId, wacheId) {
    const shiftsColRef = collection(db, "whiteboard", wacheId, "tage", dayId, "schichten");
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
        const shiftRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", shiftId);
        
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
        const shiftRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", shiftId);
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
        const dayRef = doc(db, "whiteboard", wacheId, "tage", dayId);
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
        const dayRef = doc(db, "whiteboard", currentWache, "tage", dayId);
        
        await setDoc(dayRef, {
            datum: dayId,
            timestamp: serverTimestamp() 
        }, { merge: true });

        // Nur die ERSTE Schicht aus der Liste der Wachen-Schichten erstellen
        const shifts = WACHEN_SCHICHTEN[currentWache];
        if (shifts.length > 0) {
            const defaultShiftName = shifts[0]; 
            
            // FIX: Der erste Shift wird IMMER als temporär angelegt.
            const tempShiftId = 'temp-initial-' + Date.now(); 
            const shiftRef = doc(db, "whiteboard", currentWache, "tage", dayId, "schichten", tempShiftId);
            
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
    const shiftsForWache = WACHEN_SCHICHTEN[wacheId];
    if (shiftsForWache.length === 0) {
        alert("Für diese Wache sind keine Schichten definiert.");
        return;
    }
    
    const tempShiftId = 'temp-' + Date.now(); 
    const defaultShiftName = shiftsForWache[0]; 

    try {
        const shiftRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", tempShiftId);
        
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

        const oldRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", oldShiftId);
        const newRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", newShiftName);
        
        // 1. Prüfen, ob Zieldokument bereits existiert
        const newSnap = await getDoc(newRef);
        if (newSnap.exists()) {
            alert(`Die Schicht "${newShiftName}" existiert bereits an diesem Tag. Bitte wählen Sie eine andere Schicht oder löschen Sie die bestehende.`);
            return;
        }

        // 2. Daten des alten Shifts abrufen (wichtig für die Personal-Übernahme)
        const oldSnap = await getDoc(oldRef);
        const oldData = oldSnap.data() || { personal1: null, personal2: null };
        
        const dataToSet = {
            shiftName: newShiftName,
            isTemporary: false,
            // Personal übertragen
            personal1: oldData.personal1, 
            personal2: oldData.personal2,
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
    
    const name = nameInput.value.trim();
    const farbe = colorInput.value;
    
    const selectedQuals = Array.from(qualGroup.querySelectorAll('input[name="qual"]:checked')).map(el => el.value);

    if (!name) {
        alert("Bitte Name eingeben.");
        return;
    }
    
    closePersonnelPopup();

    const personalData = {
        name: name,
        qualifikationen: selectedQuals,
        farbe: farbe
    };

    const updateField = `personal${slotIndex}`;

    try {
        const shiftRef = doc(db, "whiteboard", wacheId, "tage", dayId, "schichten", shiftId);
        
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
    isOVD = currentWache === "OVD";

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

    if (!isOVD) {
        addDayBtn.classList.remove('hidden');
    } else {
        ovdMessage.classList.remove('hidden');
    }
    
    listenForDays();
});

addDayBtn.addEventListener("click", openDatePopup);

/**
 * Allgemeine Hilfsfunktion zum robusten Parsen von DD.MM.YYYY
 */
const parseGermanDateRobust = (dayId) => {
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
    const daysColRef = collection(db, "whiteboard", currentWache, "tage");
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
                const idA = a.id.split('-')[1]; // dayId
                const idB = b.id.split('-')[1]; // dayId
                
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
        
        const wacheInfo = wacheId ? `<span class="wache-info">(${wacheId.replace('RW_', 'RW ').replace('KTW_', 'KTW ')})</span>` : '';
        
        const deleteDayBtn = `<button class="control-btn delete-day-btn" onclick="deleteDay('${dayId}', '${actualWacheId}')" title="Tag löschen">🗑️</button>`;
        
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
    const shiftsColRef = collection(db, "whiteboard", wacheId, "tage", dayId, "schichten");
    const q = query(shiftsColRef); 

    onSnapshot(q, (snapshot) => {
        containerElement.innerHTML = ''; 
        
        snapshot.forEach(docSnap => {
            const shiftId = docSnap.id; 
            const shiftData = docSnap.data();
            
            const isFullyManned = !!shiftData.personal1 && !!shiftData.personal2;
            
            // Verwendet den globalen Zustand 'isOVD'
            if (isOVD && isFullyManned) { 
                return; 
            }
            
            renderShiftRow(dayId, shiftId, shiftData, containerElement, wacheId);
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
    const isSlot1Manned = !!data.personal1;
    const isSlot2Manned = !!data.personal2;
    
    let mannedStatusClass = 'unmanned'; 
    if (isSlot1Manned && isSlot2Manned) {
        mannedStatusClass = 'fully-manned'; 
    } 

    const row = document.createElement('div');
    row.id = `shift-${dayId}-${shiftId}-${wacheId}`; 
    row.className = `shift-row ${mannedStatusClass}`;
    
    const shiftsToUse = WACHEN_SCHICHTEN[wacheId] || WACHEN_SCHICHTEN[currentWache];
    
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
    
    const deleteShiftBtn = `<button class="control-btn delete-shift-btn" onclick="deleteShift('${dayId}', '${shiftId}', '${wacheId}')" title="Schicht löschen">🗑️</button>`;

    row.innerHTML = `
        <select class="shift-select" ${selectDisabled} data-day-id="${dayId}" data-old-shift-id="${shiftId}" data-wache-id="${wacheId}">
            ${shiftOptions}
        </select>
        <div class="personnel-slot">
            ${renderPersonnelSlot(dayId, shiftId, 1, data.personal1, wacheId)}
            ${renderPersonnelSlot(dayId, shiftId, 2, data.personal2, wacheId)}
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
}

/**
 * Rendert einen Personal-Slot (Label).
 */
function renderPersonnelSlot(dayId, shiftId, slotIndex, personalData, wacheId) {
    const dataWacheId = wacheId || currentWache;
    const isTemporary = shiftId.startsWith('temp-');

    if (personalData) {
        const quals = personalData.qualifikationen.join('/');
        const text = `${personalData.name} (${quals})`;
        const color = personalData.farbe || '#ffffff';
        
        const encodedData = encodeURIComponent(JSON.stringify(personalData));
        
        if (isTemporary) {
             return `<div class="personnel-label unassigned">Schicht noch nicht ausgewählt</div>`;
        }

        return `
            <div 
                class="personnel-label assigned" 
                style="background-color: ${color} !important;" 
                title="Klicken zum Bearbeiten"
                onclick="openPersonnelPopup('${dayId}', '${shiftId}', ${slotIndex}, JSON.parse(decodeURIComponent('${encodedData}')), '${dataWacheId}')"
            >
                ${text} 
                <span class="remove-btn" onclick="event.stopPropagation(); removePersonnel('${dayId}', '${shiftId}', ${slotIndex}, '${dataWacheId}');" title="Personal entfernen">🗑️</span>
            </div>
        `;
    } else {
         if (isTemporary) {
            return `<div class="personnel-label unassigned">Bitte Schicht auswählen</div>`;
        }

        return `
            <div 
                class="personnel-label unassigned" 
                onclick="openPersonnelPopup('${dayId}', '${shiftId}', ${slotIndex}, null, '${dataWacheId}')"
            >
                Personal ${slotIndex} eintragen
            </div>
        `;
    }
}


function listenForOVDSummary() {
    const wachenToQuery = Object.keys(WACHEN_SCHICHTEN).filter(w => w !== "OVD" && w !== "default");
    
    let activeWacheListeners = 0;
    daysArea.innerHTML = ''; 

    const dayDocsMap = new Map(); 

    wachenToQuery.forEach(wache => {
        activeWacheListeners++;
        const daysColRef = collection(db, "whiteboard", wache, "tage");
        // Sortierung auf den Zeitstempel umgestellt
        const q = query(daysColRef, orderBy("timestamp", "asc")); 

        onSnapshot(q, (snapshot) => {
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
        const daysColRef = collection(db, "whiteboard", wache, "tage");
        const daySnap = await getDocs(daysColRef); 
        
        for (const dayDoc of daySnap.docs) {
            const dayId = dayDoc.id;
            const dayData = dayDoc.data();
            
            const shiftsColRef = collection(db, "whiteboard", wache, "tage", dayId, "schichten");
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


// Initialer Start beim Laden (setzt auf 'default')
document.addEventListener("DOMContentLoaded", () => {
    wacheSelect.value = "default";
    
    // Event Listener für den neuen Button anhängen
    if (showYellowListBtn) {
        showYellowListBtn.addEventListener("click", showYellowPersonnelList);
        // showYellowListBtn.classList.add('hidden'); // Der Button ist standardmäßig unsichtbar bis eine Wache gewählt wird
    }
});

// Popup-Funktionen global verfügbar machen
window.closeDatePopup = closeDatePopup;
window.closePersonnelPopup = closePersonnelPopup;
window.showYellowPersonnelList = showYellowPersonnelList; // Muss global sein