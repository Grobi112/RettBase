// Initialisierungs-Script für Firestore
// Führe dieses Script einmalig in der Browser-Konsole aus (nach Login als Superadmin)
// 
// ANLEITUNG:
// 1. Öffne die Browser-Konsole (F12)
// 2. Kopiere und führe aus:
//    import('./init-firestore.js').then(m => m.initializeFirestore())
// 3. Oder: await initializeFirestore()

import { db } from "./firebase-config.js";
import { initializeDefaultModules, setCompanyModules } from "./modules.js";
import { doc, setDoc, getDoc } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

/**
 * Initialisiert die komplette Datenbankstruktur für einen Superadmin
 * @param {string} companyId - Die Firmen-ID (z.B. "admin")
 * @param {string} userId - Die User-UID
 */
async function initializeFirestore(companyId = "admin", userId = "sM4eleebk0aPwz4qOWT0I7KRZAk1") {
    console.log("🚀 Starte Firestore-Initialisierung...");
    
    try {
        // 1. Standard-Module in Firestore anlegen
        console.log("📦 Initialisiere Standard-Module...");
        await initializeDefaultModules();
        
        // 2. Module für die Firma freischalten
        console.log(`🔓 Schalte Module für Firma '${companyId}' frei...`);
        const modulesToEnable = {
            'home': true,           // Immer aktiv
            'admin': true,          // Mitgliederverwaltung
            'kundenverwaltung': true, // Kundenverwaltung
            'modulverwaltung': true   // Modul-Verwaltung
        };
        await setCompanyModules(companyId, modulesToEnable);
        
        // 3. Standard-Tiles für den Benutzer anlegen (falls noch nicht vorhanden)
        console.log(`🎨 Lege Standard-Tiles für Benutzer an...`);
        const tilesRef = doc(db, "kunden", companyId, "users", userId, "userTiles", "config");
        const tilesSnap = await getDoc(tilesRef);
        
        if (!tilesSnap.exists()) {
            const defaultTiles = [
                { label: "Mitglieder", page: "kunden/admin/admin.html" },
                { label: "Kunden", page: "kunden/admin/kundenverwaltung.html" },
                { label: "Module", page: "kunden/admin/modulverwaltung.html" },
                null, null, null, null, null, null
            ];
            
            await setDoc(tilesRef, { tiles: defaultTiles });
            console.log("✅ Standard-Tiles angelegt");
        } else {
            console.log("ℹ️ Tiles existieren bereits");
        }
        
        console.log("✅ Firestore-Initialisierung abgeschlossen!");
        console.log("🔄 Bitte Seite neu laden, um die Änderungen zu sehen.");
        
    } catch (error) {
        console.error("❌ Fehler bei der Initialisierung:", error);
        console.error("Details:", error.message);
    }
}

// Exportiere die Funktion für die Konsole
window.initializeFirestore = initializeFirestore;

console.log("💡 Initialisierungs-Script geladen!");
console.log("📝 Führe aus: await initializeFirestore('admin', 'sM4eleebk0aPwz4qOWT0I7KRZAk1')");
console.log("   Oder einfach: initializeFirestore()");

