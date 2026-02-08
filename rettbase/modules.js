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
    orderBy,
    serverTimestamp
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
        roles: ['superadmin', 'admin', 'leiterssd'],
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
        roles: ['superadmin', 'admin', 'supervisor', 'leiterssd', 'wachleitung', 'ovd'],
        free: true,
        order: 2,
        active: true
    },
    office: {
        id: 'office',
        label: 'Office',
        url: '/module/office/office.html',
        icon: 'office',
        roles: ['superadmin', 'admin', 'supervisor', 'leiterssd', 'wachleitung', 'ovd', 'user'],
        free: true,
        order: 3,
        active: true
    },
    'einsatztagebuch---ovd': {
        id: 'einsatztagebuch---ovd',
        label: 'Einsatztagebuch - OVD',
        url: '/module/ovdeinsatztagebuch/ovdeinsatztagebuch.html',
        icon: 'ovd',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'ovd'],
        free: true,
        order: 7,
        active: true
    },
    telefonliste: {
        id: 'telefonliste',
        label: 'Telefonliste',
        url: 'kunden/admin/telefonliste.html',
        icon: 'phone',
        roles: ['superadmin', 'admin', 'leiterssd', 'ovd'],
        free: true,
        order: 8,
        active: true
    },
    einstellungen: {
        id: 'einstellungen',
        label: 'Einstellungen',
        url: 'kunden/admin/einstellungen.html',
        icon: 'einstellungen',
        roles: ['superadmin', 'admin', 'leiterssd'],
        free: true,
        order: 9,
        active: true
    },
    menueverwaltung: {
        id: 'menueverwaltung',
        label: 'Menü-Verwaltung',
        url: 'kunden/admin/menue.html',
        icon: 'menu',
        roles: ['superadmin'],
        free: true,
        order: 10,
        active: true
    },
    fahrzeugmanagement: {
        id: 'fahrzeugmanagement',
        label: 'Flottenmanagement',
        url: '/module/fahrzeugmanagement/fahrzeugmanagement.html',
        icon: 'fahrzeug',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'wachleitung', 'ovd'],
        free: true,
        order: 11,
        active: true
    },
    neuermangel: {
        id: 'neuermangel',
        label: 'Mängelmelder',
        url: '/module/fahrzeugmanagement/neuermangel.html',
        icon: 'maengelmelder',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'wachleitung', 'ovd', 'user'],
        free: true,
        order: 12,
        active: true
    },
    mangeluebersicht: {
        id: 'mangeluebersicht',
        label: 'Mängelübersicht',
        url: '/module/fahrzeugmanagement/mangeluebersicht.html',
        icon: 'maengelmelder',
        roles: ['superadmin', 'admin', 'leiterssd', 'wachleitung', 'ovd', 'fahrzeugbeauftragter'],
        free: true,
        order: 13,
        active: true
    },
    schichtanmeldung: {
        id: 'schichtanmeldung',
        label: 'Schichtanmeldung',
        url: '/module/schichtanmeldung/schichtanmeldung.html',
        icon: 'schichtplan',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter'],
        free: true,
        order: 14,
        active: true
    },
    schichtuebersicht: {
        id: 'schichtuebersicht',
        label: 'Schichtübersicht',
        url: '/module/schichtanmeldung/schichtuebersicht.html',
        icon: 'schichtplan',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter'],
        free: true,
        order: 15,
        active: true
    },
    ssd: {
        id: 'ssd',
        label: 'SSD',
        url: '/module/ssd/notfallprotokoll-ssd.html',
        icon: 'ssd',
        roles: ['superadmin', 'admin', 'leiterssd', 'supervisor', 'wachleitung', 'ovd', 'user'],
        free: true,
        order: 16,
        active: true
    },
    chat: {
        id: 'chat',
        label: 'Chat',
        url: '/module/chat/chat.html',
        icon: 'chat',
        roles: ['superadmin', 'admin', 'supervisor', 'leiterssd', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter'],
        free: true,
        order: 17,
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
        // Korrigierter Pfad: settings/modules als Document mit Subcollection "items"
        const settingsDocRef = doc(db, "settings", "modules");
        const modulesCollection = collection(settingsDocRef, "items");
        const snap = await getDocs(query(modulesCollection, orderBy("order", "asc")));
        
        const modules = {};
        snap.forEach((docSnap) => {
            const data = docSnap.data();
            modules[docSnap.id] = {
                id: docSnap.id,
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
        const mergedModules = { ...DEFAULT_MODULES };
        console.log(`📦 DEFAULT_MODULES enthalten:`, Object.keys(DEFAULT_MODULES));
        console.log(`📦 Firestore-Module enthalten:`, Object.keys(modules));
        
        Object.keys(modules).forEach(moduleId => {
            const firestoreModule = modules[moduleId];
            const defaultModule = DEFAULT_MODULES[moduleId];
            
            if (defaultModule) {
                // Modul existiert in beiden: Merge Rollen
                let mergedRoles = [];
                if (firestoreModule.roles && Array.isArray(firestoreModule.roles) && firestoreModule.roles.length > 0) {
                    const firestoreRoles = firestoreModule.roles.map(r => String(r).toLowerCase().trim());
                    const defaultRoles = defaultModule.roles.map(r => String(r).toLowerCase().trim());
                    mergedRoles = [...new Set([...firestoreRoles, ...defaultRoles])];
                } else {
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
        
        console.log(`📦 Merged-Module enthalten:`, Object.keys(mergedModules));
        console.log(`📦 Flottenmanagement in mergedModules:`, mergedModules['fahrzeugmanagement'] ? '✅ Ja' : '❌ Nein');
        if (mergedModules['fahrzeugmanagement']) {
            console.log(`📦 Flottenmanagement-Details:`, JSON.stringify(mergedModules['fahrzeugmanagement'], null, 2));
        }
        
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
        // Korrigierter Pfad: settings/modules als Document mit Subcollection "items/{moduleId}"
        const settingsDocRef = doc(db, "settings", "modules");
        const modulesCollection = collection(settingsDocRef, "items");
        const moduleRef = doc(modulesCollection, moduleId);
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
 * @returns {Promise<string>} Modul-ID
 */
export async function saveModule(moduleData) {
    try {
        const moduleId = moduleData.id || moduleData.label.toLowerCase().replace(/\s+/g, '-');
        
        const dataToSave = {
            label: moduleData.label,
            url: moduleData.url,
            icon: moduleData.icon || 'default',
            roles: moduleData.roles || ['user'],
            free: moduleData.free !== undefined ? moduleData.free : true,
            order: moduleData.order || 999,
            active: moduleData.active !== undefined ? moduleData.active : true,
            updatedAt: serverTimestamp()
        };
        
        // Korrigierter Pfad: settings/modules als Document mit Subcollection "items/{moduleId}"
        // Stelle sicher, dass das Parent-Document existiert
        const settingsDocRef = doc(db, "settings", "modules");
        await setDoc(settingsDocRef, { _exists: true }, { merge: true });
        
        const modulesCollection = collection(settingsDocRef, "items");
        const moduleRef = doc(modulesCollection, moduleId);
        const moduleSnap = await getDoc(moduleRef);
        
        if (moduleSnap.exists()) {
            // Dokument existiert - Update
            await setDoc(moduleRef, dataToSave, { merge: true });
        } else {
            // Dokument existiert nicht - Create
            dataToSave.createdAt = serverTimestamp();
            await setDoc(moduleRef, dataToSave);
        }
        
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
        
        // Korrigierter Pfad: settings/modules als Document mit Subcollection "items/{moduleId}"
        const settingsDocRef = doc(db, "settings", "modules");
        const modulesCollection = collection(settingsDocRef, "items");
        const moduleRef = doc(modulesCollection, moduleId);
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
        // Stelle sicher, dass das Parent-Document existiert
        const settingsDocRef = doc(db, "settings", "modules");
        await setDoc(settingsDocRef, { _exists: true }, { merge: true });
        
        let initializedCount = 0;
        for (const [moduleId, moduleData] of Object.entries(DEFAULT_MODULES)) {
            try {
                // Korrigierter Pfad: settings/modules als Document mit Subcollection "items/{moduleId}"
                const modulesCollection = collection(settingsDocRef, "items");
                const moduleRef = doc(modulesCollection, moduleId);
                const moduleSnap = await getDoc(moduleRef);
                
                if (!moduleSnap.exists()) {
                    // Dokument existiert nicht - Create
                    const dataToSave = {
                        ...moduleData,
                        createdAt: serverTimestamp(),
                        updatedAt: serverTimestamp()
                    };
                    await setDoc(moduleRef, dataToSave);
                    console.log(`✅ Standard-Modul '${moduleId}' initialisiert`);
                    initializedCount++;
                } else {
                    // 🔥 WICHTIG: Aktualisiere auch bestehende Module, um sicherzustellen, dass neue Felder hinzugefügt werden
                    const existingData = moduleSnap.data();
                    const needsUpdate = !existingData.label || !existingData.url || !existingData.roles;
                    
                    if (needsUpdate) {
                        const dataToSave = {
                            ...moduleData,
                            ...existingData, // Behalte bestehende Daten
                            updatedAt: serverTimestamp()
                        };
                        await setDoc(moduleRef, dataToSave, { merge: true });
                        console.log(`🔄 Standard-Modul '${moduleId}' aktualisiert`);
                    }
                }
            } catch (error) {
                console.error(`⚠️ Fehler beim Initialisieren des Moduls ${moduleId}:`, error);
            }
        }
        console.log(`✅ Standard-Module initialisiert (${initializedCount} neu, ${Object.keys(DEFAULT_MODULES).length - initializedCount} bereits vorhanden)`);
    } catch (error) {
        console.error("Fehler beim Initialisieren der Standard-Module:", error);
    }
}

/**
 * Lädt die freigeschalteten Module für eine Firma
 * Firestore-Struktur: kunden/{companyId}/modules/{moduleId}
 * @param {string} companyId - Die Firmen-ID
 * @returns {Promise<Object>} Objekt mit moduleId -> enabled Status
 */
export async function getCompanyModules(companyId) {
    try {
        // 🔥 KORRIGIERT: Pfad von "einstellungen/module" zu "modules" geändert
        // Firestore Collections müssen eine ungerade Anzahl von Segmenten haben
        // kunden/{companyId}/modules = 3 Segmente (ungerade) ✓
        const modulesRef = collection(db, "kunden", companyId, "modules");
        const snap = await getDocs(modulesRef);
        
        const enabledModules = {};
        snap.forEach((docSnap) => {
            const data = docSnap.data();
            // 🔥 WICHTIG: Wenn enabled nicht explizit gesetzt ist, sollte es als false behandelt werden
            // Aber wenn das Dokument existiert, sollte enabled immer gesetzt sein (durch setCompanyModule)
            enabledModules[docSnap.id] = data.enabled === true;
        });
        
        console.log(`📋 Geladene Module für Firma ${companyId}:`, Object.keys(enabledModules).length, "Module");
        Object.entries(enabledModules).forEach(([moduleId, enabled]) => {
            console.log(`   - ${moduleId}: ${enabled ? '✅ freigeschaltet' : '❌ nicht freigeschaltet'}`);
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
        // 🔥 KORRIGIERT: Pfad von "einstellungen/module" zu "modules" geändert
        // Firestore Collections müssen eine ungerade Anzahl von Segmenten haben
        // kunden/{companyId}/modules = 3 Segmente (ungerade) ✓
        // kunden/{companyId}/modules/{moduleId} = 4 Segmente (gerade, für Document) ✓
        const moduleCollection = collection(db, "kunden", companyId, "modules");
        const moduleRef = doc(moduleCollection, moduleId);
        
        const dataToSave = {
            enabled: enabled,
            updatedAt: serverTimestamp()
        };
        
        const moduleSnap = await getDoc(moduleRef);
        
        if (moduleSnap.exists()) {
            // Dokument existiert - Update
            await setDoc(moduleRef, dataToSave, { merge: true });
        } else {
            // Dokument existiert nicht - Create
            dataToSave.createdAt = serverTimestamp();
            await setDoc(moduleRef, dataToSave);
        }
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
        
        // 🔥 WICHTIG: Firma "admin" hat IMMER ALLES frei (Superadmin-Firma)
        const isAdminCompany = companyId === 'admin';
        
        // Lade freigeschaltete Module der Firma (nur für nicht-admin Firmen relevant)
        const companyModules = isAdminCompany ? {} : await getCompanyModules(companyId);
        if (isAdminCompany) {
            console.log(`🏢 Admin-Firma: Alle Module sind automatisch freigeschaltet`);
        } else {
            console.log(`🏢 Freigeschaltete Module für ${companyId}:`, companyModules);
        }
        
        // Filtere Module: Muss aktiv sein, freigeschaltet sein UND Benutzer-Rolle muss erlaubt sein
        console.log(`🔍 Filtere Module für companyId=${companyId}, userRole=${userRole}`);
        console.log(`🔍 allModules enthält:`, Object.keys(allModules));
        console.log(`🔍 Flottenmanagement in allModules:`, allModules['fahrzeugmanagement'] ? '✅ Ja' : '❌ Nein');
        
        let visibleModules = Object.values(allModules)
            .filter(module => {
                console.log(`🔍 Prüfe Modul: ${module.id} (active=${module.active}, label=${module.label})`);
                
                // Modul muss aktiv sein
                if (module.active === false) {
                    console.log(`   ❌ Modul ${module.id} ist nicht aktiv`);
                    return false;
                }
                
                // 🔥 WICHTIG: Home ist IMMER sichtbar (Basis-Modul)
                if (module.id === 'home') {
                    console.log(`   ✅ Modul ${module.id} ist Home - immer sichtbar`);
                    return true;
                }
                
                // 🔥 WICHTIG: Admin-Firma hat IMMER ALLES frei (keine Freischaltung und keine Rollenprüfung nötig)
                if (isAdminCompany) {
                    // Für admin-Firma: Alle aktiven Module sind automatisch sichtbar, unabhängig von der Rolle
                    console.log(`   ✅ Modul ${module.id} ist für Admin-Firma automatisch sichtbar (keine Rollenprüfung)`);
                    return true;
                }
                
                // Für andere Firmen: Module müssen explizit freigeschaltet sein
                const moduleStatus = companyModules[module.id]; // kann true, false oder undefined sein
                const isEnabled = moduleStatus === true;
                const isExplicitlyDisabled = moduleStatus === false; // Explizit auf false gesetzt
                const isNotSet = moduleStatus === undefined; // Nicht in Firestore gesetzt
                
                // 🔥 NEUE LOGIK: Alle Module (außer home) müssen explizit freigeschaltet sein (enabled: true)
                // Wenn ein Modul nicht gesetzt ist (undefined) oder auf false gesetzt wurde, wird es NICHT angezeigt
                if (!isEnabled) {
                    if (isExplicitlyDisabled) {
                        console.log(`   🔒 Modul ${module.id} ist explizit gesperrt für Firma ${companyId} (enabled=false)`);
                    } else if (isNotSet) {
                        console.log(`   🔒 Modul ${module.id} ist NICHT freigeschaltet für Firma ${companyId} (nicht in Firestore gesetzt)`);
                    }
                    return false;
                }
                
                // Prüfe, ob Benutzer-Rolle Zugriff hat (CASE-INSENSITIVE)
                let hasRoleAccess = false;
                if (module.roles && Array.isArray(module.roles)) {
                    const normalizedModuleRoles = module.roles.map(r => String(r).toLowerCase().trim());
                    hasRoleAccess = normalizedModuleRoles.includes(normalizedUserRole);
                } else {
                    console.warn(`⚠️ Modul ${module.id} hat keine roles-Array oder roles ist kein Array:`, module.roles);
                }

                // Admin-Module: Kundenverwaltung nur für Superadmin
                if (module.id === 'kundenverwaltung' && normalizedUserRole !== 'superadmin') {
                    return false;
                }

                // Mitgliederverwaltung: Nur für Superadmin, Admin und Rettungsdienstleiter
                if (module.id === 'admin' && !['superadmin', 'admin', 'leiterssd'].includes(normalizedUserRole)) {
                    return false;
                }

                // Einstellungen: Nur für Admin und Rettungsdienstleiter
                if (module.id === 'einstellungen' && !['superadmin', 'admin', 'leiterssd'].includes(normalizedUserRole)) {
                    return false;
                }

                // Menü-Verwaltung: Nur für Superadmin
                if (module.id === 'menueverwaltung' && normalizedUserRole !== 'superadmin') {
                    return false;
                }

                return hasRoleAccess;
            })
            .sort((a, b) => (a.order || 999) - (b.order || 999));
        
        // 🔥 Erweitere Module mit Submenüs (falls in Firestore nicht vorhanden)
        visibleModules = visibleModules.map(module => {
            // Wenn Modul bereits submenu hat, nichts ändern
            if (module.submenu && Array.isArray(module.submenu) && module.submenu.length > 0) {
                return module;
            }
            
            // Office-Modul: Füge E-Mail und Chat als Submenu hinzu
            if (module.id === 'office') {
                return {
                    ...module,
                    submenu: [
                        {
                            id: 'email',
                            label: 'E-Mail',
                            url: '/module/office/email.html',
                            page: '/module/office/email.html'
                        },
                        {
                            id: 'chat',
                            label: 'Chat',
                            url: '/module/chat/chat.html',
                            page: '/module/chat/chat.html'
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
