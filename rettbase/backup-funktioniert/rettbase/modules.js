// Datei: modules.js
// Verwaltet die Modul-Definitionen und lädt firmenspezifische Module-Freischaltungen

import { db } from "./firebase-config.js";
import { 
    collection, 
    doc, 
    getDoc, 
    getDocs, 
    setDoc, 
    updateDoc,
    deleteDoc,
    query,
    where,
    orderBy
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

/**
 * Standard-Module (Fallback, falls Firestore leer ist)
 * Diese werden beim ersten Start verwendet
 */
const DEFAULT_MODULES = {
    home: {
        id: 'home',
        label: 'Home',
        url: 'home.html',
        icon: 'home',
        roles: ['superadmin', 'admin', 'supervisor', 'user'],
        free: true,
        order: 1,
        active: true
    },
    admin: {
        id: 'admin',
        label: 'Mitgliederverwaltung',
        url: 'kunden/admin/mitarbeiterverwaltung.html',
        icon: 'admin',
        roles: ['superadmin', 'admin', 'rettungsdienstleiter'],
        free: true,
        order: 4,
        active: true
    },
    kundenverwaltung: {
        id: 'kundenverwaltung',
        label: 'Kundenverwaltung',
        url: 'kunden/admin/kundenverwaltung.html',
        icon: 'kundenverwaltung',
        roles: ['superadmin'],
        free: true,
        order: 5,
        active: true
    },
    modulverwaltung: {
        id: 'modulverwaltung',
        label: 'Modul-Verwaltung',
        url: 'kunden/admin/modulverwaltung.html',
        icon: 'modulverwaltung',
        roles: ['superadmin'],
        free: true,
        order: 6,
        active: true
    },
    schichtplan: {
        id: 'schichtplan',
        label: 'Schichtplan',
        url: '/module/schichtplan/schichtplan.html',
        icon: 'schichtplan',
        roles: ['superadmin', 'admin', 'supervisor', 'rettungsdienstleiter', 'wachleitung', 'ovd'],
        free: true,
        order: 2,
        active: true
    },
    office: {
        id: 'office',
        label: 'Office',
        url: '/module/office/office.html',
        icon: 'office',
        roles: ['superadmin', 'admin', 'supervisor', 'rettungsdienstleiter', 'wachleitung', 'ovd', 'user'],
        free: true,
        order: 3,
        active: true
    },
    'einsatztagebuch---ovd': {
        id: 'einsatztagebuch---ovd',
        label: 'Einsatztagebuch - OVD',
        url: '/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html',
        icon: 'ovd',
        roles: ['superadmin', 'admin', 'rettungsdienstleiter', 'supervisor', 'ovd'],
        free: true,
        order: 7,
        active: true
    }
};

/**
 * Liefert Default-Module abhängig von der Rolle
 * @param {string} role
 * @returns {Array}
 */
export function getDefaultModulesForRole(role) {
    // Normalisiere Rolle zu Kleinbuchstaben für Vergleich
    const normalizedRole = (role || '').toLowerCase().trim();
    
    return Object.values(DEFAULT_MODULES)
        .filter(m => {
            if (m.active === false) return false;
            
            // Wenn keine Rollen definiert, erlaube Zugriff
            if (!m.roles || !Array.isArray(m.roles)) return true;
            
            // Normalisiere Rollen im Array zu Kleinbuchstaben für Vergleich
            const normalizedModuleRoles = m.roles.map(r => String(r).toLowerCase().trim());
            return normalizedModuleRoles.includes(normalizedRole);
        })
        .sort((a, b) => (a.order || 999) - (b.order || 999));
}

/**
 * Lädt alle verfügbaren Module aus Firestore
 * @returns {Promise<Object>} Objekt mit moduleId -> Modul-Daten
 */
export async function getAllModules() {
    try {
        const modulesRef = collection(db, "modules");
        const snapshot = await getDocs(modulesRef);
        
        const modules = {};
        snapshot.forEach(doc => {
            const data = doc.data();
            modules[doc.id] = {
                id: doc.id,
                ...data
            };
        });
        
        // Falls keine Module vorhanden, verwende Default-Module
        if (Object.keys(modules).length === 0) {
            console.warn("⚠️ Keine Module in Firestore gefunden. Verwende Standard-Module.");
            return DEFAULT_MODULES;
        }
        
        // 🔥 WICHTIG: Merge mit DEFAULT_MODULES, um sicherzustellen, dass alle Rollen korrekt sind
        // Wenn ein Modul in Firestore existiert, merge die Rollen aus DEFAULT_MODULES hinzu
        // (Firestore-Rollen haben Priorität, aber fehlende Rollen werden aus DEFAULT_MODULES ergänzt)
        const mergedModules = { ...DEFAULT_MODULES };
        Object.keys(modules).forEach(moduleId => {
            const firestoreModule = modules[moduleId];
            const defaultModule = DEFAULT_MODULES[moduleId];
            
            if (defaultModule) {
                // Modul existiert in beiden: Merge Rollen
                // Kombiniere Rollen aus Firestore und DEFAULT_MODULES (keine Duplikate)
                let mergedRoles = [];
                if (firestoreModule.roles && Array.isArray(firestoreModule.roles) && firestoreModule.roles.length > 0) {
                    // Normalisiere und kombiniere Rollen
                    const firestoreRoles = firestoreModule.roles.map(r => String(r).toLowerCase().trim());
                    const defaultRoles = defaultModule.roles.map(r => String(r).toLowerCase().trim());
                    // Kombiniere beide Arrays, entferne Duplikate
                    mergedRoles = [...new Set([...firestoreRoles, ...defaultRoles])];
                } else {
                    // Wenn Firestore keine Rollen hat, verwende Default-Rollen
                    mergedRoles = defaultModule.roles.map(r => String(r).toLowerCase().trim());
                }
                
                mergedModules[moduleId] = {
                    ...defaultModule,
                    ...firestoreModule,
                    roles: mergedRoles
                };
                console.log(`🔍 Modul ${moduleId}: Rollen gemerged - Firestore: ${JSON.stringify(firestoreModule.roles)}, Default: ${JSON.stringify(defaultModule.roles)}, Final: ${JSON.stringify(mergedRoles)}`);
            } else {
                // Modul existiert nur in Firestore: Verwende es direkt
                mergedModules[moduleId] = firestoreModule;
            }
        });
        
        return mergedModules;
    } catch (error) {
        console.error("Fehler beim Laden der Module:", error);
        return DEFAULT_MODULES;
    }
}

/**
 * Lädt ein einzelnes Modul aus Firestore
 * @param {string} moduleId - Die Modul-ID
 * @returns {Promise<Object|null>} Modul-Daten oder null
 */
export async function getModule(moduleId) {
    try {
        const moduleRef = doc(db, "modules", moduleId);
        const moduleSnap = await getDoc(moduleRef);
        
        if (!moduleSnap.exists()) {
            return null;
        }
        
        return {
            id: moduleSnap.id,
            ...moduleSnap.data()
        };
    } catch (error) {
        console.error(`Fehler beim Laden des Moduls ${moduleId}:`, error);
        return null;
    }
}

/**
 * Erstellt oder aktualisiert ein Modul in Firestore
 * @param {Object} moduleData - Modul-Daten
 * @returns {Promise<void>}
 */
export async function saveModule(moduleData) {
    try {
        const moduleId = moduleData.id || moduleData.label.toLowerCase().replace(/\s+/g, '-');
        const moduleRef = doc(db, "modules", moduleId);
        
        const dataToSave = {
            label: moduleData.label,
            url: moduleData.url,
            icon: moduleData.icon || 'default',
            roles: moduleData.roles || ['user'],
            free: moduleData.free !== undefined ? moduleData.free : true,
            order: moduleData.order || 999,
            active: moduleData.active !== undefined ? moduleData.active : true,
            updatedAt: new Date()
        };
        
        // Beim Erstellen auch createdAt setzen
        const moduleSnap = await getDoc(moduleRef);
        if (!moduleSnap.exists()) {
            dataToSave.createdAt = new Date();
        }
        
        await setDoc(moduleRef, dataToSave, { merge: true });
        return moduleId;
    } catch (error) {
        console.error("Fehler beim Speichern des Moduls:", error);
        throw error;
    }
}

/**
 * Löscht ein Modul aus Firestore
 * @param {string} moduleId - Die Modul-ID
 * @returns {Promise<void>}
 */
export async function deleteModule(moduleId) {
    try {
        // System-Module (home, admin, kundenverwaltung) nicht löschen
        if (['home', 'admin', 'kundenverwaltung'].includes(moduleId)) {
            throw new Error("System-Module können nicht gelöscht werden.");
        }
        
        const moduleRef = doc(db, "modules", moduleId);
        await deleteDoc(moduleRef);
    } catch (error) {
        console.error(`Fehler beim Löschen des Moduls ${moduleId}:`, error);
        throw error;
    }
}

/**
 * Initialisiert die Standard-Module in Firestore (falls noch nicht vorhanden)
 * Sollte einmalig beim ersten Start ausgeführt werden
 */
export async function initializeDefaultModules() {
    try {
        for (const [moduleId, moduleData] of Object.entries(DEFAULT_MODULES)) {
            const moduleRef = doc(db, "modules", moduleId);
            const moduleSnap = await getDoc(moduleRef);
            
            if (!moduleSnap.exists()) {
                await setDoc(moduleRef, {
                    ...moduleData,
                    createdAt: new Date()
                });
                console.log(`✅ Standard-Modul '${moduleId}' initialisiert`);
            }
        }
        console.log("✅ Standard-Module initialisiert");
    } catch (error) {
        console.error("Fehler beim Initialisieren der Standard-Module:", error);
    }
}

/**
 * Lädt die freigeschalteten Module für eine Firma
 * @param {string} companyId - Die Firmen-ID
 * @returns {Promise<Object>} Objekt mit moduleId -> enabled Status
 */
export async function getCompanyModules(companyId) {
    try {
        const companyModulesRef = collection(db, "kunden", companyId, "modules");
        const snapshot = await getDocs(companyModulesRef);
        
        const enabledModules = {};
        snapshot.forEach(doc => {
            enabledModules[doc.id] = doc.data().enabled || false;
        });
        
        return enabledModules;
    } catch (error) {
        console.error("Fehler beim Laden der Firmen-Module:", error);
        return {};
    }
}

/**
 * Setzt die Freischaltung eines Moduls für eine Firma
 * @param {string} companyId - Die Firmen-ID
 * @param {string} moduleId - Die Modul-ID
 * @param {boolean} enabled - Ob das Modul freigeschaltet ist
 */
export async function setCompanyModule(companyId, moduleId, enabled) {
    try {
        const moduleRef = doc(db, "kunden", companyId, "modules", moduleId);
        await setDoc(moduleRef, {
            enabled: enabled,
            updatedAt: new Date()
        }, { merge: true });
    } catch (error) {
        console.error(`Fehler beim Setzen des Moduls ${moduleId} für Firma ${companyId}:`, error);
        throw error;
    }
}

/**
 * Setzt mehrere Module auf einmal für eine Firma
 * @param {string} companyId - Die Firmen-ID
 * @param {Object} modules - Objekt mit moduleId -> enabled Status
 */
export async function setCompanyModules(companyId, modules) {
    try {
        const promises = Object.entries(modules).map(([moduleId, enabled]) => 
            setCompanyModule(companyId, moduleId, enabled)
        );
        await Promise.all(promises);
    } catch (error) {
        console.error(`Fehler beim Setzen der Module für Firma ${companyId}:`, error);
        throw error;
    }
}

/**
 * Lädt die für einen Benutzer sichtbaren Module
 * Berücksichtigt: Freigeschaltete Module der Firma + Rollen-Berechtigung
 * @param {string} companyId - Die Firmen-ID
 * @param {string} userRole - Die Rolle des Benutzers
 * @returns {Promise<Array>} Array von Modul-Objekten, sortiert nach order
 */
export async function getUserModules(companyId, userRole) {
    try {
        console.log(`🔍 getUserModules aufgerufen: companyId=${companyId}, userRole=${userRole}`);
        
        // Normalisiere userRole zu Kleinbuchstaben für Vergleich
        const normalizedUserRole = (userRole || '').toLowerCase().trim();
        console.log(`🔍 Normalisierte Benutzer-Rolle: "${normalizedUserRole}" (ursprünglich: "${userRole}")`);
        
        // Lade alle verfügbaren Module aus Firestore
        const allModules = await getAllModules();
        console.log(`📦 Alle Module geladen:`, Object.keys(allModules));
        
        // Lade freigeschaltete Module der Firma
        const companyModules = await getCompanyModules(companyId);
        console.log(`🏢 Freigeschaltete Module für ${companyId}:`, companyModules);
        console.log(`🏢 Office-Modul Status für ${companyId}:`, companyModules['office'] !== undefined ? `enabled=${companyModules['office']}` : 'nicht gesetzt (undefined)');
        
        // Filtere Module: Muss aktiv sein, freigeschaltet sein UND Benutzer-Rolle muss erlaubt sein
        let visibleModules = Object.values(allModules)
            .filter(module => {
                // Modul muss aktiv sein
                if (module.active === false) {
                    return false;
                }
                
                // Prüfe, ob Modul für diese Firma freigeschaltet ist
                const moduleStatus = companyModules[module.id]; // kann true, false oder undefined sein
                const isEnabled = moduleStatus === true;
                const isExplicitlyDisabled = moduleStatus === false; // Explizit auf false gesetzt
                const isNotSet = moduleStatus === undefined; // Nicht in Firestore gesetzt
                
                // 🔥 WICHTIG: Wenn ein Modul explizit auf false gesetzt wurde, ist es gesperrt (auch wenn free: true)
                if (isExplicitlyDisabled) {
                    // Modul wurde explizit gesperrt - nicht anzeigen
                    console.log(`   🔒 Modul ${module.id} ist explizit gesperrt für Firma ${companyId} (enabled=false)`);
                    return false;
                }
                
                // 🔥 WICHTIG: Kostenlose Module (free: true) sind standardmäßig aktiviert, NUR wenn sie nicht explizit gesperrt sind
                const isFreeModule = module.free === true;
                // Modul ist aktiviert, wenn: explizit enabled=true ODER (free=true UND nicht gesetzt)
                const isModuleEnabled = isEnabled || (isFreeModule && isNotSet);
                
                // Prüfe, ob Benutzer-Rolle Zugriff hat (CASE-INSENSITIVE)
                // Normalisiere alle Rollen im Array zu Kleinbuchstaben für Vergleich
                let hasRoleAccess = false;
                if (module.roles && Array.isArray(module.roles)) {
                    const normalizedModuleRoles = module.roles.map(r => String(r).toLowerCase().trim());
                    hasRoleAccess = normalizedModuleRoles.includes(normalizedUserRole);
                    console.log(`🔍 Modul ${module.id}: roles=${JSON.stringify(module.roles)} → normalisiert=${JSON.stringify(normalizedModuleRoles)}, userRole="${normalizedUserRole}", hasRoleAccess=${hasRoleAccess}`);
                } else {
                    console.warn(`⚠️ Modul ${module.id} hat keine roles-Array oder roles ist kein Array:`, module.roles);
                }
                
                // Debug-Log für wichtige Module
                if (module.id === 'admin' || module.id === 'schichtplan' || module.id === 'home' || module.id === 'office' || module.id === 'einsatztagebuch---ovd') {
                    console.log(`🔍 Modul ${module.id}: aktiv=${module.active !== false}, moduleStatus="${moduleStatus}" (enabled=${isEnabled}, disabled=${isExplicitlyDisabled}, notSet=${isNotSet}), free=${isFreeModule}, finalEnabled=${isModuleEnabled}, roles=${JSON.stringify(module.roles)}, hasRoleAccess=${hasRoleAccess}, userRole="${normalizedUserRole}"`);
                    if (isExplicitlyDisabled) {
                        console.log(`   🔒 Modul ${module.id} ist explizit gesperrt (enabled=false) - wird NICHT angezeigt`);
                    } else if (!isModuleEnabled && !isFreeModule) {
                        console.log(`   ⚠️ Modul ${module.id} ist NICHT für Firma ${companyId} aktiviert (kunden/${companyId}/modules/${module.id} fehlt oder enabled=false)`);
                    }
                    if (!hasRoleAccess) {
                        console.log(`   ⚠️ Modul ${module.id}: Benutzer-Rolle "${normalizedUserRole}" hat KEINEN Zugriff`);
                    }
                }
                
                // Home ist immer sichtbar (kostenlos und Basis-Modul)
                if (module.id === 'home') {
                    return true;
                }

                // Admin-Module: Kundenverwaltung nur für Superadmin
                if (module.id === 'kundenverwaltung' && normalizedUserRole !== 'superadmin') {
                    return false;
                }

                // Mitgliederverwaltung: Nur für Superadmin, Admin und Rettungsdienstleiter
                if (module.id === 'admin' && !['superadmin', 'admin', 'rettungsdienstleiter'].includes(normalizedUserRole)) {
                    return false;
                }

                return isModuleEnabled && hasRoleAccess;
            })
            .sort((a, b) => (a.order || 999) - (b.order || 999));
        
        // 🔥 Erweitere Module mit Submenüs (falls in Firestore nicht vorhanden)
        visibleModules = visibleModules.map(module => {
            // Wenn Modul bereits submenu hat, nichts ändern
            if (module.submenu && Array.isArray(module.submenu) && module.submenu.length > 0) {
                return module;
            }
            
            // Office-Modul: Füge E-Mail als Submenu hinzu
            if (module.id === 'office') {
                return {
                    ...module,
                    submenu: [
                        {
                            id: 'email',
                            label: 'E-Mail',
                            url: '/module/office/email.html',
                            page: '/module/office/email.html'
                        }
                    ]
                };
            }
            
            return module;
        });
        
        return visibleModules;
    } catch (error) {
        console.error("Fehler beim Laden der Benutzer-Module:", error);
        // Fallback: Nur Home anzeigen
        return getDefaultModulesForRole(userRole);
    }
}