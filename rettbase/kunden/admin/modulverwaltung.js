// Datei: modulverwaltung.js
// Verwaltung der Module im Superadmin-Backend

import { auth, db } from "../../auth.js"; 
import { getAllModules, getModule, saveModule, deleteModule, initializeDefaultModules, setCompanyModule, getCompanyModules } from "../../modules.js";
import { 
    collection, 
    doc, 
    getDoc, 
    getDocs, 
    query,
    orderBy
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// --- GLOBALE ZUSTÄNDE ---
let currentAuthData = null; 

// --- DOM-ELEMENTE ---
const moduleForm = document.getElementById("newModuleForm");
const moduleMessage = document.getElementById("moduleMessage");
const moduleList = document.getElementById("moduleList"); 

// Modal-Elemente (Neu anlegen)
const createModal = document.getElementById("createModal");
const createModuleBtn = document.getElementById("createModuleBtn");
const closeCreateModalBtn = document.getElementById("closeCreateModal");

// Modal-Elemente (Bearbeiten)
const editModal = document.getElementById("editModal");
const closeEditModalBtn = document.getElementById("closeEditModal");
const editModuleForm = document.getElementById("editModuleForm");
const editMessage = document.getElementById("editMessage");
const editModuleId = document.getElementById("editModuleId");
const editModuleLabel = document.getElementById("editModuleLabel");
const editModuleUrl = document.getElementById("editModuleUrl");
const editModuleIcon = document.getElementById("editModuleIcon");
const editModuleOrder = document.getElementById("editModuleOrder");
const editModuleFree = document.getElementById("editModuleFree");
const editModuleActive = document.getElementById("editModuleActive");

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
});

window.addEventListener('message', async (event) => {
    if (event.data && event.data.type === 'AUTH_DATA') {
        currentAuthData = event.data.data;
        
        // Anzeige des Buttons nur für Superadmin
        if (currentAuthData.role === 'superadmin') {
            createModuleBtn.classList.remove('is-hidden');
            await initializeDefaultModules(); // Stelle sicher, dass Standard-Module existieren
            await loadAndRenderModuleList();
            
            // Stelle sicher, dass ALLE Module für Admin freigeschaltet sind (asynchron im Hintergrund)
            enableAllModulesForAdminLocal().catch(enableError => {
                console.warn("⚠️ Fehler beim Freischalten aller Module für Admin:", enableError);
            });
        } else {
            moduleList.innerHTML = '<p>Sie benötigen Superadmin-Rechte, um Module zu verwalten.</p>';
        }
    }
});

if (window.parent) {
    window.parent.postMessage({ type: 'IFRAME_READY' }, '*');
}

// --- 2. LOGIK FÜR MODUL-ANLAGE ---

moduleForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    moduleMessage.textContent = 'Verarbeite Daten...';
    moduleMessage.style.color = 'blue';

    if (currentAuthData.role !== 'superadmin') {
        moduleMessage.textContent = 'Fehler: Keine Berechtigung.';
        moduleMessage.style.color = 'red';
        return;
    }

    const label = document.getElementById("moduleLabel").value.trim();
    let url = document.getElementById("moduleUrl").value.trim();
    const icon = document.getElementById("moduleIcon").value.trim() || 'default';
    const order = parseInt(document.getElementById("moduleOrder").value) || 999;
    const free = document.getElementById("moduleFree").value === 'true';
    const active = document.getElementById("moduleActive").value === 'true';
    
    // Korrigiere "modul" zu "module" in der URL
    url = url.replace(/\/modul\//g, '/module/');
    // Füge führenden Slash hinzu, falls fehlt (außer bei absoluten URLs)
    if (url && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('/')) {
        url = '/' + url;
    }
    
    // Sammle Rollen aus Checkboxen
    const roleCheckboxes = document.querySelectorAll('#roleCheckboxes input[type="checkbox"]:checked');
    const roles = Array.from(roleCheckboxes).map(cb => cb.value);
    
    if (!label || !url || roles.length === 0) {
        moduleMessage.textContent = 'Fehler: Bitte alle Pflichtfelder ausfüllen.';
        moduleMessage.style.color = 'red';
        return;
    }
    
    try {
        const moduleData = {
            label: label,
            url: url,
            icon: icon,
            order: order,
            free: free,
            active: active,
            roles: roles
        };
        
        const moduleId = await saveModule(moduleData);
        console.log(`✅ Modul '${moduleId}' gespeichert. Label: '${label}'`);
        
        // Automatisch für Admin-Firma freischalten (immer, da Entwickler)
        try {
            console.log(`🔓 Schalte Modul '${moduleId}' für Admin-Firma frei (Entwickler)...`);
            await setCompanyModule("admin", moduleId, true);
            console.log(`✅ Modul '${moduleId}' für Admin-Firma freigeschaltet`);
            
            // Verifikation: Prüfe ob Freischaltung wirklich funktioniert hat
            const companyModules = await getCompanyModules("admin");
            if (companyModules[moduleId] === true) {
                console.log(`✅ Verifikation: Modul '${moduleId}' ist für Admin-Firma freigeschaltet`);
            } else {
                console.warn(`⚠️ Verifikation fehlgeschlagen: Modul '${moduleId}' ist NICHT für Admin-Firma freigeschaltet!`);
            }
        } catch (enableError) {
            console.error("❌ Fehler beim automatischen Freischalten des Moduls für Admin:", enableError);
            moduleMessage.textContent = `⚠️ Modul angelegt, aber Freischaltung für Admin fehlgeschlagen: ${enableError.message}.`;
            moduleMessage.style.color = 'orange';
        }
        
        // 🔥 ENTFERNT: Automatische Freischaltung für alle Firmen bei kostenlosen Modulen
        // Module müssen jetzt explizit in der Kundenverwaltung für jede Firma freigeschaltet werden
        // Dies stellt sicher, dass nur die Module angezeigt werden, die auch tatsächlich angekreuzt wurden
        
        moduleMessage.textContent = `✅ Modul '${label}' erfolgreich angelegt (ID: ${moduleId}) und freigeschaltet.`;
        moduleMessage.style.color = 'green';
        moduleForm.reset();
        
        // Reset Checkboxen
        document.querySelectorAll('#roleCheckboxes input[type="checkbox"]').forEach(cb => cb.checked = true);
        document.getElementById("moduleOrder").value = "999";
        document.getElementById("moduleFree").value = "true";
        document.getElementById("moduleActive").value = "true";
        
        await loadAndRenderModuleList();
        
        // Informiere das Dashboard, dass Module aktualisiert wurden
        if (window.parent) {
            window.parent.postMessage({ type: 'MODULES_UPDATED', reason: 'saved' }, '*');
            console.log('📢 Dashboard über Module-Update informiert (reason: saved)');
        }
        
        setTimeout(closeCreateModal, 1500); 

    } catch (e) {
        console.error("Fehler beim Anlegen des Moduls:", e);
        moduleMessage.textContent = `Fehler beim Erstellen: ${e.message}`;
        moduleMessage.style.color = 'red';
    }
});

// --- MODAL-FUNKTIONEN FÜR NEUANLAGE ---
function openCreateModal() {
    moduleMessage.textContent = '';
    createModal.style.display = 'flex';
}

function closeCreateModal() {
    createModal.style.display = 'none';
    moduleForm.reset();
    document.querySelectorAll('#roleCheckboxes input[type="checkbox"]').forEach(cb => cb.checked = true);
}

createModuleBtn.addEventListener('click', openCreateModal);
closeCreateModalBtn.addEventListener('click', closeCreateModal);

// --- HELPER: Schaltet alle Module für Admin frei ---
async function enableAllModulesForAdminLocal() {
    try {
        const allModules = await getAllModules();
        const activeModules = Object.values(allModules).filter(m => m.active !== false);
        
        console.log(`🔓 Schalte ${activeModules.length} Module für Admin-Firma frei (Entwickler)...`);
        
        const enablePromises = activeModules.map(module => 
            setCompanyModule("admin", module.id, true)
        );
        
        await Promise.all(enablePromises);
        console.log(`✅ Alle ${activeModules.length} Module für Admin-Firma freigeschaltet`);
    } catch (error) {
        console.error("Fehler beim Freischalten aller Module für Admin:", error);
        throw error;
    }
}

// --- 3. LOGIK FÜR MODUL-ÜBERSICHT ---

