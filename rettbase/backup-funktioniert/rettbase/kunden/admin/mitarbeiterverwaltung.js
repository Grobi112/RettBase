// Datei: mitarbeiterverwaltung.js
// Verwaltung der Mitarbeiter im Admin-Backend

import { db, auth } from "../../firebase-config.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-functions.js"; 
import { 
    collection, 
    collectionGroup,
    doc, 
    getDoc, 
    getDocs, 
    setDoc,
    deleteDoc,
    query,
    orderBy,
    where,
    serverTimestamp,
    deleteField
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import {
    createUserWithEmailAndPassword,
    updatePassword,
    signInWithEmailAndPassword,
    signOut
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

// --- GLOBALE ZUSTÄNDE ---
let currentAuthData = null; 
let allMitarbeiter = [];

// --- DOM-ELEMENTE ---
const mitarbeiterList = document.getElementById("mitarbeiterList");
const mitarbeiterSearch = document.getElementById("mitarbeiterSearch");
const createMitarbeiterBtn = document.getElementById("createMitarbeiterBtn");

// Modal-Elemente (Neu anlegen)
const createModal = document.getElementById("createModal");
const closeCreateModalBtn = document.getElementById("closeCreateModal");
const closeCreateModalXBtn = document.getElementById("closeCreateModalX");
const newMitarbeiterForm = document.getElementById("newMitarbeiterForm");
const mitarbeiterMessage = document.getElementById("mitarbeiterMessage");

// Modal-Elemente (Bearbeiten)
const editModal = document.getElementById("editModal");
const closeEditModalBtn = document.getElementById("closeEditModal");
const closeEditModalXBtn = document.getElementById("closeEditModalX");
const editMitarbeiterForm = document.getElementById("editMitarbeiterForm");
const editMessage = document.getElementById("editMessage");
const editMitarbeiterId = document.getElementById("editMitarbeiterId");

// --- 1. INITIALISIERUNG & HANDSHAKE ---

// Zurück-Button Event Listener
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

    // Funktion zum Schließen des Create-Modals
    const closeCreateModal = () => {
        createModal.style.display = "none";
        newMitarbeiterForm.reset();
        mitarbeiterMessage.textContent = "";
        // Reset Select-Farben
        const roleSelect = document.getElementById("role");
        const activeSelect = document.getElementById("active");
        if (roleSelect) roleSelect.style.color = "#9ca3af";
        if (activeSelect) activeSelect.style.color = "#9ca3af";
    };

    // Modal-Event-Listener
    closeCreateModalBtn?.addEventListener("click", closeCreateModal);
    closeCreateModalXBtn?.addEventListener("click", closeCreateModal);

    // Funktion zum Schließen des Edit-Modals
    const closeEditModal = () => {
        editModal.style.display = "none";
        editMitarbeiterForm.reset();
        editMessage.textContent = "";
        // Reset Select-Farben
        const editRoleSelect = document.getElementById("editRole");
        const editActiveSelect = document.getElementById("editActive");
        if (editRoleSelect) editRoleSelect.style.color = "#9ca3af";
        if (editActiveSelect) editActiveSelect.style.color = "#9ca3af";
    };

    closeEditModalBtn?.addEventListener("click", closeEditModal);
    closeEditModalXBtn?.addEventListener("click", closeEditModal);
    
    // Password Toggle für "Neuen Mitarbeiter anlegen"
    const passwordToggle = document.getElementById("passwordToggle");
    const passwordInput = document.getElementById("password");
    const eyeIcon = passwordToggle?.querySelector("#eyeIcon");
    
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

    // Modal-Overlay-Klick zum Schließen
    createModal?.addEventListener("click", (e) => {
        if (e.target === createModal) {
            createModal.style.display = "none";
            newMitarbeiterForm.reset();
            mitarbeiterMessage.textContent = "";
            // Reset Select-Farben
            const roleSelect = document.getElementById("role");
            const activeSelect = document.getElementById("active");
            if (roleSelect) roleSelect.style.color = "#9ca3af";
            if (activeSelect) activeSelect.style.color = "#9ca3af";
        }
    });

    editModal?.addEventListener("click", (e) => {
        if (e.target === editModal) {
            editModal.style.display = "none";
            editMitarbeiterForm.reset();
            editMessage.textContent = "";
            // Reset Select-Farben
            const editRoleSelect = document.getElementById("editRole");
            const editActiveSelect = document.getElementById("editActive");
            if (editRoleSelect) editRoleSelect.style.color = "#9ca3af";
            if (editActiveSelect) editActiveSelect.style.color = "#9ca3af";
        }
    });

    // Suchfeld Event Listener
    mitarbeiterSearch?.addEventListener("input", (e) => {
        renderMitarbeiterList(e.target.value.trim());
    });

    // Button Event Listener
    createMitarbeiterBtn?.addEventListener("click", () => {
        createModal.style.display = "flex";
        // Reset Select-Farben beim Öffnen
        setTimeout(() => {
            const roleSelect = document.getElementById("role");
            const activeSelect = document.getElementById("active");
            if (roleSelect) roleSelect.style.color = "#9ca3af";
            if (activeSelect) activeSelect.style.color = "#9ca3af";
            
            // Scroll zum Anfang des Formulars (Personalnummer)
            const modalBody = createModal.querySelector(".modal-body");
            if (modalBody) {
                modalBody.scrollTop = 0;
            }
            // Alternativ: Scroll zum ersten Input-Feld
            const firstInput = document.getElementById("personalnummer");
            if (firstInput) {
                firstInput.scrollIntoView({ behavior: "smooth", block: "start" });
            }
        }, 100);
    });
    
    // Event Listener für Select-Änderungen (um Farbe zu aktualisieren)
    const roleSelect = document.getElementById("role");
    const activeSelect = document.getElementById("active");
    roleSelect?.addEventListener("change", function() {
        this.style.color = this.value ? "var(--text-color)" : "#9ca3af";
    });
    activeSelect?.addEventListener("change", function() {
        this.style.color = "var(--text-color)";
    });
    
    const editRoleSelect = document.getElementById("editRole");
    const editActiveSelect = document.getElementById("editActive");
    editRoleSelect?.addEventListener("change", function() {
        this.style.color = this.value ? "var(--text-color)" : "#9ca3af";
    });
    editActiveSelect?.addEventListener("change", function() {
        this.style.color = "var(--text-color)";
    });
});

