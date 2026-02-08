// Script zum Prüfen und Anlegen des Superadmin-Benutzers
// Führe dies in der Browser-Console aus, nachdem du als Superadmin eingeloggt bist

import { auth, db } from "./firebase-config.js";
import { doc, getDoc, setDoc } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

async function checkAndCreateSuperadmin() {
    const user = auth.currentUser;
    
    if (!user) {
        console.error("❌ Kein Benutzer eingeloggt!");
        return;
    }
    
    console.log(`🔍 Prüfe Superadmin-Benutzer: ${user.email} (UID: ${user.uid})`);
    
    const userRef = doc(db, "kunden", "admin", "users", user.uid);
    const userSnap = await getDoc(userRef);
    
    if (userSnap.exists()) {
        const userData = userSnap.data();
        console.log("✅ Superadmin-Benutzer existiert bereits:");
        console.log("   Email:", userData.email);
        console.log("   Rolle:", userData.role);
        console.log("   Status:", userData.status);
    } else {
        console.log("⚠️ Superadmin-Benutzer existiert NICHT in Firestore!");
        console.log("   Erstelle jetzt...");
        
        try {
            await setDoc(userRef, {
                email: user.email,
                role: "superadmin",
                companyId: "admin",
                createdAt: new Date(),
                status: true
            });
            
            console.log("✅ Superadmin-Benutzer erfolgreich erstellt!");
        } catch (error) {
            console.error("❌ Fehler beim Erstellen:", error);
            console.error("   Stelle sicher, dass die Firestore Rules erlauben, dass du dich selbst anlegst.");
        }
    }
}

// Führe die Prüfung aus
checkAndCreateSuperadmin();