async function loadAndRenderModuleList() {
    moduleList.innerHTML = '<p>Lade Module...</p>';
    
    try {
        const modules = await getAllModules();
        
        if (Object.keys(modules).length === 0) {
            moduleList.innerHTML = '<p>Bisher keine Module vorhanden.</p>';
            return;
        }

        moduleList.innerHTML = ''; 
        
        // Sortiere Module nach order
        const sortedModules = Object.values(modules).sort((a, b) => (a.order || 999) - (b.order || 999));
        
        sortedModules.forEach(module => {
            renderModuleItem(module);
        });

    } catch (e) {
        console.error("Fehler beim Laden der Modulliste:", e);
        moduleList.innerHTML = '<p style="color:red;">Fehler beim Laden der Modulliste. Prüfen Sie die Berechtigungen.</p>';
    }
}

function renderModuleItem(module) {
    const div = document.createElement('div');
    div.className = 'customer-item';
    div.dataset.moduleId = module.id;
    
    const isSystemModule = ['home', 'kundenverwaltung'].includes(module.id); // admin ist jetzt bearbeitbar
    const statusBadge = module.active ? '<span style="color: green;">✓ Aktiv</span>' : '<span style="color: red;">✗ Inaktiv</span>';
    const freeBadge = module.free ? '<span style="color: #00bcd4;">Kostenlos</span>' : '<span style="color: orange;">Kostenpflichtig</span>';
    const rolesText = module.roles ? module.roles.join(', ') : 'Keine';
    
    div.innerHTML = `
        <div class="customer-details">
            <strong>${module.label}</strong> ${statusBadge} | ${freeBadge}
            <div class="customer-id">
                ID: ${module.id} | URL: ${module.url} | Reihenfolge: ${module.order || 999}
                <br>Rollen: ${rolesText}
            </div>
        </div>
        <div class="customer-actions">
            ${!isSystemModule ? '<button class="edit-btn">Bearbeiten</button>' : ''}
            ${!isSystemModule ? '<button class="delete-btn" style="background: #e74c3c;">Löschen</button>' : '<span style="color: #999; font-size: 0.9em;">System-Modul</span>'}
        </div>
    `;
    
    if (!isSystemModule) {
        // Event Listener für Bearbeiten
        div.querySelector('.edit-btn').addEventListener('click', () => {
            openEditModal(module.id); 
        });
        
        // Event Listener für Löschen
        div.querySelector('.delete-btn').addEventListener('click', () => {
            handleDeleteModule(module.id, module.label);
        });
    }

    moduleList.appendChild(div);
}

// --- 4. LOGIK FÜR MODUL BEARBEITEN (MODAL) ---

async function openEditModal(moduleId) {
    editMessage.textContent = '';
    editModal.style.display = 'flex';
    
    try {
        const module = await getModule(moduleId);
        
        if (!module) {
            editMessage.textContent = 'Fehler: Modul nicht gefunden.';
            editMessage.style.color = 'red';
            return;
        }
        
        editModuleId.value = moduleId; 
        editModuleLabel.value = module.label || '';
        editModuleUrl.value = module.url || '';
        editModuleIcon.value = module.icon || 'default';
        editModuleOrder.value = module.order || 999;
        editModuleFree.value = module.free ? 'true' : 'false';
        editModuleActive.value = module.active !== false ? 'true' : 'false';
        
        // Setze Rollen-Checkboxen
        const roles = module.roles || [];
        document.querySelectorAll('#editRoleCheckboxes input[type="checkbox"]').forEach(cb => {
            cb.checked = roles.includes(cb.value);
        });
        
    } catch (e) {
        console.error("Fehler beim Laden der Bearbeitungsdaten:", e);
        editMessage.textContent = 'Fehler beim Laden der Daten.';
        editMessage.style.color = 'red';
    }
}

function closeEditModal() {
    editModal.style.display = 'none';
    editModuleForm.reset();
}

closeEditModalBtn.addEventListener('click', closeEditModal);