window.addEventListener('message', async (event) => {
    if (event.data && event.data.type === 'AUTH_DATA') {
        currentAuthData = event.data.data;
        console.log("✅ Mitarbeiterverwaltung - Auth-Daten empfangen:", currentAuthData);
        
        // Prüfe Berechtigung (Superadmin, Admin oder Rettungsdienstleiter)
        if (['superadmin', 'admin', 'rettungsdienstleiter'].includes(currentAuthData.role)) {
            await loadMitarbeiter();
            renderMitarbeiterList();
        } else {
            mitarbeiterList.innerHTML = '<p>Sie benötigen entsprechende Rechte (Superadmin, Admin oder Rettungsdienstleiter), um Mitarbeiter zu verwalten.</p>';
            if (createMitarbeiterBtn) createMitarbeiterBtn.style.display = "none";
        }
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

        console.log(`🔍 Lade Mitarbeiter für companyId: ${currentAuthData.companyId}`);
        
        const mitarbeiterRef = collection(db, "kunden", currentAuthData.companyId, "mitarbeiter");
        // ⚠️ WICHTIG: Lade alle Mitarbeiter OHNE orderBy, da orderBy Dokumente ohne das Feld ausschließt
        // Wir sortieren dann manuell, um sicherzustellen, dass ALLE Mitarbeiter geladen werden
        const snap = await getDocs(mitarbeiterRef);
        
        console.log(`📊 Firestore Query Ergebnis: ${snap.docs.length} Dokumente gefunden`);
        
        // Debug: Prüfe ob es ein Problem mit der Collection gibt
        if (snap.empty) {
            console.warn(`⚠️ Keine Mitarbeiter in kunden/${currentAuthData.companyId}/mitarbeiter gefunden!`);
        }
        
        // Debug: Suche speziell nach "Thomas Biber" direkt in Firestore
        console.log(`🔍 Suche direkt in Firestore nach "Thomas Biber"...`);
        try {
            // Suche nach vorname "Thomas" in der aktuellen companyId
            const thomasQuery = query(mitarbeiterRef, where("vorname", "==", "Thomas"));
            const thomasSnap = await getDocs(thomasQuery);
            console.log(`🔍 Mitarbeiter mit vorname "Thomas" gefunden (${currentAuthData.companyId}): ${thomasSnap.docs.length}`);
            thomasSnap.docs.forEach(doc => {
                const data = doc.data();
                console.log(`  - ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}, Email: ${data.email || "keine"}, Active: ${data.active}`);
            });
            
            // Suche nach nachname "Biber" in der aktuellen companyId
            const biberQuery = query(mitarbeiterRef, where("nachname", "==", "Biber"));
            const biberSnap = await getDocs(biberQuery);
            console.log(`🔍 Mitarbeiter mit nachname "Biber" gefunden (${currentAuthData.companyId}): ${biberSnap.docs.length}`);
            biberSnap.docs.forEach(doc => {
                const data = doc.data();
                console.log(`  - ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}, Email: ${data.email || "keine"}, Active: ${data.active}`);
            });
            
            // ⚠️ WICHTIG: Suche auch in ALLEN anderen companyIds (Collection Group Query)
            console.log(`🔍 Suche nach "Thomas Biber" in ALLEN Firmen (Collection Group Query)...`);
            try {
                const allMitarbeiterGroup = collectionGroup(db, "mitarbeiter");
                
                // Suche nach vorname "Thomas" in allen Firmen
                const thomasGroupQuery = query(allMitarbeiterGroup, where("vorname", "==", "Thomas"));
                const thomasGroupSnap = await getDocs(thomasGroupQuery);
                console.log(`🔍 Mitarbeiter mit vorname "Thomas" in ALLEN Firmen gefunden: ${thomasGroupSnap.docs.length}`);
                thomasGroupSnap.docs.forEach(doc => {
                    const data = doc.data();
                    const pathParts = doc.ref.path.split("/");
                    const companyId = pathParts[1]; // kunden/{companyId}/mitarbeiter/{id}
                    console.log(`  - Firma: ${companyId}, ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}, Email: ${data.email || "keine"}, Active: ${data.active}`);
                });
                
                // Suche nach nachname "Biber" in allen Firmen
                const biberGroupQuery = query(allMitarbeiterGroup, where("nachname", "==", "Biber"));
                const biberGroupSnap = await getDocs(biberGroupQuery);
                console.log(`🔍 Mitarbeiter mit nachname "Biber" in ALLEN Firmen gefunden: ${biberGroupSnap.docs.length}`);
                biberGroupSnap.docs.forEach(doc => {
                    const data = doc.data();
                    const pathParts = doc.ref.path.split("/");
                    const companyId = pathParts[1]; // kunden/{companyId}/mitarbeiter/{id}
                    console.log(`  - Firma: ${companyId}, ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}, Email: ${data.email || "keine"}, Active: ${data.active}`);
                });
            } catch (groupError) {
                console.error("Fehler bei Collection Group Query (möglicherweise fehlende Berechtigungen):", groupError);
            }
        } catch (searchError) {
            console.error("Fehler bei direkter Suche in Firestore:", searchError);
            // Möglicherweise fehlt ein Index - das ist ok, wir laden trotzdem alle
        }
        
        allMitarbeiter = snap.docs.map((d) => {
            const data = d.data();
            return {
                id: d.id,
                ...data
            };
        });
        
        // Debug: Zeige ALLE geladenen Mitarbeiter mit vollständigen Daten
        console.log(`📋 Alle geladenen Mitarbeiter (vor Sortierung):`, allMitarbeiter.length);
        allMitarbeiter.forEach((m, index) => {
            console.log(`  [${index}] ID: ${m.id}, Name: "${m.nachname || "kein nachname"}, ${m.vorname || "kein vorname"}", Email: ${m.email || "keine"}, UID: ${m.uid || "keine"}, Active: ${m.active !== false}`);
        });
        
        // Sortiere manuell nach nachname A-Z (Dokumente ohne nachname kommen ans Ende)
        allMitarbeiter.sort((a, b) => {
            const nachnameA = (a.nachname || "").toLowerCase().trim();
            const nachnameB = (b.nachname || "").toLowerCase().trim();
            
            // Wenn beide einen Nachnamen haben, sortiere nach Nachname (A-Z)
            if (nachnameA && nachnameB) {
                const compare = nachnameA.localeCompare(nachnameB, 'de', { sensitivity: 'base' });
                // Wenn Nachnamen gleich sind, sortiere nach Vorname
                if (compare === 0) {
                    const vornameA = (a.vorname || "").toLowerCase().trim();
                    const vornameB = (b.vorname || "").toLowerCase().trim();
                    return vornameA.localeCompare(vornameB, 'de', { sensitivity: 'base' });
                }
                return compare;
            }
            
            // Mitarbeiter mit Nachname kommen vor Mitarbeitern ohne Nachname
            if (nachnameA) return -1;
            if (nachnameB) return 1;
            
            // Wenn beide keinen nachname haben, sortiere nach vorname
            const vornameA = (a.vorname || "").toLowerCase().trim();
            const vornameB = (b.vorname || "").toLowerCase().trim();
            if (vornameA && vornameB) return vornameA.localeCompare(vornameB, 'de', { sensitivity: 'base' });
            if (vornameA) return -1;
            if (vornameB) return 1;
            return 0;
        });
        
        console.log(`✅ ${allMitarbeiter.length} Mitarbeiter geladen`);
        // Debug: Zeige alle Mitarbeiter mit Email und Passwort
        const mitarbeiterMitEmail = allMitarbeiter.filter(m => m.email && !m.email.endsWith(".rettbase.de"));
        console.log(`📧 Mitarbeiter mit echter E-Mail: ${mitarbeiterMitEmail.length}`);
        mitarbeiterMitEmail.forEach(m => {
            console.log(`  - ${m.nachname || "kein nachname"}, ${m.vorname || "kein vorname"} (${m.email}) - ID: ${m.id}, UID: ${m.uid || "keine"}`);
        });
        
        // Debug: Suche speziell nach "Thomas Biber" (verschiedene Varianten)
        const thomasBiber = allMitarbeiter.find(m => {
            const vorname = (m.vorname || "").toLowerCase().trim();
            const nachname = (m.nachname || "").toLowerCase().trim();
            return (vorname.includes("thomas") && nachname.includes("biber")) ||
                   (vorname === "thomas" && nachname === "biber") ||
                   (nachname === "biber" && vorname === "thomas");
        });
        if (thomasBiber) {
            console.log(`🔍 ✅ Thomas Biber GEFUNDEN:`, {
                id: thomasBiber.id,
                vorname: thomasBiber.vorname,
                nachname: thomasBiber.nachname,
                email: thomasBiber.email,
                uid: thomasBiber.uid,
                active: thomasBiber.active,
                vollständigeDaten: thomasBiber
            });
        } else {
            console.log(`⚠️ Thomas Biber NICHT in allMitarbeiter gefunden!`);
            console.log(`🔍 Suche nach ähnlichen Namen...`);
            const ähnlicheNamen = allMitarbeiter.filter(m => {
                const vorname = (m.vorname || "").toLowerCase().trim();
                const nachname = (m.nachname || "").toLowerCase().trim();
                return vorname.includes("thomas") || nachname.includes("biber") || 
                       vorname.includes("biber") || nachname.includes("thomas");
            });
            if (ähnlicheNamen.length > 0) {
                console.log(`🔍 Ähnliche Namen gefunden:`, ähnlicheNamen.map(m => ({
                    id: m.id,
                    vorname: m.vorname,
                    nachname: m.nachname
                })));
            }
        }
    } catch (error) {
        console.error("❌ Fehler beim Laden der Mitarbeiter:", error);
        allMitarbeiter = [];
    }
}

// --- 3. MITARBEITER LISTE RENDERN ---

function renderMitarbeiterList(searchTerm = "") {
    if (!mitarbeiterList) {
        console.error("❌ mitarbeiterList Element nicht gefunden!");
        return;
    }

    const searchLower = searchTerm.toLowerCase().trim();
    const filtered = searchLower 
        ? allMitarbeiter.filter(m => {
            const fullName = `${m.vorname || ""} ${m.nachname || ""}`.toLowerCase();
            const email = (m.email || "").toLowerCase();
            const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(" ").toLowerCase() : "";
            return fullName.includes(searchLower) || email.includes(searchLower) || qualis.includes(searchLower);
        })
        : allMitarbeiter;

    mitarbeiterList.innerHTML = "";

    if (filtered.length === 0) {
        const emptyMessage = document.createElement("p");
        emptyMessage.style.padding = "20px";
        emptyMessage.style.textAlign = "center";
        emptyMessage.style.color = "#666";
        emptyMessage.textContent = allMitarbeiter.length === 0 
            ? "Noch keine Mitarbeiter vorhanden. Klicken Sie auf 'Neuen Mitarbeiter anlegen', um einen Mitarbeiter hinzuzufügen."
            : "Keine Mitarbeiter gefunden.";
        mitarbeiterList.appendChild(emptyMessage);
        return;
    }

    filtered.forEach((m) => {
        const row = document.createElement("div");
        row.className = "list-item";
        row.style.display = "flex";
        row.style.justifyContent = "space-between";
        row.style.alignItems = "center";
        row.style.padding = "12px 15px";
        row.style.borderBottom = "1px solid #eee";
        row.style.gap = "15px";

        // Name mit Qualifikation
        // ⚠️ WICHTIG: Format: "Nachname, Vorname (Qualifikation)"
        const nameDiv = document.createElement("div");
        nameDiv.style.flex = "1";
        nameDiv.style.minWidth = "200px";
        // Stelle sicher, dass nachname und vorname korrekt zugeordnet sind
        const nachname = (m.nachname || "").trim();
        const vorname = (m.vorname || "").trim();
        const qualis = Array.isArray(m.qualifikation) ? m.qualifikation.join(", ") : "";
        
        // Format: "Nachname, Vorname" oder nur "Nachname" oder nur "Vorname"
        let nameText;
        if (nachname && vorname) {
            nameText = `${nachname}, ${vorname}`;
        } else if (nachname) {
            nameText = nachname;
        } else if (vorname) {
            nameText = vorname;
        } else {
            nameText = "Unbekannt";
        }
        
        // Füge Qualifikation hinzu, falls vorhanden
        if (qualis) {
            nameText += ` (${qualis})`;
        }
        
        nameDiv.textContent = nameText;
        nameDiv.style.fontSize = "14px";

        // Button-Container
        const buttonContainer = document.createElement("div");
        buttonContainer.style.display = "flex";
        buttonContainer.style.gap = "8px";
        buttonContainer.style.flexShrink = "0";

        // Bearbeiten-Button
        const editBtn = document.createElement("button");
        editBtn.textContent = "Bearbeiten";
        editBtn.className = "btn-small";
        editBtn.addEventListener("click", () => openEditModal(m));

        // Löschen-Button
        const deleteBtn = document.createElement("button");
        deleteBtn.textContent = "Löschen";
        deleteBtn.className = "btn-small";
        deleteBtn.style.backgroundColor = "#ef4444";
        deleteBtn.style.color = "white";
        deleteBtn.style.border = "none";
        deleteBtn.addEventListener("click", () => handleDeleteMitarbeiter(m));

        buttonContainer.appendChild(editBtn);
        buttonContainer.appendChild(deleteBtn);

        // Status-Dropdown mit Icon
        const statusContainer = document.createElement("div");
        statusContainer.style.display = "flex";
        statusContainer.style.alignItems = "center";
        statusContainer.style.gap = "8px";
        statusContainer.style.flexShrink = "0";

        // Status-Icon
        const statusIcon = document.createElement("span");
        statusIcon.style.fontSize = "18px";
        statusIcon.style.lineHeight = "1";
        if (m.active !== false) {
            statusIcon.textContent = "✓";
            statusIcon.style.color = "#22c55e"; // Grün
        } else {
            statusIcon.textContent = "✗";
            statusIcon.style.color = "#ef4444"; // Rot
        }

        // Status-Dropdown
        const statusSelect = document.createElement("select");
        statusSelect.className = "status-select";
        statusSelect.style.padding = "6px 10px";
        statusSelect.style.borderRadius = "4px";
        statusSelect.style.border = "1px solid var(--border-color)";
        statusSelect.style.fontSize = "14px";
        statusSelect.style.cursor = "pointer";
        
        const optionActive = document.createElement("option");
        optionActive.value = "true";
        optionActive.textContent = "Aktiv";
        if (m.active !== false) optionActive.selected = true;
        
        const optionInactive = document.createElement("option");
        optionInactive.value = "false";
        optionInactive.textContent = "Inaktiv";
        if (m.active === false) optionInactive.selected = true;
        
        statusSelect.appendChild(optionActive);
        statusSelect.appendChild(optionInactive);
        
        statusSelect.addEventListener("change", async (e) => {
            const newStatus = e.target.value === "true";
            if (newStatus !== (m.active !== false)) {
                await toggleMitarbeiterActiveStatus(m, newStatus);
                // Update Icon
                if (newStatus) {
                    statusIcon.textContent = "✓";
                    statusIcon.style.color = "#22c55e";
                } else {
                    statusIcon.textContent = "✗";
                    statusIcon.style.color = "#ef4444";
                }
                m.active = newStatus;
            }
        });

        statusContainer.appendChild(statusIcon);
        statusContainer.appendChild(statusSelect);

        row.appendChild(nameDiv);
        row.appendChild(buttonContainer);
        row.appendChild(statusContainer);
        mitarbeiterList.appendChild(row);
    });
}

// --- 4. NEUEN MITARBEITER ANLEGEN ---

newMitarbeiterForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    mitarbeiterMessage.textContent = "Verarbeite Daten...";
    mitarbeiterMessage.style.color = "blue";

    if (!currentAuthData || !currentAuthData.companyId) {
        mitarbeiterMessage.textContent = "Fehler: Keine Berechtigung.";
        mitarbeiterMessage.style.color = "red";
        return;
    }

    const vorname = document.getElementById("vorname").value.trim();
    const nachname = document.getElementById("nachname").value.trim();

    if (!nachname) {
        mitarbeiterMessage.textContent = "Fehler: Bitte Name eingeben.";
        mitarbeiterMessage.style.color = "red";
        return;
    }

    try {
        // Parse Qualifikation (Radio-Button - nur eine Auswahl)
        const qualifikationRadio = document.querySelector("#qualifikationGroup input.qualification-radio:checked");
        const qualifikation = qualifikationRadio ? qualifikationRadio.value : null;
        const qualifikationen = qualifikation ? [qualifikation] : [];

        // Parse Angestelltenverhältnis (Checkboxen)
        const angestelltenverhaeltnisCheckboxes = document.querySelectorAll("#angestelltenverhaeltnisGroup input.angestelltenverhaeltnis-checkbox:checked");
        const angestelltenverhaeltnis = Array.from(angestelltenverhaeltnisCheckboxes).map(cb => cb.value);

        // Parse Geburtsdatum
        const geburtsdatumInput = document.getElementById("geburtsdatum").value;
        const geburtsdatum = geburtsdatumInput ? new Date(geburtsdatumInput) : null;

        const roleValue = document.getElementById("role").value.trim();
        const activeValue = document.getElementById("active").value;
        
        if (!roleValue || roleValue === "") {
            mitarbeiterMessage.textContent = "Fehler: Bitte eine Rolle auswählen.";
            mitarbeiterMessage.style.color = "red";
            return;
        }

        // Prüfe ob E-Mail oder Personalnummer vorhanden ist (muss VOR dem Erstellen von mitarbeiterData kommen)
        const personalnummerValue = document.getElementById("personalnummer").value.trim();
        const emailInput = document.getElementById("email");
        const emailValue = emailInput ? emailInput.value.trim() : "";
        
        // Validierung: 1. Personalnummer
        if (personalnummerValue) {
            const existingByPersonalnummer = allMitarbeiter.find(m => 
                m.personalnummer && m.personalnummer === personalnummerValue
            );
            if (existingByPersonalnummer) {
                mitarbeiterMessage.textContent = `Fehler: Ein Mitarbeiter mit der Personalnummer "${personalnummerValue}" existiert bereits.`;
                mitarbeiterMessage.style.color = "red";
                return;
            }
        }
        
        // Validierung: 2. E-Mail
        if (emailValue && !emailValue.endsWith(".rettbase.de")) {
            // Prüfe auf doppelte echte E-Mail-Adressen (auch in anderen Collections)
            const existingByEmail = allMitarbeiter.find(m => 
                m.email && m.email === emailValue && !m.email.endsWith(".rettbase.de")
            );
            
            // Zusätzlich: Suche direkt in Firestore nach der E-Mail (auch in anderen Collections)
            if (!existingByEmail) {
                console.log(`🔍 Suche nach E-Mail "${emailValue}" in Firestore...`);
                try {
                    // Suche in der aktuellen companyId
                    const mitarbeiterRef = collection(db, "kunden", currentAuthData.companyId, "mitarbeiter");
                    const emailQuery = query(mitarbeiterRef, where("email", "==", emailValue));
                    const emailSnap = await getDocs(emailQuery);
                    
                    if (!emailSnap.empty) {
                        console.log(`⚠️ E-Mail "${emailValue}" in Firestore gefunden, aber nicht in allMitarbeiter!`);
                        emailSnap.docs.forEach(doc => {
                            const data = doc.data();
                            console.log(`  - Gefunden: ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}, Email: ${data.email}, Active: ${data.active}, Vollständige Daten:`, data);
                        });
                        mitarbeiterMessage.textContent = `Fehler: Ein Mitarbeiter mit der E-Mail-Adresse "${emailValue}" existiert bereits (ID: ${emailSnap.docs[0].id}), wird aber nicht in der Liste angezeigt. Bitte Seite neu laden.`;
                        mitarbeiterMessage.style.color = "red";
                        return;
                    }
                } catch (emailSearchError) {
                    console.error("Fehler bei E-Mail-Suche in Firestore:", emailSearchError);
                }
            }
            
            if (existingByEmail) {
                mitarbeiterMessage.textContent = `Fehler: Ein Mitarbeiter mit der E-Mail-Adresse "${emailValue}" existiert bereits.`;
                mitarbeiterMessage.style.color = "red";
                return;
            }
        }
        
        // Validierung: 3. Vorname + Nachname (nur wenn keine Personalnummer UND keine E-Mail vorhanden)
        if (!personalnummerValue && (!emailValue || emailValue.endsWith(".rettbase.de"))) {
            const existingByName = allMitarbeiter.find(m => 
                m.vorname && m.nachname && 
                m.vorname.trim().toLowerCase() === vorname.toLowerCase() && 
                m.nachname.trim().toLowerCase() === nachname.toLowerCase()
            );
            if (existingByName) {
                mitarbeiterMessage.textContent = `Fehler: Ein Mitarbeiter mit dem Namen "${vorname} ${nachname}" existiert bereits.`;
                mitarbeiterMessage.style.color = "red";
                return;
            }
        }
        
        // Passwort auslesen (nur wenn Email oder Personalnummer vorhanden ist)
        const password = document.getElementById("password").value.trim();
        let hasEmailOrPersonalnummer = personalnummerValue || emailValue;
        
        if (hasEmailOrPersonalnummer) {
            // Wenn Email oder Personalnummer vorhanden ist, ist Passwort erforderlich
            if (!password || password.length < 6) {
                mitarbeiterMessage.textContent = "Fehler: Passwort muss mindestens 6 Zeichen lang sein (erforderlich wenn Email oder Personalnummer vorhanden).";
                mitarbeiterMessage.style.color = "red";
                return;
            }
        }
        // Wenn weder Email noch Personalnummer vorhanden sind, ist Passwort nicht erforderlich
        
        // 🔥 WICHTIG: Bestimme Email für Firebase Auth (nur wenn Email oder Personalnummer vorhanden ist)
        // Wenn eine echte E-Mail vorhanden ist, verwende diese (auch wenn Personalnummer vorhanden ist)
        // Nur wenn keine echte E-Mail vorhanden ist, verwende die Pseudo-Email
        let email = null;
        if (hasEmailOrPersonalnummer) {
            if (emailValue && !emailValue.endsWith(".rettbase.de")) {
                // Echte E-Mail vorhanden - verwende diese für Firebase Auth
                email = emailValue;
            } else if (personalnummerValue) {
                // Keine echte E-Mail, aber Personalnummer vorhanden - verwende Pseudo-Email
                email = `${personalnummerValue}@${currentAuthData.companyId}.rettbase.de`;
            } else {
                email = emailValue; // Fallback
            }
        }

        const mitarbeiterData = {
            personalnummer: personalnummerValue || null,
            vorname: vorname || null,
            nachname,
            name: vorname ? `${vorname} ${nachname}`.trim() : nachname.trim(),
            geburtsdatum: geburtsdatum || null,
            strasse: document.getElementById("strasse").value.trim() || null,
            hausnummer: document.getElementById("hausnummer").value.trim() || null,
            plz: document.getElementById("plz").value.trim() || null,
            ort: document.getElementById("ort").value.trim() || null,
            telefon: document.getElementById("telefon").value.trim() || null,
            handynummer: document.getElementById("handynummer").value.trim() || null,
            qualifikation: qualifikationen.length > 0 ? qualifikationen : null,
            angestelltenverhaeltnis: angestelltenverhaeltnis.length > 0 ? angestelltenverhaeltnis : null,
            fuehrerschein: document.getElementById("fuehrerschein").value.trim() || null,
            role: roleValue || null,
            active: activeValue === "true",
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp()
        };
        
        // Setze Email/PseudoEmail in mitarbeiterData (nur wenn Email oder Personalnummer vorhanden ist)
        if (hasEmailOrPersonalnummer) {
            if (personalnummerValue) {
                // Wenn eine echte E-Mail vorhanden ist, verwende diese, sonst die Pseudo-Email
                if (emailValue && !emailValue.endsWith(".rettbase.de")) {
                    mitarbeiterData.email = emailValue; // Echte E-Mail
                    mitarbeiterData.pseudoEmail = `${personalnummerValue}@${currentAuthData.companyId}.rettbase.de`; // Pseudo-Email für Referenz
                } else {
                    mitarbeiterData.pseudoEmail = email; // Pseudo-Email
                    mitarbeiterData.email = email; // Auch als email setzen
                }
            } else {
                mitarbeiterData.email = email;
            }
        }
        
        // Update Select-Farben nach Auswahl
        const roleSelect = document.getElementById("role");
        if (roleSelect) roleSelect.style.color = roleValue ? "var(--text-color)" : "#9ca3af";
        const activeSelect = document.getElementById("active");
        if (activeSelect) activeSelect.style.color = "var(--text-color)";

        // Entferne null-Werte
        Object.keys(mitarbeiterData).forEach(key => {
            if (mitarbeiterData[key] === null) {
                delete mitarbeiterData[key];
            }
        });

        const mitarbeiterRef = collection(db, "kunden", currentAuthData.companyId, "mitarbeiter");
        const newDocRef = doc(mitarbeiterRef);
        
        // Erstelle Firebase Auth Account (nur wenn Email/Personalnummer und Passwort vorhanden sind)
        let uid = null;
        
        try {
            if (hasEmailOrPersonalnummer && password) {
                // ⚠️ WICHTIG: Speichere die aktuelle Admin-Session in localStorage VOR dem Erstellen eines neuen Accounts
                // createUserWithEmailAndPassword loggt automatisch den neuen Benutzer ein
                const currentAdminUser = auth.currentUser;
                if (!currentAdminUser || !currentAdminUser.email) {
                    mitarbeiterMessage.textContent = "Fehler: Keine aktive Admin-Session gefunden. Bitte melden Sie sich erneut an.";
                    mitarbeiterMessage.style.color = "red";
                    return;
                }
                const adminEmail = currentAdminUser.email;
                const adminUid = currentAdminUser.uid;
                
                // Erstelle Firebase Auth Account über Cloud Function (beendet nicht die aktuelle Session)
                const functions = getFunctions(undefined, "us-central1");
                const createMitarbeiterAuth = httpsCallable(functions, 'createMitarbeiterAuth');
                
                try {
                    const result = await createMitarbeiterAuth({ email, password });
                    uid = result.data.uid;
                    mitarbeiterData.uid = uid;
                    console.log(`✅ Firebase Auth Account erstellt über Cloud Function: ${email} (UID: ${uid})`);
                } catch (cloudFunctionError) {
                    console.error("Fehler beim Erstellen des Firebase Auth Accounts über Cloud Function:", cloudFunctionError);
                    
                    // Prüfe, ob die E-Mail bereits in Firebase Auth existiert
                    // ⚠️ WICHTIG: Firebase Auth ist global (nicht firmenspezifisch)
                    // Wenn ein Mitarbeiter bereits in Firma A existiert und in Firma B angelegt werden soll,
                    // kann kein neuer Firebase Auth Account erstellt werden (E-Mail bereits verwendet).
                    // ABER: Das Firestore-Dokument kann trotzdem in Firma B erstellt werden,
                    // indem die UID aus dem bestehenden Auth Account verwendet wird.
                    // Dies ermöglicht es, dass derselbe Mitarbeiter in mehreren Firmen existieren kann.
                    if (cloudFunctionError.message && cloudFunctionError.message.includes("already in use")) {
                        console.log(`⚠️ E-Mail "${email}" existiert bereits in Firebase Auth!`);
                        console.log(`💡 Dies ist normal, wenn der Mitarbeiter bereits in einer anderen Firma existiert.`);
                        console.log(`🔍 Versuche, die UID für diese E-Mail abzurufen...`);
                        
                        try {
                            // Rufe die UID für diese E-Mail ab
                            const functions = getFunctions();
                            const getUserUidByEmail = httpsCallable(functions, 'getUserUidByEmail');
                            const uidResult = await getUserUidByEmail({ email });
                            
                            if (uidResult.data && uidResult.data.exists) {
                                uid = uidResult.data.uid;
                                mitarbeiterData.uid = uid;
                                console.log(`✅ UID für "${email}" abgerufen: ${uid}`);
                                console.log(`💡 Das Firestore-Dokument wird mit dieser UID in Firma "${currentAuthData.companyId}" erstellt.`);
                                // Setze hasEmailOrPersonalnummer auf true, damit das Firestore-Dokument erstellt wird
                                hasEmailOrPersonalnummer = true;
                            } else {
                                throw new Error("E-Mail existiert nicht in Firebase Auth (unerwarteter Fehler)");
                            }
                        } catch (uidError) {
                            console.error("Fehler beim Abrufen der UID:", uidError);
                            throw cloudFunctionError; // Wirf den ursprünglichen Fehler
                        }
                    } else if (cloudFunctionError.code === 'functions/not-found' || cloudFunctionError.code === 'functions/unavailable') {
                        console.log("⚠️ Cloud Function nicht verfügbar, verwende Fallback-Methode");
                        // ⚠️ WICHTIG: Speichere Admin-Daten in localStorage für Wiederherstellung nach Neuladen
                        localStorage.setItem('admin_restore_email', adminEmail);
                        localStorage.setItem('admin_restore_uid', adminUid);
                        console.log(`📋 Admin-Session in localStorage gespeichert: ${adminEmail} (UID: ${adminUid})`);
                        
                        const userCredential = await createUserWithEmailAndPassword(auth, email, password);
                        uid = userCredential.user.uid;
                        mitarbeiterData.uid = uid;
                        console.log(`✅ Firebase Auth Account erstellt (Fallback): ${email} (UID: ${uid})`);
                        
                        // Melde den neuen Benutzer sofort wieder ab, damit der Admin wieder eingeloggt werden kann
                        await signOut(auth);
                        console.log("✅ Neuer Benutzer abgemeldet, Admin-Session wird wiederhergestellt");
                    } else {
                        throw cloudFunctionError;
                    }
                }
            } else {
                console.log("ℹ️ Kein Firebase Auth Account erstellt (keine Email/Personalnummer oder kein Passwort)");
            }
        } catch (error) {
            // Lösche localStorage-Daten bei Fehler
            localStorage.removeItem('admin_restore_email');
            localStorage.removeItem('admin_restore_uid');
            
            console.error("Fehler beim Erstellen des Firebase Auth Accounts:", error);
            if (error.code === "auth/email-already-in-use") {
                console.log(`⚠️ E-Mail "${email}" existiert bereits in Firebase Auth, aber möglicherweise nicht in Firestore!`);
                console.log(`🔍 Suche nach vorhandenem Firebase Auth Account...`);
                
                // Versuche, den vorhandenen Firebase Auth Account zu finden
                // Da wir keinen direkten Zugriff auf Firebase Admin SDK haben, müssen wir versuchen,
                // den Benutzer einzuloggen, um die UID zu erhalten
                try {
                    // Versuche, den Benutzer mit einem Dummy-Passwort einzuloggen (wird fehlschlagen, aber gibt uns die UID)
                    // ABER: Das funktioniert nicht, da wir das Passwort nicht kennen
                    // Stattdessen: Prüfe, ob ein Firestore-Dokument mit dieser E-Mail existiert
                    const mitarbeiterRef = collection(db, "kunden", currentAuthData.companyId, "mitarbeiter");
                    const emailQuery = query(mitarbeiterRef, where("email", "==", email));
                    const emailSnap = await getDocs(emailQuery);
                    
                    if (emailSnap.empty) {
                        console.log(`⚠️ E-Mail "${email}" existiert in Firebase Auth, aber NICHT in Firestore!`);
                        console.log(`💡 Möglicherweise wurde das Firestore-Dokument gelöscht oder nie erstellt.`);
                        mitarbeiterMessage.textContent = `Fehler: Diese E-Mail/Personalnummer ist bereits in Firebase Auth registriert, aber das Mitarbeiter-Dokument existiert nicht in Firestore. Bitte kontaktieren Sie den Administrator.`;
                        mitarbeiterMessage.style.color = "red";
                        return;
                    } else {
                        console.log(`✅ E-Mail "${email}" existiert sowohl in Firebase Auth als auch in Firestore.`);
                        emailSnap.docs.forEach(doc => {
                            const data = doc.data();
                            console.log(`  - Gefunden: ID: ${doc.id}, Name: ${data.nachname || "kein nachname"}, ${data.vorname || "kein vorname"}`);
                        });
                        mitarbeiterMessage.textContent = `Fehler: Diese E-Mail/Personalnummer ist bereits registriert (ID: ${emailSnap.docs[0].id}). Bitte Seite neu laden.`;
                        mitarbeiterMessage.style.color = "red";
                        return;
                    }
                } catch (checkError) {
                    console.error("Fehler beim Prüfen der E-Mail in Firestore:", checkError);
                    mitarbeiterMessage.textContent = "Fehler: Diese E-Mail/Personalnummer ist bereits registriert.";
                    mitarbeiterMessage.style.color = "red";
                    return;
                }
            } else if (error.code === "auth/weak-password") {
                mitarbeiterMessage.textContent = "Fehler: Das Passwort ist zu schwach (mindestens 6 Zeichen).";
                mitarbeiterMessage.style.color = "red";
                return;
            } else {
                mitarbeiterMessage.textContent = `Fehler beim Erstellen des Accounts: ${error.message}`;
                mitarbeiterMessage.style.color = "red";
                return;
            }
        }
        
        await setDoc(newDocRef, mitarbeiterData);
        console.log(`💾 Mitarbeiter gespeichert mit ID: ${newDocRef.id}`);
        console.log(`💾 Mitarbeiter-Daten:`, JSON.stringify(mitarbeiterData, null, 2));
        
        // Debug: Verifiziere, dass der Mitarbeiter gespeichert wurde
        const verifySnap = await getDoc(newDocRef);
        if (verifySnap.exists()) {
            const savedData = verifySnap.data();
            console.log(`✅ Mitarbeiter verifiziert in Firestore:`, JSON.stringify(savedData, null, 2));
        } else {
            console.error(`❌ Mitarbeiter wurde NICHT in Firestore gespeichert!`);
        }
        
        // Wenn ein Firebase Auth Account erstellt wurde oder eine UID abgerufen wurde
        // (auch wenn kein neues Passwort gesetzt wurde, z.B. wenn der Account bereits existiert)
        if (uid) {
            // Zeige Erfolgsmeldung
            mitarbeiterMessage.textContent = `✅ Mitarbeiter '${mitarbeiterData.name}' erfolgreich angelegt.`;
            mitarbeiterMessage.style.color = "green";
            
            // ⚠️ WICHTIG: createUserWithEmailAndPassword loggt automatisch den neuen Benutzer ein
            // Wir müssen den neuen Benutzer ausloggen, aber die Admin-Session bleibt erhalten
            // durch die Firebase Auth Persistenz. Wir laden die Seite NICHT neu.
            console.log(`✅ Mitarbeiter-Daten gespeichert. Neuer Benutzer ist automatisch eingeloggt.`);
            console.log(`⚠️ WICHTIG: Die Admin-Session sollte durch Firebase Auth Persistenz erhalten bleiben.`);
            
            // Lösche localStorage-Daten (werden nicht mehr benötigt)
            localStorage.removeItem('admin_restore_email');
            localStorage.removeItem('admin_restore_uid');
            
            // Formular zurücksetzen und Liste aktualisieren (ohne Seite neu zu laden)
            newMitarbeiterForm.reset();
            await loadMitarbeiter();
            renderMitarbeiterList();
            
            // Modal nach 1.5 Sekunden schließen
            setTimeout(() => {
                createModal.style.display = "none";
                mitarbeiterMessage.textContent = "";
            }, 1500);
        } else {
            // Kein Firebase Auth Account erstellt - normale Erfolgsmeldung ohne Neuladen
            console.log(`✅ Mitarbeiter '${mitarbeiterData.name}' angelegt (ID: ${newDocRef.id}, ohne Firebase Auth Account)`);
            mitarbeiterMessage.textContent = `✅ Mitarbeiter '${mitarbeiterData.name}' erfolgreich angelegt.`;
            mitarbeiterMessage.style.color = "green";

            // Formular zurücksetzen und Liste aktualisieren
            newMitarbeiterForm.reset();
            await loadMitarbeiter();
            renderMitarbeiterList();

            // Modal nach 1.5 Sekunden schließen
            setTimeout(() => {
                createModal.style.display = "none";
                mitarbeiterMessage.textContent = "";
            }, 1500);
        }

    } catch (error) {
        console.error("Fehler beim Anlegen des Mitarbeiters:", error);
        mitarbeiterMessage.textContent = `Fehler: ${error.message}`;
        mitarbeiterMessage.style.color = "red";
    }
});

