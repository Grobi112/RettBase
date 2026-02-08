// Datei: auth.js

import { auth, db } from "./firebase-config.js"; 
import { 
    onAuthStateChanged, 
    signOut, 
    signInWithEmailAndPassword,
    createUserWithEmailAndPassword,
    updatePassword
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js"; 
import { 
    collectionGroup, 
    query, 
    where, 
    getDocs, 
    documentId,
    doc, // Import für direkte Abfrage
    getDoc, // Import für direkte Abfrage
    setDoc, // Import für setDoc
    collection // Import für Collection-Abfragen
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";


function getKundenIdFromSubdomain() {
    const hostname = window.location.hostname; 
    const rootDomain = 'rettbase.de'; 

    if (hostname.endsWith(rootDomain)) {
        const parts = hostname.split('.');
        
        if (parts.length > 2) {
            const kundenId = parts[0]; 
            
            if (kundenId !== 'www' && kundenId !== 'login' && kundenId !== 'admin') {
                return kundenId;
            }
        }
    }
    return 'admin'; 
}

/**
 * Prüft, ob ein String eine E-Mail-Adresse ist
 */
function isEmail(str) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(str);
}

/**
 * Erstellt eine Pseudo-Email für Personalnummer-Login
 * Format: {personalnummer}@{companyId}.rettbase.de
 */
function createPseudoEmail(personalnummer, companyId) {
    return `${personalnummer}@${companyId}.rettbase.de`;
}

/**
 * Login-Funktion, die sowohl E-Mail als auch Personalnummer unterstützt
 */
export async function login(emailOrPersonalnummer, password) {
    const companyId = getKundenIdFromSubdomain();
    
    // Prüfe, ob es eine E-Mail oder Personalnummer ist
    if (isEmail(emailOrPersonalnummer)) {
        // E-Mail-Login: Suche Mitarbeiter in Firestore nach E-Mail
        const email = emailOrPersonalnummer.trim();
        
        console.log(`🔍 Suche Mitarbeiter mit E-Mail "${email}" in companyId "${companyId}"`);
        
        // Suche Mitarbeiter nach E-Mail-Adresse
        let mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
        let q = query(mitarbeiterRef, where("email", "==", email));
        let snapshot = await getDocs(q);
        
        // Wenn nicht gefunden und companyId ist "admin", suche auch in anderen Firmen (für Superadmin)
        if (snapshot.empty && companyId === 'admin') {
            console.log(`⚠️ E-Mail "${email}" nicht in kunden/admin/mitarbeiter gefunden. Suche in allen Firmen...`);
            // Collection Group Query über alle mitarbeiter Collections
            const mitarbeiterGroupRef = collectionGroup(db, "mitarbeiter");
            const groupQuery = query(mitarbeiterGroupRef, where("email", "==", email));
            snapshot = await getDocs(groupQuery);
            
            if (!snapshot.empty) {
                console.log(`✅ E-Mail "${email}" in anderer Firma gefunden. Verwende diese Firma für Login.`);
            }
        }
        
        if (snapshot.empty) {
            console.error(`❌ E-Mail "${email}" nicht gefunden in companyId "${companyId}" oder anderen Firmen`);
            throw new Error("auth/user-not-found");
        }
        
        const mitarbeiterDoc = snapshot.docs[0];
        const mitarbeiterData = mitarbeiterDoc.data();
        
        // 🔥 WICHTIG: Wenn die E-Mail in einer anderen Firma gefunden wurde (z.B. via Collection Group Query),
        // extrahiere die tatsächliche companyId aus dem Dokument-Pfad
        let actualCompanyId = companyId;
        if (mitarbeiterDoc.ref.path.includes('/kunden/')) {
            const pathParts = mitarbeiterDoc.ref.path.split('/');
            const kundenIndex = pathParts.indexOf('kunden');
            if (kundenIndex !== -1 && pathParts[kundenIndex + 1]) {
                actualCompanyId = pathParts[kundenIndex + 1];
                console.log(`📂 Tatsächliche companyId aus Dokument-Pfad extrahiert: ${actualCompanyId}`);
            }
        }
        
        // Prüfe ob Mitarbeiter aktiv ist
        if (mitarbeiterData.active === false || mitarbeiterData.status === false) {
            throw new Error("auth/user-disabled");
        }
        
        try {
            // Versuche mit E-Mail einzuloggen
            const userCredential = await signInWithEmailAndPassword(auth, email, password);
            const uid = userCredential.user.uid;
            
            // 🔥 WICHTIG: Aktualisiere IMMER die UID im Mitarbeiter-Dokument (auch wenn Account bereits existiert)
            // Dies stellt sicher, dass die UID immer korrekt gespeichert ist
            // Verwende die tatsächliche companyId, nicht die ursprüngliche
            const mitarbeiterDocRef = doc(db, "kunden", actualCompanyId, "mitarbeiter", mitarbeiterDoc.id);
            const updateData = {
                uid: uid,
                email: email,
                updatedAt: new Date()
            };
            await setDoc(mitarbeiterDocRef, updateData, { merge: true });
            console.log(`✅ UID ${uid} im Mitarbeiter-Dokument ${mitarbeiterDoc.id} (Firma: ${actualCompanyId}) aktualisiert`);
        } catch (error) {
            console.log(`⚠️ Login-Versuch fehlgeschlagen: ${error.code} - ${error.message}`);
            
            // Wenn Account nicht existiert, versuche ihn zu erstellen
            // HINWEIS: Firebase gibt manchmal "auth/invalid-credential" zurück, auch wenn der Account nicht existiert
            // Prüfe daher, ob bereits eine UID im Dokument vorhanden ist
            const existingUid = mitarbeiterData.uid;
            
            if ((error.code === "auth/user-not-found" || error.code === "auth/invalid-credential") && !existingUid) {
                // Keine UID vorhanden - Account wurde noch nicht erstellt, versuche ihn zu erstellen
                console.log(`📝 Keine UID vorhanden - erstelle neuen Firebase Auth Account für ${email}`);
                try {
                    // Erstelle Firebase Auth Account mit E-Mail
                    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
                    const uid = userCredential.user.uid;
                    
                    // Aktualisiere Mitarbeiter-Dokument mit UID
                    // Verwende die tatsächliche companyId, nicht die ursprüngliche
                    const mitarbeiterDocRef = doc(db, "kunden", actualCompanyId, "mitarbeiter", mitarbeiterDoc.id);
                    const updateData = {
                        uid: uid,
                        email: email,
                        updatedAt: new Date()
                    };
                    await setDoc(mitarbeiterDocRef, updateData, { merge: true });
                    console.log(`✅ Neuer Account erstellt und UID ${uid} im Mitarbeiter-Dokument ${mitarbeiterDoc.id} (Firma: ${actualCompanyId}) gespeichert`);
                } catch (createError) {
                    console.error(`❌ Fehler beim Erstellen des Accounts: ${createError.code} - ${createError.message}`);
                    if (createError.code === "auth/email-already-in-use") {
                        // Account existiert bereits, aber UID war nicht im Dokument gespeichert
                        // Das bedeutet, das Passwort war falsch oder der Account wurde manuell erstellt
                        console.log(`⚠️ Account existiert bereits - das eingegebene Passwort ist möglicherweise falsch`);
                        throw error; // Wirf den ursprünglichen Login-Fehler (invalid-credential)
                    } else {
                        throw createError;
                    }
                }
            } else {
                // UID vorhanden oder anderer Fehler - wirf den Fehler weiter
                throw error;
            }
        }
    } else {
        // Personalnummer-Login: Suche Mitarbeiter in Firestore
        const personalnummer = emailOrPersonalnummer.trim();
        
        // Suche Mitarbeiter nach Personalnummer
        const mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
        const q = query(mitarbeiterRef, where("personalnummer", "==", personalnummer));
        const snapshot = await getDocs(q);
        
        if (snapshot.empty) {
            throw new Error("auth/user-not-found");
        }
        
        const mitarbeiterDoc = snapshot.docs[0];
        const mitarbeiterData = mitarbeiterDoc.data();
        
        // Prüfe ob Mitarbeiter aktiv ist
        if (mitarbeiterData.active === false || mitarbeiterData.status === false) {
            throw new Error("auth/user-disabled");
        }
        
        // 🔥 WICHTIG: Prüfe, ob eine echte E-Mail vorhanden ist
        // Wenn ja, verwende diese für den Login (dieselbe E-Mail wie bei E-Mail-Login)
        // Wenn nein, verwende die Pseudo-Email
        const realEmail = mitarbeiterData.email && !mitarbeiterData.email.endsWith(".rettbase.de") 
            ? mitarbeiterData.email 
            : null;
        const loginEmail = realEmail || createPseudoEmail(personalnummer, companyId);
        
        try {
            // Versuche mit der Login-E-Mail einzuloggen (echte E-Mail oder Pseudo-Email)
            const userCredential = await signInWithEmailAndPassword(auth, loginEmail, password);
            const uid = userCredential.user.uid;
            
            // 🔥 WICHTIG: Aktualisiere IMMER die UID im Mitarbeiter-Dokument (auch wenn Account bereits existiert)
            // Dies stellt sicher, dass die UID immer korrekt gespeichert ist
            const mitarbeiterDocRef = doc(db, "kunden", companyId, "mitarbeiter", mitarbeiterDoc.id);
            const updateData = {
                uid: uid,
                updatedAt: new Date()
            };
            // Nur Pseudo-Email setzen, wenn keine echte E-Mail vorhanden ist
            if (!realEmail) {
                updateData.pseudoEmail = loginEmail;
                updateData.email = loginEmail;
            }
            await setDoc(mitarbeiterDocRef, updateData, { merge: true });
            console.log(`✅ UID ${uid} im Mitarbeiter-Dokument ${mitarbeiterDoc.id} aktualisiert (Login mit ${realEmail ? 'echter E-Mail' : 'Pseudo-Email'})`);
        } catch (error) {
            // Wenn Account nicht existiert, erstelle ihn
            if (error.code === "auth/user-not-found" || error.code === "auth/invalid-credential") {
                const existingUid = mitarbeiterData.uid;
                if (!existingUid) {
                    // Erstelle Firebase Auth Account mit Login-E-Mail
                    const userCredential = await createUserWithEmailAndPassword(auth, loginEmail, password);
                    const uid = userCredential.user.uid;
                    
                    // Aktualisiere Mitarbeiter-Dokument mit UID
                    const mitarbeiterDocRef = doc(db, "kunden", companyId, "mitarbeiter", mitarbeiterDoc.id);
                    const updateData = {
                        uid: uid,
                        updatedAt: new Date()
                    };
                    // Nur Pseudo-Email setzen, wenn keine echte E-Mail vorhanden ist
                    if (!realEmail) {
                        updateData.pseudoEmail = loginEmail;
                        updateData.email = loginEmail;
                    }
                    await setDoc(mitarbeiterDocRef, updateData, { merge: true });
                    console.log(`✅ Neuer Account erstellt und UID ${uid} im Mitarbeiter-Dokument ${mitarbeiterDoc.id} gespeichert`);
                } else {
                    // UID vorhanden, aber Login fehlgeschlagen - Passwort ist falsch
                    throw error;
                }
            } else {
                throw error;
            }
        }
    }
}

/**
 * Ruft die Benutzerrolle und CompanyId aus Firestore ab.
 * 🔥 TEMPORÄRE LÖSUNG: Versucht zuerst, den User direkt über den Pfad zu finden.
 */
export async function getAuthData(uid, email) { 
    const requestedSubdomain = getKundenIdFromSubdomain(); // Subdomain aus URL
    let requestedKundenId = requestedSubdomain; // Standard: Subdomain = companyId
    
    console.log(`🔍 getAuthData aufgerufen: uid=${uid}, email=${email}, subdomain=${requestedSubdomain}`);
    
    if (!uid || !email) {
        console.warn("⚠️ Keine UID oder Email - gebe guest zurück");
        return { role: 'guest', companyId: requestedKundenId, uid: null }; 
    }

    try {
        // --- 0. PRÜFE OB SUBDOMAIN IN FIRESTORE EXISTIERT ---
        // Für 'admin' (Superadmin) verwenden wir immer 'admin' als companyId
        if (requestedSubdomain === 'admin') {
            requestedKundenId = 'admin';
        } else {
            // Für andere Subdomains: Prüfe ob die Subdomain als companyId existiert
            const companyRef = doc(db, "kunden", requestedSubdomain);
            const companySnap = await getDoc(companyRef);
            
            if (companySnap.exists()) {
                requestedKundenId = companySnap.id; // companyId bleibt die Dokument-ID
            } else {
                // Falls nicht gefunden, suche nach Subdomain-Feld in allen Firmen
                // (wird später implementiert, falls nötig)
                requestedKundenId = requestedSubdomain;
            }
        }
        
        // --- 1. VERSUCH: DIREKTE ABFRAGE DES BENUTZERS (Umgeht Index-Problem und ist am schnellsten) ---
        // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Pfad: kunden/{requestedKundenId}/mitarbeiter/{uid}
        const directDocRef = doc(db, "kunden", requestedKundenId, "mitarbeiter", uid);
        console.log(`📂 [1] Suche Benutzer direkt unter: kunden/${requestedKundenId}/mitarbeiter/${uid}`);
        const directSnap = await getDoc(directDocRef);
        
        // Falls nicht gefunden, versuche auch die alte users Collection (für Migration)
        let userData = null;
        let userKundenId = null;
        if (directSnap.exists()) {
          userData = directSnap.data();
          userKundenId = directSnap.ref.parent.parent.id;
          console.log(`✅ [1] Benutzer direkt gefunden in kunden/${userKundenId}/mitarbeiter/${uid}, Rolle: ${userData.role}`);
        } else {
          console.log(`❌ [1] Direkte Abfrage fehlgeschlagen (Dokument existiert nicht)`);
          
          // Fallback 1: Versuche alte users Collection
          const oldUsersDocRef = doc(db, "kunden", requestedKundenId, "users", uid);
          const oldUsersSnap = await getDoc(oldUsersDocRef);
          if (oldUsersSnap.exists()) {
            console.log(`⚠️ [1-Fallback] Benutzer in alter users Collection gefunden, sollte migriert werden`);
            userData = oldUsersSnap.data();
            userKundenId = oldUsersSnap.ref.parent.parent.id;
          } else {
            // Fallback 2: Suche nach UID-Feld in der mitarbeiter Collection (wenn uid != documentId)
            console.log(`🔄 [1-Fallback] Suche nach uid-Feld in mitarbeiter Collection...`);
            try {
              const mitarbeiterRef = collection(db, "kunden", requestedKundenId, "mitarbeiter");
              const uidQuery = query(mitarbeiterRef, where("uid", "==", uid));
              const uidSnapshot = await getDocs(uidQuery);
              
              if (!uidSnapshot.empty) {
                const mitarbeiterDoc = uidSnapshot.docs[0];
                userData = mitarbeiterDoc.data();
                userKundenId = mitarbeiterDoc.ref.parent.parent.id;
                console.log(`✅ [1-Fallback] Benutzer gefunden über uid-Feld in kunden/${userKundenId}/mitarbeiter/${mitarbeiterDoc.id}, Rolle: ${userData.role}`);
              } else {
                console.log(`❌ [1-Fallback] Kein Mitarbeiter mit uid="${uid}" gefunden`);
              }
            } catch (queryError) {
              console.warn(`⚠️ [1-Fallback] Query nach uid-Feld fehlgeschlagen:`, queryError);
            }
          }
        }
        
        if (userData) {
          console.log(`✅ Benutzer gefunden in kunden/${userKundenId}/mitarbeiter/${uid}`);
          console.log(`📋 Benutzer-Daten:`, { role: userData.role, active: userData.active, status: userData.status });
          
          // 🔥 NEU: Prüfe das Feld 'status' oder 'active' nur, wenn es existiert und false ist
          if (userData.status === false || userData.active === false) {
            console.warn("Benutzer ist inaktiv (status/active: false). Logout wird erzwungen.");
            await logout(); 
            return { role: 'guest', companyId: requestedKundenId, uid: null };
          }

          // Rolle aus userData lesen (BEVOR andere Checks)
          // Konvertiere zu Kleinbuchstaben für Vergleich
          const role = (userData.role || 'user').toLowerCase(); 
          console.log(`🔍 Rolle aus Firestore: "${userData.role}" → konvertiert zu: "${role}"`);
          const validRoles = ['superadmin', 'admin', 'supervisor', 'rettungsdienstleiter', 'wachleitung', 'ovd', 'user'];
          const finalRole = validRoles.includes(role) ? role : 'user';
          console.log(`✅ Finale Rolle: "${finalRole}" (gültig: ${validRoles.includes(role)})`);

          // KRITISCHE PRÜFUNG (Subdomain-Check) - nur für Non-Admin Kunden notwendig
          // Superadmin kann sich immer in 'admin' einloggen
          if (userKundenId !== requestedKundenId && userKundenId !== 'admin' && requestedKundenId !== 'admin') {
            await logout(); 
            return { role: 'guest', companyId: requestedKundenId, uid: null };
          }
          
          // Wenn Superadmin auf admin.rettbase.de geht, erlaube Zugriff
          if (finalRole === 'superadmin' && requestedKundenId === 'admin') {
            return {
              role: 'superadmin',
              companyId: 'admin',
              uid: uid
            };
          }

          // Daten direkt abgerufen
          return {
            role: finalRole,
            companyId: userKundenId, 
            uid: uid
          };
        }
        
        // --- 2. FALLBACK: Collection Group Query (Wenn der direkte Pfad fehlschlägt) ---
        // Dies fängt den Fall ab, dass der Benutzer zwar eingeloggt ist, aber die CompanyId in der URL 
        // nicht mit seiner tatsächlichen CompanyId übereinstimmt (wenn er z.B. fälschlicherweise eine andere Subdomain besucht).
        
        console.warn(`⚠️ [2] Direkter Kunden-Abruf für ${requestedKundenId} fehlgeschlagen. Benutzer existiert nicht unter kunden/${requestedKundenId}/mitarbeiter/${uid}`);
        console.warn(`🔄 [2] Versuche Collection Group Query...`);
        
        // 🔥 NEUE ZENTRALE MITARBEITER-COLLECTION: Suche zuerst nach uid, dann nach email
        let snapshot = null;
        try {
          // Versuche 1: Suche nach uid-Feld in mitarbeiter Collection
          console.log(`🔍 [2] Suche nach uid="${uid}" in mitarbeiter Collection...`);
          const mitarbeiterRef = collectionGroup(db, 'mitarbeiter');
          const uidQuery = query(mitarbeiterRef, where('uid', '==', uid)); 
          snapshot = await getDocs(uidQuery);
          
          if (!snapshot.empty) {
            console.log(`✅ [2] Mitarbeiter gefunden über uid-Feld: ${snapshot.docs.length} Dokument(e)`);
          } else if (email) {
            // Versuche 2: Suche nach email-Feld in mitarbeiter Collection
            console.log(`🔄 [2] Suche nach uid fehlgeschlagen, versuche email="${email}"...`);
            const emailQuery = query(mitarbeiterRef, where('email', '==', email)); 
            snapshot = await getDocs(emailQuery);
            if (!snapshot.empty) {
              console.log(`✅ [2] Mitarbeiter gefunden über email-Feld: ${snapshot.docs.length} Dokument(e)`);
            } else {
              console.log(`❌ [2] Kein Mitarbeiter mit email="${email}" gefunden`);
            }
          }
        } catch (error) {
          console.warn(`⚠️ [2] Collection Group Query für mitarbeiter fehlgeschlagen:`, error);
          // Fallback: Versuche alte users Collection
          try {
            console.log(`🔄 [2-Fallback] Versuche alte users Collection...`);
            const usersRef = collectionGroup(db, 'users');
            const q = query(usersRef, where('email', '==', email)); 
            snapshot = await getDocs(q);
            if (!snapshot.empty) {
              console.log(`✅ [2-Fallback] Benutzer in users Collection gefunden: ${snapshot.docs.length} Dokument(e)`);
            }
          } catch (usersError) {
            console.warn(`⚠️ [2-Fallback] Collection Group Query für users fehlgeschlagen:`, usersError);
          }
        }

        if (!snapshot || snapshot.empty) {
            console.error(`❌ [2] Benutzerdokument für UID ${uid} (Email: ${email}) nicht gefunden.`);
            console.error(`❌ [2] Mögliche Ursachen:`);
            console.error(`    - Mitarbeiter-Dokument existiert nicht in kunden/${requestedKundenId}/mitarbeiter`);
            console.error(`    - uid-Feld im Mitarbeiter-Dokument stimmt nicht überein`);
            console.error(`    - email-Feld im Mitarbeiter-Dokument stimmt nicht überein`);
            return { role: 'guest', companyId: requestedKundenId, uid: uid }; 
        }

        const docSnap = snapshot.docs[0];
        const fallbackUserData = docSnap.data();
        const fallbackUserKundenId = docSnap.ref.parent.parent.id;
        // Konvertiere zu Kleinbuchstaben für Vergleich
        const userRole = (fallbackUserData.role || 'user').toLowerCase();

        // 🔥 NEU: Superadmin kann sich in jede Firma einloggen
        // Wenn Superadmin auf eine Kunden-Subdomain geht, erhält er Admin-Rechte in dieser Firma
        if (userRole === 'superadmin' && requestedKundenId !== 'admin' && requestedKundenId !== fallbackUserKundenId) {
            // Prüfe, ob die angeforderte Firma existiert
            const companyRef = doc(db, "kunden", requestedKundenId);
            const companySnap = await getDoc(companyRef);
            
            if (companySnap.exists()) {
                console.log(`✅ Superadmin erhält temporären Admin-Zugriff auf Firma '${requestedKundenId}'`);
                return {
                    role: 'admin', // Superadmin erhält Admin-Rechte in der Kunden-Firma
                    companyId: requestedKundenId,
                    uid: uid,
                    isSuperadmin: true // Flag für später
                };
            }
        }

        const validRoles = ['superadmin', 'admin', 'supervisor', 'rettungsdienstleiter', 'wachleitung', 'ovd', 'user'];
        const finalRole = validRoles.includes(userRole) ? userRole : 'user';

        return {
            role: finalRole,
            companyId: fallbackUserKundenId, 
            uid: uid
        };


    } catch (error) {
        console.error("❌ Schwerer Fehler beim Abrufen der Auth-Daten:", error);
        console.error("   Fehler-Details:", error.message);
        console.error("   Fehler-Code:", error.code);
        console.error("   Requested KundenId:", requestedKundenId);
        console.error("   UID:", uid);
        return { role: 'guest', companyId: requestedKundenId, uid: uid };
    }
}

export async function logout() {
    try {
        await signOut(auth);
        console.log("Benutzer abgemeldet. Seite wird neu geladen.");
        window.location.reload(); 
    } catch (error) {
        console.error("Fehler beim Abmelden:", error);
    }
}

export { auth };
export { db };
export { onAuthStateChanged };
export { getKundenIdFromSubdomain };