// Speichern der bearbeiteten Daten
editModuleForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    editMessage.textContent = 'Speichere Änderungen...';
    editMessage.style.color = 'blue';

    const moduleId = editModuleId.value;
    
    try {
        const label = editModuleLabel.value.trim();
        let url = editModuleUrl.value.trim();
        const icon = editModuleIcon.value.trim() || 'default';
        const order = parseInt(editModuleOrder.value) || 999;
        const free = editModuleFree.value === 'true';
        const active = editModuleActive.value === 'true';
        
        // Korrigiere "modul" zu "module" in der URL
        url = url.replace(/\/modul\//g, '/module/');
        // Füge führenden Slash hinzu, falls fehlt (außer bei absoluten URLs)
        if (url && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('/')) {
            url = '/' + url;
        }
        
        // Sammle Rollen aus Checkboxen
        const roleCheckboxes = document.querySelectorAll('#editRoleCheckboxes input[type="checkbox"]:checked');
        const roles = Array.from(roleCheckboxes).map(cb => cb.value);
        
        if (!label || !url || roles.length === 0) {
            editMessage.textContent = 'Fehler: Bitte alle Pflichtfelder ausfüllen.';
            editMessage.style.color = 'red';
            return;
        }
        
        const moduleData = {
            id: moduleId,
            label: label,
            url: url,
            icon: icon,
            order: order,
            free: free,
            active: active,
            roles: roles
        };
        
        console.log(`💾 Speichere Modul-Änderungen für '${moduleId}':`, moduleData);
        const savedModuleId = await saveModule(moduleData);
        console.log(`✅ Modul '${savedModuleId}' erfolgreich aktualisiert`);
        
        // Verifikation: Lade das gespeicherte Modul, um zu prüfen, ob die URL korrekt gespeichert wurde
        const verifyModule = await getModule(savedModuleId);
        if (verifyModule) {
            console.log(`✅ Verifikation: Gespeichertes Modul:`, verifyModule);
            if (verifyModule.url !== url) {
                console.warn(`⚠️ Warnung: Gespeicherte URL (${verifyModule.url}) unterscheidet sich von erwarteter URL (${url})`);
            }
        } else {
            console.error(`❌ Fehler: Modul '${savedModuleId}' konnte nach dem Speichern nicht verifiziert werden`);
        }
        
        editMessage.textContent = '✅ Modul erfolgreich aktualisiert.';
        editMessage.style.color = 'green';
        
        // Warte kurz, damit Firestore die Änderung verarbeitet
        await new Promise(resolve => setTimeout(resolve, 300));
        
        // Prüfe nochmal direkt aus Firestore, ob die Änderung wirklich gespeichert wurde
        const refreshedModule = await getModule(savedModuleId);
        console.log(`🔄 Direkt nach Speichern: Modul '${savedModuleId}' URL aus Firestore:`, refreshedModule?.url);
        console.log(`🔄 Erwartete URL war:`, url);
        
        if (refreshedModule && refreshedModule.url === url) {
            console.log(`✅ URL wurde korrekt in Firestore gespeichert`);
        } else {
            console.error(`❌ PROBLEM: URL in Firestore (${refreshedModule?.url}) stimmt nicht mit erwarteter URL (${url}) überein!`);
        }
        
        // Lade die Liste neu
        await loadAndRenderModuleList();
        
        // Informiere das Dashboard, dass Module aktualisiert wurden
        if (window.parent) {
            window.parent.postMessage({ type: 'MODULES_UPDATED', reason: 'saved' }, '*');
            console.log('📢 Dashboard über Module-Update informiert (reason: saved)');
        }
        
        setTimeout(closeEditModal, 1500); 
        
    } catch (e) {
        console.error("Fehler beim Speichern der Änderungen:", e);
        editMessage.textContent = `Fehler beim Speichern: ${e.message}`;
        editMessage.style.color = 'red';
    }
});

// --- 5. LOGIK FÜR MODUL LÖSCHEN ---

async function handleDeleteModule(moduleId, moduleLabel) {
    if (!confirm(`Sind Sie sicher, dass Sie das Modul '${moduleLabel}' (ID: ${moduleId}) wirklich löschen möchten?`)) {
        return;
    }

    try {
        await deleteModule(moduleId);
        alert(`✅ Modul '${moduleLabel}' wurde erfolgreich gelöscht.`);
        await loadAndRenderModuleList();
    } catch (e) {
        console.error("Fehler beim Löschen des Moduls:", e);
        alert(`Fehler beim Löschen des Moduls: ${e.message}`);
    }
}