// --- 5. MITARBEITER BEARBEITEN ---

function openEditModal(mitarbeiter) {
    if (!editModal || !editMitarbeiterForm) return;

    // Debug: Zeige was geladen wird
    console.log(`📂 Öffne Bearbeitungs-Modal für Mitarbeiter ID: ${mitarbeiter.id}`);
    console.log(`📂 Geladene Mitarbeiter-Daten:`, JSON.stringify(mitarbeiter, null, 2));

    editMitarbeiterId.value = mitarbeiter.id;
    document.getElementById("editPersonalnummer").value = mitarbeiter.personalnummer || "";
    const editEmailInput = document.getElementById("editEmail");
    if (editEmailInput) {
        // Zeige E-Mail nur an, wenn es eine echte E-Mail ist (nicht mit .rettbase.de endend)
        if (mitarbeiter.email && !mitarbeiter.email.endsWith(".rettbase.de")) {
            editEmailInput.value = mitarbeiter.email;
        } else {
            editEmailInput.value = "";
        }
    }
    document.getElementById("editVorname").value = mitarbeiter.vorname || "";
    document.getElementById("editNachname").value = mitarbeiter.nachname || "";
    
    // Geburtsdatum
    if (mitarbeiter.geburtsdatum) {
        let geburtsdatum = mitarbeiter.geburtsdatum;
        if (geburtsdatum.toDate) {
            geburtsdatum = geburtsdatum.toDate();
        } else if (typeof geburtsdatum === "string") {
            geburtsdatum = new Date(geburtsdatum);
        }
        document.getElementById("editGeburtsdatum").value = geburtsdatum.toISOString().split("T")[0];
    } else {
        document.getElementById("editGeburtsdatum").value = "";
    }

    document.getElementById("editStrasse").value = mitarbeiter.strasse || "";
    document.getElementById("editHausnummer").value = mitarbeiter.hausnummer || "";
    document.getElementById("editPlz").value = mitarbeiter.plz || "";
    document.getElementById("editOrt").value = mitarbeiter.ort || "";
    document.getElementById("editTelefon").value = mitarbeiter.telefon || "";
    document.getElementById("editHandynummer").value = mitarbeiter.handynummer || "";
    document.getElementById("editFuehrerschein").value = mitarbeiter.fuehrerschein || "";

    // Qualifikation (Radio-Button - nur eine Auswahl)
    const qualis = Array.isArray(mitarbeiter.qualifikation) ? mitarbeiter.qualifikation : (mitarbeiter.qualifikation ? [mitarbeiter.qualifikation] : []);
    const selectedQuali = qualis.length > 0 ? qualis[0] : null;
    document.querySelectorAll("#editQualifikationGroup input.qualification-radio").forEach(radio => {
        radio.checked = radio.value === selectedQuali;
    });

    // Angestelltenverhältnis (Checkboxen)
    const av = Array.isArray(mitarbeiter.angestelltenverhaeltnis) ? mitarbeiter.angestelltenverhaeltnis : [];
    document.querySelectorAll("#editAngestelltenverhaeltnisGroup input.angestelltenverhaeltnis-checkbox").forEach(cb => {
        cb.checked = av.includes(cb.value);
    });

    // Rolle und Status - Setze Wert und ändere Textfarbe
    const editRoleSelect = document.getElementById("editRole");
    if (editRoleSelect) {
        editRoleSelect.value = mitarbeiter.role || "";
        editRoleSelect.style.color = editRoleSelect.value ? "var(--text-color)" : "#9ca3af";
    }
    
    const editActiveSelect = document.getElementById("editActive");
    if (editActiveSelect) {
        editActiveSelect.value = mitarbeiter.active !== false ? "true" : "false";
        editActiveSelect.style.color = "var(--text-color)";
    }

    // Passwort-Feld leeren (wird nicht vorausgefüllt)
    const editPasswordInput = document.getElementById("editPassword");
    if (editPasswordInput) {
        editPasswordInput.value = "";
    }

    editModal.style.display = "flex";
    editMessage.textContent = "";
}

