// Debug-Script: Testet Firestore-Zugriffe
// Führe in der Browser-Konsole aus (nach Login)

import { db } from "./firebase-config.js";
import { doc, getDoc, collection, getDocs } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

async function testFirestoreAccess() {
    console.log("🔍 Teste Firestore-Zugriffe...\n");
    
    const userId = "sM4eleebk0aPwz4qOWT0I7KRZAk1";
    const companyId = "admin";
    
    // Test 1: Globale Module
    console.log("1️⃣ Teste: modules/");
    try {
        const modulesRef = collection(db, "modules");
        const modulesSnap = await getDocs(modulesRef);
        console.log("✅ modules/ - ERFOLG:", modulesSnap.size, "Module gefunden");
        modulesSnap.forEach(doc => {
            console.log("   -", doc.id, ":", doc.data().label);
        });
    } catch (error) {
        console.error("❌ modules/ - FEHLER:", error.code, error.message);
    }
    
    // Test 2: Firmen-Module
    console.log("\n2️⃣ Teste: kunden/admin/modules/");
    try {
        const companyModulesRef = collection(db, "kunden", companyId, "modules");
        const companyModulesSnap = await getDocs(companyModulesRef);
        console.log("✅ kunden/admin/modules/ - ERFOLG:", companyModulesSnap.size, "Module gefunden");
        companyModulesSnap.forEach(doc => {
            console.log("   -", doc.id, ":", doc.data());
        });
    } catch (error) {
        console.error("❌ kunden/admin/modules/ - FEHLER:", error.code, error.message);
        console.error("   → Das ist der Hauptfehler! Die Rules blockieren diesen Pfad.");
    }
    
    // Test 3: User-Tiles
    console.log("\n3️⃣ Teste: kunden/admin/users/{uid}/userTiles/config");
    try {
        const tilesRef = doc(db, "kunden", companyId, "users", userId, "userTiles", "config");
        const tilesSnap = await getDoc(tilesRef);
        if (tilesSnap.exists()) {
            console.log("✅ userTiles/config - ERFOLG:", tilesSnap.data());
        } else {
            console.log("⚠️ userTiles/config - NICHT GEFUNDEN (aber Zugriff erlaubt)");
        }
    } catch (error) {
        console.error("❌ userTiles/config - FEHLER:", error.code, error.message);
    }
    
    // Test 4: User-Dokument
    console.log("\n4️⃣ Teste: kunden/admin/users/{uid}");
    try {
        const userRef = doc(db, "kunden", companyId, "users", userId);
        const userSnap = await getDoc(userRef);
        if (userSnap.exists()) {
            console.log("✅ users/{uid} - ERFOLG:", userSnap.data());
        } else {
            console.log("⚠️ users/{uid} - NICHT GEFUNDEN");
        }
    } catch (error) {
        console.error("❌ users/{uid} - FEHLER:", error.code, error.message);
    }
    
    console.log("\n📋 Zusammenfassung:");
    console.log("Wenn Test 2 (kunden/admin/modules/) fehlschlägt:");
    console.log("→ Die Wildcard-Regel greift nicht für modules/");
    console.log("→ Du brauchst eine explizite Regel für kunden/{kundenId}/modules/{moduleId}");
}

// Exportiere für Konsole
window.testFirestoreAccess = testFirestoreAccess;

console.log("💡 Debug-Script geladen!");
console.log("📝 Führe aus: await testFirestoreAccess()");




