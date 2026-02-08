// Datei: telefonliste.js
// Telefonliste mit Bearbeitungsfunktionen

import { db } from "../../firebase-config.js";
import { 
    collection, 
    doc, 
    getDocs, 
    updateDoc,
    query,
    orderBy
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --- GLOBALE ZUSTÄNDE ---
let currentAuthData = null; 
let allMitarbeiter = [];
let canEditAll = false; // Admin und Rettungsdienstleiter können alles bearbeiten
let canEditPhoneOnly = false; // OVD kann nur Telefon/Handy bearbeiten

// --- DOM-ELEMENTE ---
const telefonlisteList = document.getElementById("telefonlisteList");
const telefonlisteSearch = document.getElementById("telefonlisteSearch");
const editModal = document.getElementById("editModal");
const closeEditModalBtn = document.getElementById("closeEditModal");
const closeEditModalXBtn = document.getElementById("closeEditModalX");
const editMitarbeiterForm = document.getElementById("editMitarbeiterForm");
const editMessage = document.getElementById("editMessage");
const editMitarbeiterId = document.getElementById("editMitarbeiterId");

// Feldset-Elemente für bedingte Anzeige
const editNachnameFieldset = document.getElementById("editNachnameFieldset");
const editVornameFieldset = document.getElementById("editVornameFieldset");
const editQualifikationFieldset = document.getElementById("editQualifikationFieldset");
const editFuehrerscheinFieldset = document.getElementById("editFuehrerscheinFieldset");

// --- 1. INITIALISIERUNG & HANDSHAKE ---

document.addEventListener('DOMContentLoaded', () => {
    const backBtn = document.getElementById("backBtn");
    if (backBtn) {
        backBtn.addEventListener("click", () => {
            const frame = window.parent?.document.getElementById("contentFrame");
            if (frame) {
                frame.src = "../../home.html";
            } else {
                window.location.href = "../../home.html";
            }
        });
    }

    // Funktion zum Schließen des Edit-Modals
    const closeEditModal = () => {
        editModal.style.display = "none";
        editMitarbeiterForm.reset();
        editMessage.textContent = "";
        editMessage.className = "";
        editMessage.style.display = "none";
    };

    closeEditModalBtn?.addEventListener("click", closeEditModal);
    closeEditModalXBtn?.addEventListener("click", closeEditModal);

    // Modal-Overlay-Klick zum Schließen
    editModal?.addEventListener("click", (e) => {
        if (e.target === editModal) {
            closeEditModal();
        }
    });

    // Suchfeld Event Listener
    telefonlisteSearch?.addEventListener("input", (e) => {
        renderTelefonliste(e.target.value.trim());
    });
});

window.addEventListener('message', async (event) => {
    if (event.data && event.data.type === 'AUTH_DATA') {
        currentAuthData = event.data.data;
        console.log("✅ Telefonliste - Auth-Daten empfangen:", currentAuthData);
        
        // Prüfe Berechtigung (nur Superadmin, Admin, Rettungsdienstleiter und OVD)
        const userRole = currentAuthData.role?.toLowerCase();
        const allowedRoles = ['superadmin', 'admin', 'rettungsdienstleiter', 'ovd'];
        
        if (!allowedRoles.includes(userRole)) {
            telefonlisteList.innerHTML = '<p>Sie benötigen entsprechende Rechte (Superadmin, Admin, Rettungsdienstleiter oder OVD), um die Telefonliste einzusehen.</p>';
            return;
        }
        
        // Setze Bearbeitungsrechte
        // Superadmin, Admin und Rettungsdienstleiter können alles bearbeiten
        canEditAll = ['admin', 'rettungsdienstleiter', 'superadmin'].includes(userRole);
        // OVD kann nur Telefonnummern und Handynummern bearbeiten
        canEditPhoneOnly = userRole === 'ovd';
        
        await loadMitarbeiter();
        renderTelefonliste();
    }
});

if (window.parent) {
    window.parent.postMessage({ type: 'IFRAME_READY' }, '*');
}

// --- 2. MITARBEITER LADEN ---

async function loadMitarbeiter() {
    try {
        if (!currentAuthData || !currentAuthData.companyId) {
            console.error("❌ Keine companyId verfügbar!");
            return;
        }

        console.log(`🔍 Lade Mitarbeiter für Telefonliste (companyId: ${currentAuthData.companyId})`);
        
        const mitarbeiterRef = collection(db, "kunden", currentAuthData.companyId, "mitarbeiter");
        const snap = await getDocs(mitarbeiterRef);
        
        allMitarbeiter = [];
        snap.forEach((docSnap) => {
            const data = docSnap.data() || {};
            // Nur aktive Mitarbeiter anzeigen
            if (data.active !== false) {
                allMitarbeiter.push({
                    id: docSnap.id,
                    ...data
                });
            }
        });
        
        // Sortiere nach Nachname (A-Z), dann Vorname (A-Z)
        allMitarbeiter.sort((a, b) => {
            const nachnameA = (a.nachname || "").trim().toLowerCase();
            const nachnameB = (b.nachname || "").trim().toLowerCase();
            if (nachnameA !== nachnameB) {
                return nachnameA.localeCompare(nachnameB, 'de');
            }
            const vornameA = (a.vorname || "").trim().toLowerCase();
            const vornameB = (b.vorname || "").trim().toLowerCase();
            return vornameA.localeCompare(vornameB, 'de');
        });
        
        console.log(`✅ ${allMitarbeiter.length} Mitarbeiter für Telefonliste geladen`);
    } catch (error) {
        console.error("❌ Fehler beim Laden der Mitarbeiter:", error);
        telefonlisteList.innerHTML = '<p style="color: red;">Fehler beim Laden der Telefonliste.</p>';
    }
}

// --- 3. TELEFONLISTE RENDERN ---

/**
 * Formatiert eine Telefonnummer als klickbaren tel: Link
 */
function formatPhoneLink(phoneNumber) {
    if (!phoneNumber || phoneNumber === "-") {
        return "-";
    }
    
    // Entferne alle Leerzeichen, Bindestriche und andere Zeichen für tel: Schema
    const cleanNumber = phoneNumber.replace(/[\s\-\(\)]/g, "");
    
    // Erstelle tel: Link mit Styling
    return `<a href="tel:${cleanNumber}" style="color: var(--primary-color); text-decoration: underline;">${phoneNumber}</a>`;
}

function renderTelefonliste(searchTerm = "") {
    if (!telefonlisteList) return;
    
    if (allMitarbeiter.length === 0) {
        telefonlisteList.innerHTML = '<p>Keine Mitarbeiter gefunden.</p>';
        return;
    }
    
    // Filtere nach Suchbegriff
    let filteredMitarbeiter = allMitarbeiter;
    if (searchTerm) {
        const term = searchTerm.toLowerCase();
        filteredMitarbeiter = allMitarbeiter.filter((m) => {
            const nachname = (m.nachname || "").toLowerCase();
            const vorname = (m.vorname || "").toLowerCase();
            const qualifikation = Array.isArray(m.qualifikation) 
                ? m.qualifikation.join(" ").toLowerCase() 
                : (m.qualifikation || "").toLowerCase();
            const telefon = (m.telefon || m.telefonnummer || "").toLowerCase();
            const handynummer = (m.handynummer || m.handy || "").toLowerCase();
            
            return nachname.includes(term) || 
                   vorname.includes(term) || 
                   qualifikation.includes(term) ||
                   telefon.includes(term) ||
                   handynummer.includes(term);
        });
    }
    
    if (filteredMitarbeiter.length === 0) {
        telefonlisteList.innerHTML = '<p>Keine Mitarbeiter gefunden, die dem Suchbegriff entsprechen.</p>';
        return;
    }
    
    // Erstelle Header
    let html = `
        <div class="list-item-header">
            <div>Nachname, Vorname</div>
            <div>Qualifikation</div>
            <div>Führerschein</div>
            <div>Telefonnummer</div>
            <div>Handynummer</div>
            <div></div>
        </div>
    `;
    
    // Erstelle Liste
    filteredMitarbeiter.forEach((m) => {
        const nachname = m.nachname || "";
        const vorname = m.vorname || "";
        const name = nachname && vorname 
            ? `${nachname}, ${vorname}` 
            : nachname || vorname || "Unbekannt";
        
        const qualifikation = Array.isArray(m.qualifikation) 
            ? m.qualifikation.join(" / ") 
            : (m.qualifikation || "-");
        
        const fuehrerschein = m.fuehrerschein || "-";
        const telefon = m.telefon || m.telefonnummer || "-";
        const handynummer = m.handynummer || m.handy || "-";
        
        // Formatiere Telefonnummern als klickbare Links
        const telefonDisplay = formatPhoneLink(telefon);
        const handynummerDisplay = formatPhoneLink(handynummer);
        
        // Bearbeiten-Button nur anzeigen, wenn Bearbeitungsrechte vorhanden
        const editButton = (canEditAll || canEditPhoneOnly) 
            ? `<button class="btn-small" onclick="openEditModal('${m.id}')">Bearbeiten</button>`
            : "";
        
        html += `
            <div class="list-item">
                <div data-label="Name">${name}</div>
                <div data-label="Qualifikation">${qualifikation}</div>
                <div data-label="Führerschein">${fuehrerschein}</div>
                <div data-label="Telefonnummer">${telefonDisplay}</div>
                <div data-label="Handynummer">${handynummerDisplay}</div>
                <div>${editButton}</div>
            </div>
        `;
    });
    
    telefonlisteList.innerHTML = html;
}

// --- 4. BEARBEITUNGS-MODAL ---

window.openEditModal = async function(mitarbeiterId) {
    const m = allMitarbeiter.find((mm) => mm.id === mitarbeiterId);
    if (!m) {
        alert("Mitarbeiter nicht gefunden.");
        return;
    }
    
    // Setze Bearbeitungsrechte für Felder
    if (canEditAll) {
        // Admin/Rettungsdienstleiter: Alle Felder anzeigen
        editNachnameFieldset.style.display = "block";
        editVornameFieldset.style.display = "block";
        editQualifikationFieldset.style.display = "block";
        editFuehrerscheinFieldset.style.display = "block";
    } else if (canEditPhoneOnly) {
        // OVD: Nur Telefon/Handy anzeigen
        editNachnameFieldset.style.display = "none";
        editVornameFieldset.style.display = "none";
        editQualifikationFieldset.style.display = "none";
        editFuehrerscheinFieldset.style.display = "none";
    } else {
        // Keine Bearbeitungsrechte
        alert("Sie haben keine Berechtigung, Mitarbeiter zu bearbeiten.");
        return;
    }
    
    // Fülle Formular
    editMitarbeiterId.value = mitarbeiterId;
    
    if (canEditAll) {
        document.getElementById("editNachname").value = m.nachname || "";
        document.getElementById("editVorname").value = m.vorname || "";
        document.getElementById("editFuehrerschein").value = m.fuehrerschein || "";
        
        // Qualifikation (Radio Buttons)
        const qualifikation = Array.isArray(m.qualifikation) ? m.qualifikation[0] : (m.qualifikation || "");
        const qualifikationRadios = document.querySelectorAll('input[name="editQualifikation"]');
        qualifikationRadios.forEach(radio => {
            radio.checked = radio.value === qualifikation;
        });
    }
    
    document.getElementById("editTelefon").value = m.telefon || m.telefonnummer || "";
    document.getElementById("editHandynummer").value = m.handynummer || m.handy || "";
    
    editMessage.textContent = "";
    editMessage.className = "";
    editMessage.style.display = "none";
    
    editModal.style.display = "block";
};

// Formular-Submit Handler
editMitarbeiterForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    
    const mitarbeiterId = editMitarbeiterId.value;
    if (!mitarbeiterId) {
        showMessage("Fehler: Keine Mitarbeiter-ID gefunden.", "error");
        return;
    }
    
    try {
        const mitarbeiterRef = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", mitarbeiterId);
        const updateData = {};
        
        if (canEditAll) {
            // Admin/Rettungsdienstleiter: Alle Felder aktualisieren
            const nachname = document.getElementById("editNachname").value.trim();
            const vorname = document.getElementById("editVorname").value.trim();
            const fuehrerschein = document.getElementById("editFuehrerschein").value.trim();
            
            if (nachname) updateData.nachname = nachname;
            if (vorname) updateData.vorname = vorname;
            if (fuehrerschein) updateData.fuehrerschein = fuehrerschein;
            
            // Qualifikation (Radio Button)
            const selectedQualifikation = document.querySelector('input[name="editQualifikation"]:checked');
            if (selectedQualifikation) {
                updateData.qualifikation = selectedQualifikation.value;
            }
            
            // Name aktualisieren
            if (nachname || vorname) {
                updateData.name = vorname ? `${vorname} ${nachname}`.trim() : nachname.trim();
            }
        }
        
        // Telefonnummer und Handynummer (alle mit Bearbeitungsrechten)
        const telefon = document.getElementById("editTelefon").value.trim();
        const handynummer = document.getElementById("editHandynummer").value.trim();
        
        if (telefon) {
            updateData.telefon = telefon;
            updateData.telefonnummer = telefon; // Für Kompatibilität
        } else {
            updateData.telefon = null;
            updateData.telefonnummer = null;
        }
        
        if (handynummer) {
            updateData.handynummer = handynummer;
            updateData.handy = handynummer; // Für Kompatibilität
        } else {
            updateData.handynummer = null;
            updateData.handy = null;
        }
        
        await updateDoc(mitarbeiterRef, updateData);
        
        // Aktualisiere lokale Daten
        const index = allMitarbeiter.findIndex((m) => m.id === mitarbeiterId);
        if (index !== -1) {
            Object.assign(allMitarbeiter[index], updateData);
        }
        
        showMessage("Mitarbeiter erfolgreich aktualisiert.", "success");
        
        // Aktualisiere Liste
        renderTelefonliste(telefonlisteSearch?.value.trim() || "");
        
        // Modal nach kurzer Verzögerung schließen
        setTimeout(() => {
            editModal.style.display = "none";
            editMitarbeiterForm.reset();
        }, 1500);
        
    } catch (error) {
        console.error("❌ Fehler beim Aktualisieren des Mitarbeiters:", error);
        showMessage("Fehler beim Aktualisieren: " + error.message, "error");
    }
});

function showMessage(message, type) {
    editMessage.textContent = message;
    editMessage.className = type;
    editMessage.style.display = "block";
}