editMitarbeiterForm?.addEventListener("submit", async (e) => {
    e.preventDefault();
    editMessage.textContent = "Verarbeite Daten...";
    editMessage.style.color = "blue";

    const id = editMitarbeiterId.value;
    if (!id) {
        editMessage.textContent = "Fehler: Keine Mitarbeiter-ID gefunden.";
        editMessage.style.color = "red";
        return;
    }

    const vorname = document.getElementById("editVorname").value.trim();
    const nachname = document.getElementById("editNachname").value.trim();

    if (!nachname) {
        editMessage.textContent = "Fehler: Bitte Name eingeben.";
        editMessage.style.color = "red";
        return;
    }

    try {
        // Prüfe ob E-Mail oder Personalnummer vorhanden ist
        const personalnummerValue = document.getElementById("editPersonalnummer").value.trim();
        const emailInput = document.getElementById("editEmail");
        const emailValue = emailInput ? emailInput.value.trim() : "";
        
        // Validierung: 1. Personalnummer (ausschließlich des aktuellen Mitarbeiters)
        if (personalnummerValue) {
            const existingByPersonalnummer = allMitarbeiter.find(m => 
                m.id !== id && m.personalnummer && m.personalnummer === personalnummerValue
            );
            if (existingByPersonalnummer) {
                editMessage.textContent = `Fehler: Ein Mitarbeiter mit der Personalnummer "${personalnummerValue}" existiert bereits.`;
                editMessage.style.color = "red";
                return;
            }
        }
        
        // Validierung: 2. E-Mail (ausschließlich des aktuellen Mitarbeiters)
        if (emailValue && !emailValue.endsWith(".rettbase.de")) {
            // Prüfe auf doppelte echte E-Mail-Adressen
            const existingByEmail = allMitarbeiter.find(m => 
                m.id !== id && m.email && m.email === emailValue && !m.email.endsWith(".rettbase.de")
            );
            if (existingByEmail) {
                editMessage.textContent = `Fehler: Ein Mitarbeiter mit der E-Mail-Adresse "${emailValue}" existiert bereits.`;
                editMessage.style.color = "red";
                return;
            }
        }
        
        // Validierung: 3. Vorname + Nachname (nur wenn keine Personalnummer UND keine E-Mail vorhanden, ausschließlich des aktuellen Mitarbeiters)
        if (!personalnummerValue && (!emailValue || emailValue.endsWith(".rettbase.de"))) {
            const existingByName = allMitarbeiter.find(m => 
                m.id !== id &&
                m.vorname && m.nachname && 
                m.vorname.trim().toLowerCase() === vorname.toLowerCase() && 
                m.nachname.trim().toLowerCase() === nachname.toLowerCase()
            );
            if (existingByName) {
                editMessage.textContent = `Fehler: Ein Mitarbeiter mit dem Namen "${vorname} ${nachname}" existiert bereits.`;
                editMessage.style.color = "red";
                return;
            }
        }
        
        // Parse Qualifikation (Radio-Button - nur eine Auswahl)
        const qualifikationRadio = document.querySelector("#editQualifikationGroup input.qualification-radio:checked");
        const qualifikation = qualifikationRadio ? qualifikationRadio.value : null;
        const qualifikationen = qualifikation ? [qualifikation] : [];

        // Parse Angestelltenverhältnis (Checkboxen)
        const angestelltenverhaeltnisCheckboxes = document.querySelectorAll("#editAngestelltenverhaeltnisGroup input.angestelltenverhaeltnis-checkbox:checked");
        const angestelltenverhaeltnis = Array.from(angestelltenverhaeltnisCheckboxes).map(cb => cb.value);

        // Parse Geburtsdatum
        const geburtsdatumInput = document.getElementById("editGeburtsdatum").value;
        const geburtsdatum = geburtsdatumInput ? new Date(geburtsdatumInput) : null;
        
        // 🔥 WICHTIG: Lade bestehende Daten ZUERST, um zu wissen, welche Felder gelöscht werden müssen
        const existingDocRef = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", id);
        const existingSnap = await getDoc(existingDocRef);
        const existingData = existingSnap.exists() ? existingSnap.data() : {};
        
        const mitarbeiterData = {
            vorname: vorname || null,
            nachname,
            name: vorname ? `${vorname} ${nachname}`.trim() : nachname.trim(),
            geburtsdatum: geburtsdatum || null,
            strasse: document.getElementById("editStrasse").value.trim() || null,
            hausnummer: document.getElementById("editHausnummer").value.trim() || null,
            plz: document.getElementById("editPlz").value.trim() || null,
            ort: document.getElementById("editOrt").value.trim() || null,
            telefon: document.getElementById("editTelefon").value.trim() || null,
            handynummer: document.getElementById("editHandynummer").value.trim() || null,
            qualifikation: qualifikationen.length > 0 ? qualifikationen : null,
            angestelltenverhaeltnis: angestelltenverhaeltnis.length > 0 ? angestelltenverhaeltnis : null,
            fuehrerschein: document.getElementById("editFuehrerschein").value.trim() || null,
            role: document.getElementById("editRole").value.trim() || null,
            active: document.getElementById("editActive").value === "true",
            updatedAt: serverTimestamp()
        };
        
        // Personalnummer und E-Mail/Pseudo-Email
        if (personalnummerValue) {
            const pseudoEmail = `${personalnummerValue}@${currentAuthData.companyId}.rettbase.de`;
            mitarbeiterData.personalnummer = personalnummerValue;
            mitarbeiterData.pseudoEmail = pseudoEmail;
            // Wenn eine echte E-Mail eingegeben wurde, verwende diese, sonst die Pseudo-Email
            if (emailValue && !emailValue.endsWith(".rettbase.de")) {
                mitarbeiterData.email = emailValue;
            } else {
                mitarbeiterData.email = pseudoEmail;
            }
        } else if (emailValue) {
            mitarbeiterData.email = emailValue;
            // Lösche personalnummer und pseudoEmail, wenn sie vorher vorhanden waren
            if (existingData.personalnummer) {
                mitarbeiterData.personalnummer = deleteField();
            }
            if (existingData.pseudoEmail) {
                mitarbeiterData.pseudoEmail = deleteField();
            }
        } else {
            // Weder Personalnummer noch E-Mail - lösche beide, wenn sie vorher vorhanden waren
            if (existingData.personalnummer) {
                mitarbeiterData.personalnummer = deleteField();
            }
            if (existingData.pseudoEmail) {
                mitarbeiterData.pseudoEmail = deleteField();
            }
            // E-Mail wird nicht gesetzt (bleibt wie sie ist, oder wird gelöscht, wenn sie eine Pseudo-Email war)
            if (existingData.email && existingData.email.endsWith(".rettbase.de")) {
                // Wenn die alte E-Mail eine Pseudo-Email war, lösche sie
                mitarbeiterData.email = deleteField();
            }
        }

        // Felder, die explizit gelöscht werden sollen, wenn sie leer sind, aber vorher einen Wert hatten
        const fieldsToDelete = ['strasse', 'hausnummer', 'plz', 'ort', 'telefon', 'handynummer'];
        fieldsToDelete.forEach(field => {
            // Wenn das Feld leer ist UND es vorher einen Wert hatte
            if ((mitarbeiterData[field] === null || mitarbeiterData[field] === '') 
                && existingData[field] !== undefined && existingData[field] !== null && existingData[field] !== '') {
                // Lösche das Feld explizit
                mitarbeiterData[field] = deleteField();
            } else if (mitarbeiterData[field] === null || mitarbeiterData[field] === '') {
                // Feld war leer und wird gelöscht (war vorher auch nicht vorhanden)
                delete mitarbeiterData[field];
            }
        });
        
        // Entferne null-Werte für andere Felder (behalte aber geburtsdatum)
        Object.keys(mitarbeiterData).forEach(key => {
            if (mitarbeiterData[key] === null && key !== "geburtsdatum") {
                delete mitarbeiterData[key];
            }
        });
        
        // Update Select-Farben nach Auswahl
        const editRoleSelect = document.getElementById("editRole");
        const editActiveSelect = document.getElementById("editActive");
        if (editRoleSelect) editRoleSelect.style.color = mitarbeiterData.role ? "var(--text-color)" : "#9ca3af";
        if (editActiveSelect) editActiveSelect.style.color = "var(--text-color)";

        // Prüfe ob Passwort gesetzt/geändert werden soll
        const newPassword = document.getElementById("editPassword") ? document.getElementById("editPassword").value.trim() : "";
        if (newPassword && newPassword.length >= 6) {
            // Lade bestehende Mitarbeiter-Daten, um UID und Email zu erhalten
            const mitarbeiterRefForPassword = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", id);
            const mitarbeiterSnap = await getDoc(mitarbeiterRefForPassword);
            
            if (mitarbeiterSnap.exists()) {
                const existingData = mitarbeiterSnap.data();
                const existingUid = existingData.uid;
                const existingEmail = existingData.email || existingData.pseudoEmail;
                
                // Bestimme neue Email (falls geändert) - verwende die bereits in mitarbeiterData gesetzte Email
                let email = mitarbeiterData.email || existingEmail;
                if (personalnummerValue) {
                    email = `${personalnummerValue}@${currentAuthData.companyId}.rettbase.de`;
                } else if (emailValue) {
                    email = emailValue;
                }
                
                // 🔥 WICHTIG: Aktualisiere mitarbeiterData.email mit der korrekten Email
                mitarbeiterData.email = email;
                if (personalnummerValue) {
                    mitarbeiterData.pseudoEmail = email;
                }
                
                if (!email) {
                    editMessage.textContent = "Fehler: E-Mail oder Personalnummer muss vorhanden sein, um Passwort zu setzen.";
                    editMessage.style.color = "red";
                    return;
                }
                
                // ⚠️ WICHTIG: Wenn bereits eine UID vorhanden ist, hat der Mitarbeiter bereits einen Account
                // Das Passwort wird über die Cloud Function aktualisiert
                if (existingUid) {
                    // Importiere Firebase Functions (dynamisch, falls noch nicht importiert)
                    let getFunctions, httpsCallable;
                    try {
                        const functionsModule = await import("https://www.gstatic.com/firebasejs/11.0.1/firebase-functions.js");
                        getFunctions = functionsModule.getFunctions;
                        httpsCallable = functionsModule.httpsCallable;
                    } catch (error) {
                        console.error("Fehler beim Laden von Firebase Functions:", error);
                        editMessage.textContent = "Fehler: Firebase Functions konnten nicht geladen werden.";
                        editMessage.style.color = "red";
                        return;
                    }
                    
                    const functions = getFunctions(undefined, "us-central1");
                    const updateMitarbeiterPasswordFunction = httpsCallable(functions, 'updateMitarbeiterPassword');
                    
                    try {
                        await updateMitarbeiterPasswordFunction({ uid: existingUid, newPassword: newPassword });
                        console.log(`✅ Passwort für Firebase Auth Account aktualisiert: ${existingUid}`);
                    } catch (error) {
                        console.error("❌ Fehler beim Aktualisieren des Passworts:", error);
                        editMessage.textContent = `Fehler beim Aktualisieren des Passworts: ${error.message || error.code || 'Unbekannter Fehler'}`;
                        editMessage.style.color = "red";
                        return;
                    }
                    // Fortsetzen mit normaler Aktualisierung (Passwort wurde bereits aktualisiert)
                } else {
                    // Mitarbeiter hat noch keinen Account - erstelle neuen Account
                    // ⚠️ WICHTIG: Speichere die aktuelle Admin-Session in localStorage VOR dem Erstellen
                    const currentAdminUser = auth.currentUser;
                    if (!currentAdminUser || !currentAdminUser.email) {
                        editMessage.textContent = "Fehler: Keine aktive Admin-Session gefunden. Bitte melden Sie sich erneut an.";
                        editMessage.style.color = "red";
                        return;
                    }
                    const adminEmail = currentAdminUser.email;
                    const adminUid = currentAdminUser.uid;
                    
                    // 🔥 KRITISCH: Speichere Admin-Daten in localStorage für Wiederherstellung nach Neuladen
                    localStorage.setItem('admin_restore_email', adminEmail);
                    localStorage.setItem('admin_restore_uid', adminUid);
                    console.log(`📋 Admin-Session in localStorage gespeichert: ${adminEmail} (UID: ${adminUid})`);
                    
                    try {
                        // ⚠️ WICHTIG: Dies loggt automatisch den neuen Benutzer ein!
                        const userCredential = await createUserWithEmailAndPassword(auth, email, newPassword);
                        const uid = userCredential.user.uid;
                        mitarbeiterData.uid = uid;
                        mitarbeiterData.email = email;
                        if (personalnummerValue) {
                            mitarbeiterData.pseudoEmail = email;
                        }
                        console.log(`✅ Firebase Auth Account erstellt: ${email} (UID: ${uid})`);
                        console.log(`⚠️ Neuer Benutzer wurde automatisch eingeloggt - wir müssen den Admin wieder einloggen`);
                    } catch (error) {
                        // Lösche localStorage-Daten bei Fehler
                        localStorage.removeItem('admin_restore_email');
                        localStorage.removeItem('admin_restore_uid');
                        
                        console.error("Fehler beim Erstellen des Firebase Auth Accounts:", error);
                        if (error.code === "auth/email-already-in-use") {
                            editMessage.textContent = "⚠️ Diese E-Mail/Personalnummer ist bereits in Firebase Auth registriert. Der Mitarbeiter kann sich bereits anmelden. Passwort-Änderungen müssen über das Profil des Benutzers erfolgen.";
                            editMessage.style.color = "orange";
                            // Kein Account erstellt - breche hier ab und setze normale Aktualisierung fort
                            // (Die normale Aktualisierung erfolgt weiter unten im Code)
                        } else {
                            editMessage.textContent = `Fehler beim Erstellen des Accounts: ${error.message}`;
                            editMessage.style.color = "red";
                            return;
                        }
                    }
                    
                    // Nur fortfahren, wenn Account erfolgreich erstellt wurde (uid vorhanden)
                    if (mitarbeiterData.uid) {
                        // ⚠️ KRITISCH: Speichere Daten zuerst
                        await setDoc(mitarbeiterRefForPassword, mitarbeiterData, { merge: true });
                        
                        // Zeige Erfolgsmeldung
                        editMessage.textContent = `✅ Mitarbeiter erfolgreich aktualisiert. Seite wird neu geladen...`;
                        editMessage.style.color = "green";
                        
                        // Warte kurz, damit der Benutzer die Erfolgsmeldung sieht
                        await new Promise(resolve => setTimeout(resolve, 1000));
                        
                        // Logge den neuen Benutzer aus und lade die Seite neu
                        // Dashboard.js wird die Admin-Session aus localStorage wiederherstellen
                        console.log(`✅ Mitarbeiter-Daten gespeichert. Logge neuen Benutzer aus...`);
                        await signOut(auth);
                        console.log(`✅ Neuer Benutzer ausgeloggt. Lade Seite neu...`);
                        
                        // Seite neu laden - Dashboard.js wird die Admin-Session aus localStorage wiederherstellen
                        window.location.reload();
                        return; // Wichtig: Nicht weiter ausführen, da die Seite neu geladen wird
                    }
                    // Wenn uid nicht vorhanden (email-already-in-use), wird die normale Aktualisierung weiter unten fortgesetzt
                }
            }
        }

        const mitarbeiterRef = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", id);
        
        // Debug: Zeige was gespeichert wird
        console.log(`💾 Speichere Mitarbeiter-Daten für ID: ${id}`);
        console.log(`💾 mitarbeiterData:`, JSON.stringify(mitarbeiterData, null, 2));
        console.log(`💾 Formular-Werte:`, {
            vorname: vorname,
            nachname: nachname,
            personalnummer: personalnummerValue,
            email: emailValue,
            strasse: document.getElementById("editStrasse").value.trim(),
            hausnummer: document.getElementById("editHausnummer").value.trim(),
            plz: document.getElementById("editPlz").value.trim(),
            ort: document.getElementById("editOrt").value.trim(),
            telefon: document.getElementById("editTelefon").value.trim(),
            handynummer: document.getElementById("editHandynummer").value.trim(),
            fuehrerschein: document.getElementById("editFuehrerschein").value.trim(),
            role: document.getElementById("editRole").value.trim(),
            active: document.getElementById("editActive").value === "true"
        });
        
        await setDoc(mitarbeiterRef, mitarbeiterData, { merge: true });
        
        // Debug: Prüfe ob Daten gespeichert wurden
        const verifySnap = await getDoc(mitarbeiterRef);
        if (verifySnap.exists()) {
            const savedData = verifySnap.data();
            console.log(`✅ Daten gespeichert. Verifiziert:`, JSON.stringify(savedData, null, 2));
            
            // Prüfe ob alle wichtigen Felder gespeichert wurden
            const importantFields = ['vorname', 'nachname', 'name', 'role', 'active', 'email'];
            importantFields.forEach(field => {
                if (mitarbeiterData[field] !== undefined && savedData[field] !== mitarbeiterData[field]) {
                    console.error(`❌ FEHLER: Feld '${field}' wurde nicht korrekt gespeichert! Erwartet: ${mitarbeiterData[field]}, Gespeichert: ${savedData[field]}`);
                }
            });
        } else {
            console.error(`❌ FEHLER: Daten wurden nicht gespeichert!`);
        }

        console.log(`✅ Mitarbeiter '${mitarbeiterData.name}' aktualisiert`);
        
        // Erstelle Erfolgsmeldung
        let successMessage = `✅ Mitarbeiter '${mitarbeiterData.name}' erfolgreich aktualisiert.`;
        if (newPassword && newPassword.length >= 6 && mitarbeiterData.uid) {
            successMessage += " Neues Passwort wurde gesetzt.";
        }
        editMessage.textContent = successMessage;
        editMessage.style.color = "green";

        await loadMitarbeiter();
        renderMitarbeiterList(mitarbeiterSearch?.value || "");

        // Modal nach 1.5 Sekunden schließen
        setTimeout(() => {
            editModal.style.display = "none";
            editMessage.textContent = "";
        }, 1500);

    } catch (error) {
        console.error("Fehler beim Aktualisieren des Mitarbeiters:", error);
        editMessage.textContent = `Fehler: ${error.message}`;
        editMessage.style.color = "red";
    }
});

