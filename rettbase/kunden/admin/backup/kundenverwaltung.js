// Datei: /kunden/kundenverwaltung.js

// WICHTIG: Importpfad zu auth.js ist korrekt (hoch ins Root-Verzeichnis)
import { auth, db } from "../../auth.js"; 
import { getAllModules, setCompanyModules, getCompanyModules } from "../../modules.js";
import { 
    createUserWithEmailAndPassword,
    signInWithEmailAndPassword,
    signOut
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";
import { 
    collection, 
    doc, 
    setDoc, 
    getDocs, 
    query,
    getDoc, 
    updateDoc, 
    deleteDoc, 
    orderBy 
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --- GLOBALE ZUSTÄNDE ---
let currentAuthData = null; 

// --- DOM-ELEMENTE ---
const companyForm = document.getElementById("newCompanyForm");
const companyMessage = document.getElementById("companyMessage");
const customerList = document.getElementById("customerList"); 

// Such- und Filter-Elemente
const searchInput = document.getElementById("searchInput");
const statusFilter = document.getElementById("statusFilter");
const sortSelect = document.getElementById("sortSelect");

// Modal-Elemente (Neu anlegen)
const createModal = document.getElementById("createModal");
const createCompanyBtn = document.getElementById("createCompanyBtn"); // Button
const closeCreateModalBtn = document.getElementById("closeCreateModal");
const moduleCheckboxes = document.getElementById("moduleCheckboxes");
const editModuleCheckboxes = document.getElementById("editModuleCheckboxes");


// Modal-Elemente (Bearbeiten)
const editModal = document.getElementById("editModal");
const closeEditModalBtn = document.getElementById("closeEditModal");
const editCompanyForm = document.getElementById("editCompanyForm");
const editMessage = document.getElementById("editMessage");
// Input-Felder für Bearbeiten
const editCompanyId = document.getElementById("editCompanyId");
const editName = document.getElementById("editName");
const editAddress = document.getElementById("editAddress");
const editZipCity = document.getElementById("editZipCity");
const editPhone = document.getElementById("editPhone");
const editEmail = document.getElementById("editEmail");
const editStatus = document.getElementById("editStatus");
const editSubdomain = document.getElementById("editSubdomain");


// --- 1. INITIALISIERUNG & HANDSHAKE ---

window.addEventListener('message', async (event) => {
    if (event.data && event.data.type === 'AUTH_DATA') {
        console.log("📥 Kundenverwaltung: AUTH_DATA empfangen:", event.data);
        currentAuthData = event.data.data || event.data.authData; // Unterstütze beide Formate
        
        if (!currentAuthData) {
            console.error("❌ Keine Auth-Daten in AUTH_DATA Nachricht gefunden");
            customerList.innerHTML = '<p style="color:red;">Fehler: Keine Authentifizierungsdaten empfangen.</p>';
            return;
        }
        
        console.log("✅ Auth-Daten empfangen:", {
            role: currentAuthData.role,
            companyId: currentAuthData.companyId,
            uid: currentAuthData.uid
        });
        
        // Anzeige des Buttons nur für Superadmin
        if (currentAuthData.role === 'superadmin') {
            createCompanyBtn.classList.remove('is-hidden'); // 🔥 KORREKTUR: Entfernt die Hiding-Klasse
            console.log("🔍 Starte loadAndRenderCompanyList()...");
            await loadAndRenderCompanyList(); 
        } else {
             // Zugriff verweigert
             customerList.innerHTML = '<p>Sie benötigen Superadmin-Rechte, um Kunden zu verwalten.</p>';
        }
    }
});

if (window.parent) {
    window.parent.postMessage({ type: 'IFRAME_READY' }, '*');
}

// Initialisiere Modul-Checkboxen beim Laden (wird später mit Daten gefüllt)
window.addEventListener('DOMContentLoaded', async () => {
    // Zurück-Button Event Listener
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
    
    await renderModuleCheckboxes(moduleCheckboxes, {});
    await renderModuleCheckboxes(editModuleCheckboxes, {});
    
    // Event Listener für Suche, Filter und Sortierung
    if (searchInput) searchInput.addEventListener('input', filterAndRenderCompanies);
    if (statusFilter) statusFilter.addEventListener('change', filterAndRenderCompanies);
    if (sortSelect) sortSelect.addEventListener('change', filterAndRenderCompanies);
    
    // Auto-Fill Subdomain basierend auf companyId
    const companyIdInput = document.getElementById("companyId");
    const companySubdomainInput = document.getElementById("companySubdomain");
    if (companyIdInput && companySubdomainInput) {
        companyIdInput.addEventListener('input', (e) => {
            const value = e.target.value.toLowerCase().trim();
            // Validiere und setze Subdomain automatisch
            const validSubdomain = value.replace(/[^a-z0-9-]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
            companySubdomainInput.value = validSubdomain;
        });
    }
});

// Globale Variable für alle geladenen Kunden
let allCompanies = [];
let isRendering = false; // Flag, um mehrfaches Rendering zu verhindern

/**
 * Rendert die Modul-Checkboxen
 * @param {HTMLElement} container - Container für die Checkboxen
 * @param {Object} enabledModules - Objekt mit moduleId -> enabled Status
 */
async function renderModuleCheckboxes(container, enabledModules) {
    container.innerHTML = '';
    
    try {
        // Lade alle Module aus Firestore
        const allModules = await getAllModules();
        
        // Filtere System-Module raus (sind immer aktiv) und nur aktive Module
        const configurableModules = Object.values(allModules)
            .filter(m => m.id !== 'home' && m.id !== 'admin' && m.id !== 'kundenverwaltung' && m.active !== false)
            .sort((a, b) => (a.order || 999) - (b.order || 999));
        
        if (configurableModules.length === 0) {
            container.innerHTML = '<p style="color: #666; font-size: 0.9em;">Keine konfigurierbaren Module verfügbar.</p>';
            return;
        }
        
        configurableModules.forEach(module => {
            const label = document.createElement('label');
            label.style.cssText = 'display: block; cursor: pointer; margin: 0 0 10px 0; padding: 0; text-align: left;';
            
            const checkbox = document.createElement('input');
            checkbox.type = 'checkbox';
            checkbox.id = `module_${module.id}`;
            checkbox.name = `module_${module.id}`;
            checkbox.checked = enabledModules[module.id] === true;
            checkbox.dataset.moduleId = module.id;
            checkbox.style.cssText = 'margin: 0 8px 0 0; padding: 0; vertical-align: middle; display: inline;';
            
            const span = document.createElement('span');
            span.textContent = `${module.label}${module.free ? ' (kostenlos)' : ' (kostenpflichtig)'}`;
            span.style.cssText = 'display: inline; margin: 0; padding: 0;';
            
            label.appendChild(checkbox);
            label.appendChild(span);
            container.appendChild(label);
        });
    } catch (error) {
        console.error("Fehler beim Laden der Module:", error);
        container.innerHTML = '<p style="color: red; font-size: 0.9em;">Fehler beim Laden der Module.</p>';
    }
}

/**
 * Sammelt die ausgewählten Module aus den Checkboxen
 * @param {HTMLElement} container - Container mit den Checkboxen
 * @returns {Promise<Object>} Objekt mit moduleId -> enabled Status
 */
async function getSelectedModules(container) {
    const modules = {};
    
    // Lade alle verfügbaren Module, um zu wissen, welche Module konfigurierbar sind
    const allModules = await getAllModules();
    const configurableModules = Object.values(allModules)
        .filter(m => m.id !== 'home' && m.id !== 'admin' && m.id !== 'kundenverwaltung' && m.active !== false);
    
    // Initialisiere ALLE konfigurierbaren Module mit false (nicht aktiviert)
    configurableModules.forEach(module => {
        modules[module.id] = false;
    });
    
    // Setze angekreuzte Module auf true
    const checkboxes = container.querySelectorAll('input[type="checkbox"]');
    checkboxes.forEach(checkbox => {
        const moduleId = checkbox.dataset.moduleId;
        if (moduleId && checkbox.checked) {
            modules[moduleId] = true;
        }
    });
    
    // System-Module sind immer aktiv (werden nicht als Checkboxen angezeigt)
    modules['home'] = true;
    modules['admin'] = true;
    
    return modules;
}

/**
 * Initialisiert die Datenbankstruktur für einen neuen Kunden
 * Legt automatisch an: Standard-Module, Standard-Tiles für Admin
 */
async function initializeCompanyDatabase(companyId, adminUid) {
    try {
        console.log(`🔧 Initialisiere Datenbankstruktur für Firma '${companyId}'...`);
        
        // 1. Standard-Tiles für den Admin-Benutzer anlegen
        const tilesRef = doc(db, "kunden", companyId, "users", adminUid, "userTiles", "config");
        const tilesSnap = await getDoc(tilesRef);
        
        if (!tilesSnap.exists()) {
            const defaultTiles = [
                { label: "Home", page: "home.html" },
                { label: "Mitglieder", page: "kunden/admin/admin.html" },
                null, null, null, null, null, null, null
            ];
            
            await setDoc(tilesRef, { tiles: defaultTiles });
            console.log(`✅ Standard-Tiles für Admin-Benutzer angelegt`);
        }
        
        console.log(`✅ Datenbankstruktur für Firma '${companyId}' initialisiert`);
        
    } catch (error) {
        console.error(`❌ Fehler beim Initialisieren der Datenbankstruktur für '${companyId}':`, error);
        // Fehler nicht weiterwerfen, damit Kunden-Anlage nicht fehlschlägt
    }
}

// --- 2. LOGIK FÜR KUNDENREGISTRIERUNG & ADMIN-ANLAGE ---

companyForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    companyMessage.textContent = 'Verarbeite Daten...';
    companyMessage.style.color = 'blue';

    if (currentAuthData.role !== 'superadmin') {
        companyMessage.textContent = 'Fehler: Keine Berechtigung.';
        companyMessage.style.color = 'red';
        return;
    }

    const companyName = document.getElementById("companyName").value.trim();
    const companyId = document.getElementById("companyId").value.toLowerCase().trim();
    let companySubdomain = document.getElementById("companySubdomain").value.toLowerCase().trim();
    
    // Bereinige Subdomain: Entferne alles nach dem ersten Punkt (falls vollständige Domain eingegeben wurde)
    // z.B. "testfirma.rettbase.de" -> "testfirma"
    if (companySubdomain.includes('.')) {
        companySubdomain = companySubdomain.split('.')[0];
    }
    const address = document.getElementById("address").value.trim();
    const zipCity = document.getElementById("zipCity").value.trim();
    const phone = document.getElementById("phone").value.trim();
    const companyEmail = document.getElementById("companyEmail").value.trim();

    const adminEmail = document.getElementById("adminEmail").value.trim();
    const adminPassword = document.getElementById("adminPassword").value;

    // Validierung
    if (!companyId || !companySubdomain || !adminEmail || !adminPassword) {
        companyMessage.textContent = 'Fehler: Bitte alle Pflichtfelder ausfüllen.';
        companyMessage.style.color = 'red';
        return;
    }

    // Validierung: companyId muss Subdomain-kompatibel sein
    if (!/^[a-z0-9-]+$/.test(companyId) || companyId.startsWith('-') || companyId.endsWith('-')) {
        companyMessage.textContent = 'Fehler: Die ID darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten.';
        companyMessage.style.color = 'red';
        return;
    }

    // Validierung: Subdomain muss Subdomain-kompatibel sein
    if (!/^[a-z0-9-]+$/.test(companySubdomain) || companySubdomain.startsWith('-') || companySubdomain.endsWith('-')) {
        companyMessage.textContent = 'Fehler: Die Subdomain darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten.';
        companyMessage.style.color = 'red';
        return;
    }
    
    try {
        // 🔥 WICHTIG: Speichere die aktuelle Session, bevor wir einen neuen Benutzer erstellen
        const currentUser = auth.currentUser;
        if (!currentUser || !currentUser.email) {
            throw new Error("Keine aktive Session gefunden. Bitte melden Sie sich erneut an.");
        }
        
        // Speichere die aktuellen Auth-Daten für die Wiederherstellung
        const originalEmail = currentUser.email;
        const originalUid = currentUser.uid;
        
        // 🔥 KRITISCH: Speichere Superadmin-Daten in localStorage für Wiederherstellung nach Neuladen
        // Dies ermöglicht es, den Superadmin nach dem Neuladen wieder zu identifizieren
        localStorage.setItem('superadmin_restore_email', originalEmail);
        localStorage.setItem('superadmin_restore_uid', originalUid);
        console.log("✅ Superadmin-Daten in localStorage gespeichert für Wiederherstellung");
        
        // SCHRITT A: KUNDEN-STAMM-DOKUMENT ANLEGEN
        await setDoc(doc(db, "kunden", companyId), {
            name: companyName,
            address: address,
            zipCity: zipCity,
            phone: phone,
            email: companyEmail,
            subdomain: companySubdomain, // 🔥 NEU: Subdomain speichern
            status: "active",
            createdAt: new Date(),
            creatorUid: originalUid
        });

        // SCHRITT B & C: ADMIN ANLEGEN
        // ⚠️ WICHTIG: createUserWithEmailAndPassword loggt automatisch den neuen Benutzer ein
        // Wir müssen danach die ursprüngliche Session wiederherstellen
        let newUid;
        try {
            const userCredential = await createUserWithEmailAndPassword(auth, adminEmail, adminPassword);
            newUid = userCredential.user.uid;

            await setDoc(doc(db, "kunden", companyId, "users", newUid), {
                email: adminEmail,
                role: "admin", 
                companyId: companyId, 
                createdAt: new Date(),
                creatorUid: originalUid,
                status: true // Aktiv
            });
            
            // 🔥 KRITISCH: Der neue Benutzer wurde automatisch eingeloggt
            // Wir müssen den Superadmin wieder einloggen, aber wir haben kein Passwort
            // LÖSUNG: Wir loggen den neuen Benutzer aus und versuchen, die ursprüngliche Session wiederherzustellen
            // Da Firebase die Session im Browser-Cache speichert, können wir sie nach dem Neuladen wiederherstellen
            console.log("✅ Neuer Admin-Benutzer wurde erstellt (automatisch eingeloggt)");
            
        } catch (createError) {
            // Wenn der Benutzer bereits existiert, versuche die UID zu finden
            if (createError.code === 'auth/email-already-in-use') {
                throw createError; // Wirf den Fehler weiter, damit er oben behandelt wird
            }
            throw createError;
        }

        // SCHRITT D: MODULE FREISCHALTEN
        // Nur die Module freigeben, die auch angekreuzt sind
        const selectedModules = await getSelectedModules(moduleCheckboxes);
        await setCompanyModules(companyId, selectedModules);
        
        // SCHRITT E: AUTOMATISCHE DATENBANKSTRUKTUR ANLEGEN
        await initializeCompanyDatabase(companyId, newUid);
        
        // 🔥 KRITISCH: Stelle die ursprüngliche Session wieder her
        // Der neue Benutzer ist jetzt eingeloggt, aber wir brauchen den Superadmin
        // LÖSUNG: Logge den neuen Benutzer aus und lade die Seite neu
        // Firebase sollte die ursprüngliche Session im Browser-Cache haben und sie nach dem Neuladen wiederherstellen
        console.log("✅ Kunde angelegt. Logge neuen Benutzer aus und stelle Superadmin-Session wieder her...");
        
        // Logge den neuen Benutzer aus
        await signOut(auth);
        console.log("✅ Neuer Benutzer ausgeloggt");
        
        // Warte kurz, damit alle Firestore-Operationen abgeschlossen sind
        await new Promise(resolve => setTimeout(resolve, 500));
        
        // Zeige Erfolgsmeldung kurz an, bevor die Seite neu geladen wird
        companyMessage.textContent = `✅ Kunde '${companyName}' (ID: ${companyId}) und Admin ${adminEmail} erfolgreich registriert. Seite wird neu geladen...`;
        companyMessage.style.color = 'green';
        
        // Warte kurz, damit der Benutzer die Erfolgsmeldung sieht
        await new Promise(resolve => setTimeout(resolve, 1500));
        
        // 🔥 WICHTIG: Lade die Seite neu
        // Firebase sollte die ursprüngliche Session im Browser-Cache haben
        // Wenn nicht, muss sich der Superadmin erneut anmelden
        // ABER: Das ist besser als den falschen Benutzer eingeloggt zu lassen
        window.location.reload(); 

    } catch (e) {
        console.error("Fehler beim Anlegen des Kunden/des Admins:", e);
        let msg = `Fehler beim Erstellen.`;
        if (e.code === 'auth/email-already-in-use') {
            msg = `Fehler: Die Admin-E-Mail ${adminEmail} ist bereits registriert.`;
        } else if (e.code === 'auth/weak-password') {
            msg = 'Fehler: Das Passwort ist zu schwach (mindestens 6 Zeichen).';
        } else {
             msg = `Allgemeiner Fehler: ${e.message}`;
        }
        companyMessage.textContent = msg;
        companyMessage.style.color = 'red';
    }
});


// --- MODAL-FUNKTIONEN FÜR NEUANLAGE ---
function openCreateModal() {
    companyMessage.textContent = '';
    createModal.style.display = 'flex';
}

function closeCreateModal() {
    createModal.style.display = 'none';
    companyForm.reset();
}

// Event Listener für Button und Abbrechen
createCompanyBtn.addEventListener('click', openCreateModal);
closeCreateModalBtn.addEventListener('click', closeCreateModal);


// --- 3. LOGIK FÜR KUNDENÜBERSICHT ---

async function loadAndRenderCompanyList() {
    // Verhindere mehrfaches gleichzeitiges Laden
    if (isRendering) {
        console.log("⚠️ loadAndRenderCompanyList wird bereits ausgeführt - überspringe erneuten Aufruf");
        return;
    }
    
    isRendering = true;
    customerList.innerHTML = '<p>Lade Kundendaten...</p>';
    
    try {
        console.log("🔍 Lade Kunden aus Firestore...");
        const kundenRef = collection(db, "kunden");
        
        // Versuche zuerst mit orderBy("name"), falls das fehlschlägt, lade ohne Sortierung
        let snap;
        try {
            const q = query(kundenRef, orderBy("name")); 
            snap = await getDocs(q);
            console.log(`✅ Kunden mit orderBy("name") geladen: ${snap.size} Dokumente`);
        } catch (orderError) {
            console.warn("⚠️ orderBy('name') fehlgeschlagen, lade ohne Sortierung:", orderError);
            // Fallback: Lade alle Dokumente ohne Sortierung
            snap = await getDocs(kundenRef);
            console.log(`✅ Kunden ohne Sortierung geladen: ${snap.size} Dokumente`);
        }
        
        if (snap.empty) {
            customerList.innerHTML = '<p>Bisher keine Kunden registriert.</p>';
            allCompanies = [];
            isRendering = false;
            return;
        }

        // Speichere alle Kunden für Filter/Suche (entferne Duplikate nach ID UND Name/Subdomain)
        allCompanies = [];
        const seenIds = new Set();
        const seenNames = new Set();
        const seenSubdomains = new Set();
        
        snap.forEach(docSnap => {
            const companyId = docSnap.id;
            const data = docSnap.data();
            const companyName = (data.name || '').toLowerCase().trim();
            const subdomain = (data.subdomain || companyId).toLowerCase().trim();
            
            // Prüfe auf Duplikate nach ID, Name oder Subdomain
            const isDuplicate = seenIds.has(companyId) || 
                               (companyName && seenNames.has(companyName)) ||
                               (subdomain && seenSubdomains.has(subdomain));
            
            if (!isDuplicate) {
                seenIds.add(companyId);
                if (companyName) seenNames.add(companyName);
                if (subdomain) seenSubdomains.add(subdomain);
                
                allCompanies.push({
                    id: companyId,
                    ...data
                });
            } else {
                console.warn(`⚠️ Duplikat gefunden und übersprungen:`, {
                    id: companyId,
                    name: data.name,
                    subdomain: subdomain,
                    reason: seenIds.has(companyId) ? 'ID bereits vorhanden' : 
                           (companyName && seenNames.has(companyName)) ? 'Name bereits vorhanden' :
                           'Subdomain bereits vorhanden'
                });
            }
        });

        console.log(`✅ ${allCompanies.length} eindeutige Kunden geladen (von ${snap.size} Dokumenten):`);
        allCompanies.forEach(c => {
            console.log(`   - ${c.name || 'Unbenannt'} (ID: ${c.id}, Subdomain: ${c.subdomain || c.id})`);
        });

        // Sortiere manuell nach Name (falls orderBy fehlgeschlagen ist)
        if (allCompanies.length > 0) {
            allCompanies.sort((a, b) => {
                const nameA = (a.name || '').toLowerCase();
                const nameB = (b.name || '').toLowerCase();
                return nameA.localeCompare(nameB);
            });
            console.log("✅ Kunden manuell nach Name sortiert");
        }

        // Rendere gefilterte/sortierte Liste
        // Setze isRendering auf false, da das Laden abgeschlossen ist
        isRendering = false;
        await filterAndRenderCompanies();

    } catch (e) {
        console.error("❌ Fehler beim Laden der Kundenliste:", e);
        console.error("Fehler-Details:", {
            message: e.message,
            code: e.code,
            stack: e.stack
        });
        customerList.innerHTML = `<p style="color:red;">Fehler beim Laden der Kundenliste: ${e.message}<br>Details siehe Konsole.</p>`;
        allCompanies = [];
    } finally {
        isRendering = false;
        console.log("✅ loadAndRenderCompanyList abgeschlossen, isRendering = false");
    }
}

/**
 * Filtert und rendert die Kundenliste basierend auf Suche, Filter und Sortierung
 */
let isFiltering = false; // Separater Flag für filterAndRenderCompanies

async function filterAndRenderCompanies() {
    // Verhindere mehrfaches gleichzeitiges Filtern/Rendern
    if (isFiltering) {
        console.log("⚠️ filterAndRenderCompanies wird bereits ausgeführt - überspringe erneuten Aufruf");
        return;
    }
    
    isFiltering = true;
    
    try {
        if (!allCompanies || allCompanies.length === 0) {
            customerList.innerHTML = '<p>Keine Kunden gefunden.</p>';
            isFiltering = false;
            return;
        }

    // Entferne Duplikate vor dem Filtern (zusätzliche Sicherheit)
    const uniqueCompanies = [];
    const seenIdsFilter = new Set();
    for (const company of allCompanies) {
        if (!seenIdsFilter.has(company.id)) {
            seenIdsFilter.add(company.id);
            uniqueCompanies.push(company);
        }
    }
    
    if (uniqueCompanies.length !== allCompanies.length) {
        console.warn(`⚠️ ${allCompanies.length - uniqueCompanies.length} Duplikate vor dem Filtern entfernt`);
        allCompanies = uniqueCompanies;
    }

    let filtered = [...allCompanies];

    // 1. Suche
    const searchTerm = searchInput ? searchInput.value.toLowerCase().trim() : '';
    if (searchTerm) {
        filtered = filtered.filter(company => 
            company.name.toLowerCase().includes(searchTerm) ||
            company.id.toLowerCase().includes(searchTerm) ||
            (company.subdomain && company.subdomain.toLowerCase().includes(searchTerm)) ||
            (company.email && company.email.toLowerCase().includes(searchTerm))
        );
    }

    // 2. Status-Filter
    const statusFilterValue = statusFilter ? statusFilter.value : 'all';
    if (statusFilterValue !== 'all') {
        filtered = filtered.filter(company => company.status === statusFilterValue);
    }

    // 3. Sortierung
    const sortValue = sortSelect ? sortSelect.value : 'name-asc';
    filtered.sort((a, b) => {
        switch(sortValue) {
            case 'name-asc':
                return (a.name || '').localeCompare(b.name || '');
            case 'name-desc':
                return (b.name || '').localeCompare(a.name || '');
            case 'date-asc':
                const dateA = a.createdAt?.toDate?.() || new Date(0);
                const dateB = b.createdAt?.toDate?.() || new Date(0);
                return dateA - dateB;
            case 'date-desc':
                const dateA2 = a.createdAt?.toDate?.() || new Date(0);
                const dateB2 = b.createdAt?.toDate?.() || new Date(0);
                return dateB2 - dateA2;
            case 'status':
                return (a.status || '').localeCompare(b.status || '');
            default:
                return 0;
        }
    });

    // 4. Rendern
    // 🔥 WICHTIG: Leere die Liste komplett, bevor wir neu rendern
    customerList.innerHTML = '';
    
    if (filtered.length === 0) {
        customerList.innerHTML = '<p>Keine Kunden gefunden, die den Suchkriterien entsprechen.</p>';
        isFiltering = false;
        return;
    }

    // Entferne Duplikate basierend auf ID (zusätzliche Sicherheit)
    const uniqueFiltered = [];
    const seenIdsRender = new Set();
    for (const company of filtered) {
        if (!seenIdsRender.has(company.id)) {
            seenIdsRender.add(company.id);
            uniqueFiltered.push(company);
        } else {
            console.warn(`⚠️ Duplikat beim Rendern übersprungen: ${company.name || 'Unbenannt'} (ID: ${company.id})`);
        }
    }

    console.log(`🎨 Rendere ${uniqueFiltered.length} eindeutige Kunden (${filtered.length} vor Deduplizierung)`);
    uniqueFiltered.forEach(c => {
        console.log(`   → Rendere: ${c.name || 'Unbenannt'} (ID: ${c.id})`);
    });

    // Lade Statistiken für jeden Kunden (Anzahl Benutzer)
    for (const company of uniqueFiltered) {
        await renderCompanyItem(company.id, company);
    }
    
    console.log(`✅ Rendering abgeschlossen. Aktuelle Anzahl Karten im DOM: ${customerList.querySelectorAll('.customer-card').length}`);
    
    } catch (e) {
        console.error("❌ Fehler beim Filtern/Rendern der Kundenliste:", e);
        customerList.innerHTML = `<p style="color:red;">Fehler beim Anzeigen der Kundenliste: ${e.message}</p>`;
    } finally {
        isFiltering = false;
    }
}

async function renderCompanyItem(id, data) {
    // Prüfe, ob diese Karte bereits existiert (verhindere Duplikate)
    const existingCard = customerList.querySelector(`[data-company-id="${id}"]`);
    if (existingCard) {
        console.warn(`⚠️ Karte für ${id} (${data.name || 'Unbenannt'}) existiert bereits, überspringe Rendering`);
        return;
    }
    
    console.log(`🎨 Rendere Karte für: ${data.name || 'Unbenannt'} (ID: ${id})`);

    // Lade Anzahl Benutzer für diese Firma
    let userCount = 0;
    try {
        const usersRef = collection(db, "kunden", id, "users");
        const usersSnap = await getDocs(usersRef);
        userCount = usersSnap.size;
    } catch (e) {
        console.warn(`Konnte Benutzeranzahl für ${id} nicht laden:`, e);
    }

    const div = document.createElement('div');
    div.className = 'customer-card';
    div.dataset.companyId = id;
    
    // 🔥 SCHUTZ: Firma "admin" darf nicht gelöscht werden - deaktiviere Löschen-Button
    const isAdminCompany = id === 'admin';
    
    const createdAt = data.createdAt ? data.createdAt.toDate().toLocaleDateString() : 'Unbekannt';
    const subdomain = data.subdomain || id;
    const subdomainUrl = `https://${subdomain}.rettbase.de`;
    const statusBadge = getStatusBadge(data.status || 'active');

    div.innerHTML = `
        <div class="customer-card-header">
            <div class="customer-title">
                <strong>${data.name || id}</strong>
                ${statusBadge}
                ${isAdminCompany ? '<span style="margin-left: 10px; color: #ef4444; font-size: 0.85em;">🔒 System-Firma</span>' : ''}
            </div>
            <div class="customer-actions">
                <a href="${subdomainUrl}" target="_blank" class="quick-access-btn" title="Zum Kunden-Dashboard">
                    🔗 Öffnen
                </a>
                <button class="edit-btn">Bearbeiten</button>
                ${isAdminCompany ? '<button class="delete-btn" disabled title="Die Admin-Firma kann nicht gelöscht werden" style="opacity: 0.5; cursor: not-allowed;">Löschen</button>' : '<button class="delete-btn">Löschen</button>'}
            </div>
        </div>
        <div class="customer-card-body">
            <div class="customer-info-grid">
                <div class="info-item">
                    <span class="info-label">Subdomain:</span>
                    <span class="info-value">
                        <a href="${subdomainUrl}" target="_blank">${subdomainUrl}</a>
                    </span>
                </div>
                <div class="info-item">
                    <span class="info-label">ID:</span>
                    <span class="info-value">${id}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">E-Mail:</span>
                    <span class="info-value">${data.email || 'N/A'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">Telefon:</span>
                    <span class="info-value">${data.phone || 'N/A'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">Adresse:</span>
                    <span class="info-value">${data.address || 'N/A'}, ${data.zipCity || ''}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">Benutzer:</span>
                    <span class="info-value">${userCount} ${userCount === 1 ? 'Benutzer' : 'Benutzer'}</span>
                </div>
                <div class="info-item">
                    <span class="info-label">Erstellt:</span>
                    <span class="info-value">${createdAt}</span>
                </div>
            </div>
        </div>
    `;
    
    // Event Listener für Bearbeiten
    div.querySelector('.edit-btn').addEventListener('click', () => {
        openEditModal(id); 
    });
    
    // Event Listener für Löschen (nur wenn nicht admin-Firma)
    const deleteBtn = div.querySelector('.delete-btn');
    if (deleteBtn && !deleteBtn.disabled) {
        deleteBtn.addEventListener('click', () => {
            handleDeleteCompany(id, data.name);
        });
    } else if (isAdminCompany) {
        // Für admin-Firma: Zeige Warnung beim Klick
        deleteBtn.addEventListener('click', () => {
            alert('❌ Die Firma "admin" darf nicht gelöscht werden. Dies ist die Superadmin-Firma und ist für das System erforderlich.\n\nFalls die Firma "admin" versehentlich gelöscht wurde, verwenden Sie die Wiederherstellungsseite:\n/kunden/admin/restore-admin.html');
        });
    }

    customerList.appendChild(div);
}

/**
 * Erstellt ein Status-Badge
 */
function getStatusBadge(status) {
    const badges = {
        'active': '<span class="status-badge status-active">Aktiv</span>',
        'inactive': '<span class="status-badge status-inactive">Inaktiv</span>',
        'suspended': '<span class="status-badge status-suspended">Gesperrt</span>'
    };
    return badges[status] || badges['active'];
}


// --- 4. LOGIK FÜR KUNDEN BEARBEITEN (MODAL) ---

async function openEditModal(companyId) {
    editMessage.textContent = '';
    editModal.style.display = 'flex';
    
    try {
        const docRef = doc(db, "kunden", companyId);
        const docSnap = await getDoc(docRef);
        
        if (!docSnap.exists()) {
            editMessage.textContent = 'Fehler: Kunde nicht gefunden.';
            editMessage.style.color = 'red';
            return;
        }
        
        const data = docSnap.data();
        
        editCompanyId.value = companyId; 
        editName.value = data.name || '';
        editAddress.value = data.address || '';
        editZipCity.value = data.zipCity || '';
        editPhone.value = data.phone || '';
        editEmail.value = data.email || '';
        editStatus.value = data.status || 'active';
        editSubdomain.value = data.subdomain || companyId;
        
        // Lade Module-Freischaltungen
        const enabledModules = await getCompanyModules(companyId);
        await renderModuleCheckboxes(editModuleCheckboxes, enabledModules);
        
    } catch (e) {
        console.error("Fehler beim Laden der Bearbeitungsdaten:", e);
        editMessage.textContent = 'Fehler beim Laden der Daten.';
        editMessage.style.color = 'red';
    }
}

function closeEditModal() {
    editModal.style.display = 'none';
    editCompanyForm.reset();
}

// Event Listener für den Abbrechen-Button
closeEditModalBtn.addEventListener('click', closeEditModal);

// Speichern der bearbeiteten Daten
editCompanyForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    editMessage.textContent = 'Speichere Änderungen...';
    editMessage.style.color = 'blue';

    const companyId = editCompanyId.value;
    
    try {
        const docRef = doc(db, "kunden", companyId);
        
        let subdomain = editSubdomain.value.toLowerCase().trim();
        
        // Bereinige Subdomain: Entferne alles nach dem ersten Punkt (falls vollständige Domain eingegeben wurde)
        // z.B. "testfirma.rettbase.de" -> "testfirma"
        if (subdomain.includes('.')) {
            subdomain = subdomain.split('.')[0];
        }
        
        // Validierung: Subdomain muss Subdomain-kompatibel sein
        if (!/^[a-z0-9-]+$/.test(subdomain) || subdomain.startsWith('-') || subdomain.endsWith('-')) {
            editMessage.textContent = 'Fehler: Die Subdomain darf nur Kleinbuchstaben, Zahlen und Bindestriche enthalten.';
            editMessage.style.color = 'red';
            return;
        }

        const updates = {
            name: editName.value.trim(),
            address: editAddress.value.trim(),
            zipCity: editZipCity.value.trim(),
            phone: editPhone.value.trim(),
            email: editEmail.value.trim(),
            subdomain: subdomain, // 🔥 NEU: Subdomain aktualisieren
            status: editStatus.value
        };
        
        await updateDoc(docRef, updates);
        
        // Aktualisiere Module-Freischaltungen - nur die Module freigeben, die auch angekreuzt sind
        const selectedModules = await getSelectedModules(editModuleCheckboxes);
        await setCompanyModules(companyId, selectedModules);
        
        editMessage.textContent = '✅ Kunde erfolgreich aktualisiert.';
        editMessage.style.color = 'green';
        
        await loadAndRenderCompanyList(); 
        setTimeout(closeEditModal, 1500); 
        
    } catch (e) {
        console.error("Fehler beim Speichern der Änderungen:", e);
        editMessage.textContent = `Fehler beim Speichern: ${e.message}`;
        editMessage.style.color = 'red';
    }
});