// --- 6. MITARBEITER AKTIVIEREN/DEAKTIVIEREN ---

async function toggleMitarbeiterActiveStatus(mitarbeiter, newStatus) {
    try {
        const mitarbeiterRef = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", mitarbeiter.id);
        await setDoc(mitarbeiterRef, {
            active: newStatus,
            updatedAt: serverTimestamp()
        }, { merge: true });

        console.log(`✅ Mitarbeiter ${newStatus ? "aktiviert" : "deaktiviert"}`);
        await loadMitarbeiter();
        renderMitarbeiterList(mitarbeiterSearch?.value || "");
    } catch (error) {
        console.error("Fehler beim Ändern des Status:", error);
        alert(`Fehler: ${error.message}`);
    }
}

// Legacy-Funktion für Kompatibilität (falls noch verwendet)
async function toggleMitarbeiterActive(mitarbeiter) {
    if (!confirm(`Mitarbeiter "${mitarbeiter.vorname} ${mitarbeiter.nachname}" wirklich ${mitarbeiter.active !== false ? "deaktivieren" : "aktivieren"}?`)) {
        return;
    }
    await toggleMitarbeiterActiveStatus(mitarbeiter, !(mitarbeiter.active !== false));
}

// --- 7. MITARBEITER LÖSCHEN ---

async function handleDeleteMitarbeiter(mitarbeiter) {
    const mitarbeiterName = `${mitarbeiter.vorname || ""} ${mitarbeiter.nachname || ""}`.trim() || "Unbekannt";
    
    if (!confirm(`Möchten Sie den Mitarbeiter "${mitarbeiterName}" wirklich löschen?\n\nDies kann nicht rückgängig gemacht werden! Der Mitarbeiter wird vollständig aus der Datenbank entfernt.`)) {
        return;
    }

    try {
        // Importiere Firebase Functions (dynamisch, falls noch nicht importiert)
        let getFunctions, httpsCallable;
        try {
            const functionsModule = await import("https://www.gstatic.com/firebasejs/11.0.1/firebase-functions.js");
            getFunctions = functionsModule.getFunctions;
            httpsCallable = functionsModule.httpsCallable;
        } catch (error) {
            console.error("Fehler beim Laden von Firebase Functions:", error);
            throw new Error("Firebase Functions konnten nicht geladen werden");
        }

        const functions = getFunctions(undefined, "us-central1");
        const deleteMitarbeiterFunction = httpsCallable(functions, 'deleteMitarbeiter');

        const mitarbeiterRef = doc(db, "kunden", currentAuthData.companyId, "mitarbeiter", mitarbeiter.id);
        
        // 1. Lösche Firebase Auth Account (falls vorhanden)
        if (mitarbeiter.uid) {
            try {
                await deleteMitarbeiterFunction({ uid: mitarbeiter.uid });
                console.log(`✅ Firebase Auth Account gelöscht: ${mitarbeiter.uid}`);
            } catch (error) {
                console.error("Fehler beim Löschen des Firebase Auth Accounts:", error);
                // Weiter mit Firestore-Löschung, auch wenn Auth-Löschung fehlschlägt
                if (error.code !== 'functions/not-found') {
                    console.warn("⚠️ Auth Account konnte nicht gelöscht werden, aber Firestore-Dokument wird trotzdem gelöscht");
                }
            }
        }
        
        // 2. Lösche Firestore-Dokument
        await deleteDoc(mitarbeiterRef);
        console.log(`✅ Mitarbeiter-Dokument gelöscht: ${mitarbeiter.id}`);
        
        // 3. Aktualisiere Liste
        await loadMitarbeiter();
        renderMitarbeiterList(mitarbeiterSearch?.value || "");
        
        // Erfolgsmeldung
        alert(`✅ Mitarbeiter "${mitarbeiterName}" wurde erfolgreich gelöscht.`);
        
    } catch (error) {
        console.error("Fehler beim Löschen des Mitarbeiters:", error);
        alert(`Fehler beim Löschen: ${error.message}`);
    }
}