// --- 5. LOGIK FÜR KUNDEN LÖSCHEN ---

async function handleDeleteCompany(companyId, companyName) {
    // 🔥 SCHUTZ: Firma "admin" darf nicht gelöscht werden
    if (companyId === 'admin') {
        alert('❌ Die Firma "admin" darf nicht gelöscht werden. Dies ist die Superadmin-Firma und ist für das System erforderlich.\n\nFalls die Firma "admin" versehentlich gelöscht wurde, verwenden Sie die Wiederherstellungsseite:\n/kunden/admin/restore-admin.html');
        return;
    }

    if (!confirm(`Sind Sie sicher, dass Sie den Kunden '${companyName}' (ID: ${companyId}) wirklich löschen möchten? ALLE Daten werden unwiederbringlich gelöscht!`)) {
        return;
    }

    try {
        // HINWEIS: Hier sollte serverseitig über Cloud Functions gelöscht werden, 
        // um ALLE Sub-Collections (Benutzer, Whiteboard-Daten, etc.) zu entfernen!
        await deleteDoc(doc(db, "kunden", companyId));

        alert(`✅ Kunde '${companyName}' wurde erfolgreich gelöscht. HINWEIS: Zugehörige Sub-Collections (Benutzer, Whiteboard) müssen manuell/serverseitig gelöscht werden.`);
        
        await loadAndRenderCompanyList();
        
    } catch (e) {
        console.error("Fehler beim Löschen des Kunden:", e);
        alert(`Fehler beim Löschen des Kunden: ${e.message}`);
    }
}