// Datei: auth.js
// Verwaltet Benutzer-Authentifizierung mit Firebase Auth und Firestore

import { auth, db } from "./firebase-config.js"; 
import { 
    onAuthStateChanged, 
    signOut, 
    signInWithEmailAndPassword,
    createUserWithEmailAndPassword,
    updatePassword,
    sendPasswordResetEmail
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js"; 
import { 
    collectionGroup, 
    query, 
    where, 
    getDocs, 
    documentId,
    doc, 
    getDoc, 
    setDoc, 
    updateDoc,
    collection,
    serverTimestamp
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
    
    // Warte, bis Firebase Auth initialisiert ist (vermeidet Fehler bei erstem Laden / nach Cache-Leeren)
    try {
        if (auth && typeof auth.authStateReady === 'function') {
            await auth.authStateReady();
        }
    } catch (e) {
        console.warn("authStateReady:", e);
    }
    
    // Prüfe, ob es eine E-Mail oder Personalnummer ist
    if (isEmail(emailOrPersonalnummer)) {
        // E-Mail-Login: Suche Mitarbeiter in Firestore nach E-Mail
        const email = emailOrPersonalnummer.trim();
        
        console.log(`🔍 Suche Mitarbeiter mit E-Mail "${email}" in companyId "${companyId}"`);
        
        // Suche zuerst in mitarbeiter Collection (email und pseudoEmail)
        let mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
        let q = query(mitarbeiterRef, where("email", "==", email));
        let snapshot = await getDocs(q);
        if (snapshot.empty) {
            const qPseudo = query(mitarbeiterRef, where("pseudoEmail", "==", email));
            snapshot = await getDocs(qPseudo);
        }
        if (snapshot.empty) {
            await new Promise(r => setTimeout(r, 500));
            snapshot = await getDocs(q);
            if (snapshot.empty) {
                snapshot = await getDocs(query(mitarbeiterRef, where("pseudoEmail", "==", email)));
            }
        }
        let isAdminUser = false;
        let userDoc = null;
        let userData = null;
        let actualCompanyId = companyId;
        
        // Wenn nicht in mitarbeiter gefunden, suche in users Collection (für Admin-Benutzer)
        // ⚠️ HINWEIS: users erfordert isLoggedIn() – Abfrage schlägt mit permission-denied fehl, wenn nicht eingeloggt.
        // Daher: Bei permission-denied direkt signIn versuchen (Account kann in Firebase Auth existieren).
        if (snapshot.empty) {
            console.log(`⚠️ E-Mail "${email}" nicht in mitarbeiter gefunden. Suche in users Collection...`);
            try {
                const usersRef = collection(db, "kunden", companyId, "users");
                const usersQuery = query(usersRef, where("email", "==", email));
                const usersSnapshot = await getDocs(usersQuery);
                
                console.log(`🔍 Users Query Ergebnis: ${usersSnapshot.size} Dokumente gefunden`);
                
                if (!usersSnapshot.empty) {
                    userDoc = usersSnapshot.docs[0];
                    userData = userDoc.data();
                    isAdminUser = true;
                    console.log(`✅ E-Mail "${email}" in users Collection gefunden (Admin-Benutzer).`);
                }
            } catch (usersQueryError) {
                console.warn(`⚠️ Users-Abfrage fehlgeschlagen (z.B. permission-denied vor Login): ${usersQueryError?.code || usersQueryError?.message}`);
                console.log(`🔄 Versuche direkten Login – Account kann in Firebase Auth existieren.`);
            }
        } else {
            // Mitarbeiter gefunden
            userDoc = snapshot.docs[0];
            userData = userDoc.data();
            isAdminUser = false;
        }
        
        // Wenn nicht gefunden, suche IMMER in allen Firmen (nicht nur bei admin)
        // Dies ist notwendig, weil Admin-Benutzer in verschiedenen Firmen existieren können
        // und sich von jeder Subdomain aus anmelden können
        if (!userDoc) {
            console.log(`⚠️ E-Mail "${email}" nicht in companyId "${companyId}" gefunden. Suche in allen Firmen...`);
            
            // ZUERST: Suche in users Collections aller Firmen (wichtig für Admin-Benutzer)
            // ⚠️ users erfordert isLoggedIn() – kann permission-denied werfen, wenn nicht eingeloggt
            try {
                const usersGroupRef = collectionGroup(db, "users");
                const usersGroupQuery = query(usersGroupRef, where("email", "==", email));
                console.log(`🔍 Führe Collection Group Query auf 'users' aus...`);
                const usersGroupSnapshot = await getDocs(usersGroupQuery);
                
                console.log(`🔍 Collection Group Query Ergebnis: ${usersGroupSnapshot.size} Dokumente gefunden`);
                usersGroupSnapshot.docs.forEach((doc, index) => {
                    console.log(`   Dokument ${index + 1}: ${doc.ref.path}, Daten:`, doc.data());
                });
                
                if (!usersGroupSnapshot.empty) {
                    userDoc = usersGroupSnapshot.docs[0];
                    userData = userDoc.data();
                    isAdminUser = true;
                    console.log(`✅ E-Mail "${email}" in anderer Firma (users) gefunden. Pfad: ${userDoc.ref.path}`);
                }
            } catch (usersGroupError) {
                console.warn(`⚠️ Collection Group Query 'users' fehlgeschlagen (z.B. permission-denied): ${usersGroupError?.code || usersGroupError?.message}`);
            }
            
            // DANN: Suche auch in mitarbeiter Collections (falls noch nicht gefunden)
            if (!userDoc) {
                try {
                    const mitarbeiterGroupRef = collectionGroup(db, "mitarbeiter");
                    let groupQuery = query(mitarbeiterGroupRef, where("email", "==", email));
                    console.log(`🔍 Führe Collection Group Query auf 'mitarbeiter' (email) aus...`);
                    snapshot = await getDocs(groupQuery);
                    if (snapshot.empty) {
                        groupQuery = query(mitarbeiterGroupRef, where("pseudoEmail", "==", email));
                        snapshot = await getDocs(groupQuery);
                    }
                    console.log(`🔍 Collection Group Query Ergebnis (mitarbeiter): ${snapshot.size} Dokumente gefunden`);
                    
                    if (!snapshot.empty) {
                        userDoc = snapshot.docs[0];
                        userData = userDoc.data();
                        isAdminUser = false;
                        console.log(`✅ E-Mail "${email}" in anderer Firma (mitarbeiter) gefunden. Pfad: ${userDoc.ref.path}`);
                    }
                } catch (mitarbeiterGroupError) {
                    console.error(`❌ Fehler bei Collection Group Query auf 'mitarbeiter':`, mitarbeiterGroupError);
                    console.error(`   Fehler-Code:`, mitarbeiterGroupError.code);
                    console.error(`   Fehler-Message:`, mitarbeiterGroupError.message);
                }
            }
        }
        
        if (!userDoc) {
            // 🔥 FALLBACK: Versuche direkten Login – Mitarbeiter kann in Firebase Auth existieren (users-Dokument in mitarbeiterverwaltung)
            // ohne dass ein Eintrag in mitarbeiter/users auffindbar war (z.B. permission-denied bei users-Abfrage vor Login)
            console.log(`🔄 E-Mail "${email}" nicht in Firestore gefunden. Versuche direkten Firebase-Auth-Login...`);
            try {
                const userCredential = await signInWithEmailAndPassword(auth, email, password);
                console.log(`✅ Direkter Login erfolgreich – Benutzer existiert in Firebase Auth.`);
                return; // Erfolg – onAuthStateChanged leitet weiter, getAuthData wird vom Dashboard aufgerufen
            } catch (directLoginError) {
                console.error(`❌ E-Mail "${email}" nicht gefunden. Direkter Login fehlgeschlagen:`, directLoginError?.code || directLoginError?.message);
                throw new Error("auth/user-not-found");
            }
        }
        
        // 🔥 WICHTIG: Wenn die E-Mail in einer anderen Firma gefunden wurde (z.B. via Collection Group Query),
        // extrahiere die tatsächliche companyId aus dem Dokument-Pfad
        if (userDoc.ref.path.includes('/kunden/')) {
            const pathParts = userDoc.ref.path.split('/');
            const kundenIndex = pathParts.indexOf('kunden');
            if (kundenIndex !== -1 && pathParts[kundenIndex + 1]) {
                actualCompanyId = pathParts[kundenIndex + 1];
                console.log(`📂 Tatsächliche companyId aus Dokument-Pfad extrahiert: ${actualCompanyId}`);
            }
        }
        
        // Prüfe ob Benutzer aktiv ist
        if (userData.active === false || userData.status === false) {
            throw new Error("auth/user-disabled");
        }
        
        try {
            let userCredential;
            try {
                userCredential = await signInWithEmailAndPassword(auth, email, password);
            } catch (firstErr) {
            if ((firstErr.code === "auth/invalid-credential" || firstErr.code === "auth/network-request-failed") && !userData?.tempPassword) {
                console.log("🔄 Erster Login-Versuch fehlgeschlagen, warte 1,5s und versuche erneut...");
                await new Promise(r => setTimeout(r, 1500));
                    userCredential = await signInWithEmailAndPassword(auth, email, password);
                } else {
                    throw firstErr;
                }
            }
            const uid = userCredential.user.uid;
            const docCollection = isAdminUser ? "users" : "mitarbeiter";
            const docRef = doc(db, "kunden", actualCompanyId, docCollection, userDoc.id);
            await setDoc(docRef, { uid, email, updatedAt: serverTimestamp() }, { merge: true });
            console.log(`✅ UID ${uid} im ${docCollection}-Dokument aktualisiert`);
            return;
        } catch (error) {
            console.log(`⚠️ Login-Versuch fehlgeschlagen: ${error.code} - ${error.message}`);
            
            // Prüfe, ob ein tempPassword gespeichert ist (für Admin-Passwort-Reset)
            // userData aus dem bereits gefundenen userDoc verwenden – keine erneute Abfrage nötig (vermeidet permission-denied vor Login)
            if (error.code === "auth/invalid-credential" || error.code === "auth/wrong-password") {
                const tempPassword = userData?.tempPassword;
                const tempPasswordDoc = userDoc;
                if (tempPassword) {
                        console.log(`🔑 tempPassword gefunden: ${tempPassword.substring(0, 2)}*** (Länge: ${tempPassword.length})`);
                        console.log(`🔑 Eingegebenes Passwort: ${password.substring(0, 2)}*** (Länge: ${password.length})`);
                        console.log(`🔑 Passwörter stimmen überein: ${tempPassword === password}`);
                        console.log(`🔑 Versuche Login mit tempPassword...`);
                        
                        // Versuche Login mit tempPassword (unabhängig vom eingegebenen Passwort)
                        try {
                            const userCredential = await signInWithEmailAndPassword(auth, email, tempPassword);
                            const uid = userCredential.user.uid;
                            const user = userCredential.user;
                            
                            console.log(`✅ Login mit tempPassword erfolgreich - aktualisiere Passwort in Firebase Auth...`);
                            
                            // Aktualisiere das Passwort in Firebase Auth auf das eingegebene Passwort
                            await updatePassword(user, password);
                            
                            console.log(`✅ Passwort in Firebase Auth aktualisiert`);
                            
                            // Entferne tempPassword aus Firestore
                            const docRef = doc(db, tempPasswordDoc.ref.path);
                            await updateDoc(docRef, {
                                tempPassword: null,
                                passwordUpdatedAt: null,
                                updatedAt: serverTimestamp()
                            });
                            
                            console.log(`✅ tempPassword aus Firestore entfernt`);
                            
                            // Aktualisiere auch die UID im Dokument
                            await updateDoc(docRef, {
                                uid: uid,
                                email: email,
                                updatedAt: serverTimestamp()
                            });
                            
                            console.log(`✅ Login erfolgreich - Passwort wurde aktualisiert`);
                            return; // Login erfolgreich
                        } catch (tempPasswordError) {
                            console.log(`⚠️ Login mit tempPassword fehlgeschlagen:`, tempPasswordError.message);
                            
                            // Wenn Login mit tempPassword fehlschlägt, bedeutet das, dass tempPassword nicht das aktuelle Passwort in Firebase Auth ist
                            // In diesem Fall müssen wir prüfen, ob das eingegebene Passwort mit tempPassword übereinstimmt
                            if (tempPassword === password) {
                                // Das eingegebene Passwort ist das tempPassword, aber es funktioniert nicht in Firebase Auth
                                // Das bedeutet, dass der Account in Firebase Auth ein anderes Passwort hat
                                // Lösung: Versuche, eine Passwort-Reset-Email zu senden, damit der Benutzer das Passwort selbst zurücksetzen kann
                                console.log(`🔄 tempPassword stimmt mit eingegebenem Passwort überein, aber Login fehlgeschlagen.`);
                                console.log(`📧 Sende Passwort-Reset-Email an ${email}...`);
                                
                                try {
                                    // Konfiguriere die Action URL, damit der Link auf unsere eigene reset-password.html Seite zeigt
                                    const actionCodeSettings = {
                                        url: window.location.origin + '/reset-password.html',
                                        handleCodeInApp: false
                                    };
                                    
                                    await sendPasswordResetEmail(auth, email, actionCodeSettings);
                                    console.log(`✅ Passwort-Reset-Email wurde erfolgreich gesendet`);
                                    
                                    // Entferne tempPassword aus Firestore, da wir eine Reset-Email gesendet haben
                                    const docRef = doc(db, tempPasswordDoc.ref.path);
                                    await updateDoc(docRef, {
                                        tempPassword: null,
                                        passwordUpdatedAt: null,
                                        updatedAt: serverTimestamp()
                                    });
                                    console.log(`✅ tempPassword aus Firestore entfernt`);
                                    
                                    throw new Error("auth/password-reset-email-sent");
                                } catch (resetEmailError) {
                                    if (resetEmailError.message === "auth/password-reset-email-sent") {
                                        throw resetEmailError; // Weiterwerfen der speziellen Fehlermeldung
                                    }
                                    console.log(`⚠️ Fehler beim Senden der Passwort-Reset-Email:`, resetEmailError.message);
                                    // Wenn das auch fehlschlägt, wirf einen allgemeinen Fehler
                                    throw new Error("auth/password-reset-required");
                                }
                            }
                            // Weiter mit normaler Fehlerbehandlung
                        }
                }
            }
            
            // Wenn signIn fehlschlägt, versuche Account zu erstellen (gleiche Logik wie bei 309)
            // invalid-credential kann bedeuten: Account existiert nicht ODER Passwort falsch
            // createUser: Erfolg = Account war nicht vorhanden (oder wurde gelöscht) → jetzt erstellt
            // createUser: email-already-in-use = Account existiert, Passwort falsch → Admin muss zurücksetzen
            if (error.code === "auth/user-not-found" || error.code === "auth/invalid-credential") {
                console.log(`📝 SignIn fehlgeschlagen - versuche Firebase Auth Account für ${email} zu erstellen/reparieren...`);
                try {
                    // Erstelle Firebase Auth Account mit E-Mail
                    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
                    const uid = userCredential.user.uid;
                    
                    // Aktualisiere das entsprechende Dokument mit UID (users oder mitarbeiter)
                    // Verwende die tatsächliche companyId, nicht die ursprüngliche
                    if (isAdminUser) {
                        const userDocRef = doc(db, "kunden", actualCompanyId, "users", userDoc.id);
                        const updateData = {
                            uid: uid,
                            email: email,
                            updatedAt: serverTimestamp()
                        };
                        await setDoc(userDocRef, updateData, { merge: true });
                        console.log(`✅ Neuer Account erstellt und UID ${uid} im Users-Dokument ${userDoc.id} (Firma: ${actualCompanyId}) gespeichert`);
                    } else {
                        const mitarbeiterDocRef = doc(db, "kunden", actualCompanyId, "mitarbeiter", userDoc.id);
                        const updateData = {
                            uid: uid,
                            email: email,
                            updatedAt: serverTimestamp()
                        };
                        await setDoc(mitarbeiterDocRef, updateData, { merge: true });
                        console.log(`✅ Neuer Account erstellt und UID ${uid} im Mitarbeiter-Dokument ${userDoc.id} (Firma: ${actualCompanyId}) gespeichert`);
                    }
                    return; // createUserWithEmailAndPassword hat Benutzer automatisch eingeloggt
                } catch (createError) {
                    console.error(`❌ Fehler beim Erstellen des Accounts: ${createError.code} - ${createError.message}`);
                    if (createError.code === "auth/email-already-in-use") {
                        // Account existiert bereits – Passwort ist falsch
                        console.log(`⚠️ Account existiert bereits – Passwort stimmt nicht. Admin muss in Mitgliederverwaltung zurücksetzen.`);
                        throw error;
                    } else {
                        throw createError;
                    }
                }
            } else {
                throw error;
            }
        }
    } else {
        // Personalnummer-Login: Suche Mitarbeiter in Firestore
        const personalnummer = emailOrPersonalnummer.trim();
        
        const mitarbeiterRef = collection(db, "kunden", companyId, "mitarbeiter");
        let q = query(mitarbeiterRef, where("personalnummer", "==", personalnummer));
        let snapshot = await getDocs(q);
        if (snapshot.empty && /^\d+$/.test(personalnummer)) {
            q = query(mitarbeiterRef, where("personalnummer", "==", parseInt(personalnummer, 10)));
            snapshot = await getDocs(q);
        }
        
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
                updatedAt: serverTimestamp()
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
                        updatedAt: serverTimestamp()
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
            
            // 🔥 WICHTIG: Stelle sicher, dass das Dokument kunden/admin existiert
            // Dies ist notwendig, damit die Module und andere Daten geladen werden können
            const adminRef = doc(db, "kunden", "admin");
            const adminSnap = await getDoc(adminRef);
            
            if (!adminSnap.exists()) {
                console.log("🔧 Dokument kunden/admin existiert nicht - erstelle es...");
                try {
                    await setDoc(adminRef, {
                        name: "RettBase Admin",
                        subdomain: "admin",
                        status: "active",
                        createdAt: serverTimestamp(),
                        isSystem: true // Flag, dass dies ein System-Kunde ist
                    }, { merge: true });
                    console.log("✅ Dokument kunden/admin erstellt");
                } catch (createError) {
                    console.warn("⚠️ Konnte kunden/admin nicht erstellen:", createError);
                    // Weiter fortfahren, auch wenn Erstellung fehlgeschlagen ist
                }
            } else {
                console.log("✅ Dokument kunden/admin existiert bereits");
            }
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
        // 🔥 WICHTIG: Für admin-Firma (Superadmin) zuerst in users Collection suchen
        let userData = null;
        let userKundenId = null;
        
        if (requestedKundenId === 'admin') {
          // Für admin-Firma: Suche zuerst in users Collection (Superadmin wird dort gespeichert)
          const adminUsersDocRef = doc(db, "kunden", "admin", "users", uid);
          console.log(`📂 [1-Admin] Suche Superadmin in: kunden/admin/users/${uid}`);
          const adminUsersSnap = await getDoc(adminUsersDocRef);
          
          if (adminUsersSnap.exists()) {
            userData = adminUsersSnap.data();
            userKundenId = "admin";
            console.log(`✅ [1-Admin] Superadmin in users Collection gefunden, Rolle: ${userData.role}`);
          } else {
            console.log(`⚠️ [1-Admin] Superadmin nicht in users Collection gefunden, suche in mitarbeiter Collection...`);
          }
        }
        
        // Wenn nicht in users Collection gefunden (oder nicht admin-Firma), suche in mitarbeiter Collection
        if (!userData) {
          const directDocRef = doc(db, "kunden", requestedKundenId, "mitarbeiter", uid);
          console.log(`📂 [1] Suche Benutzer direkt unter: kunden/${requestedKundenId}/mitarbeiter/${uid}`);
          const directSnap = await getDoc(directDocRef);
          
          if (directSnap.exists()) {
            userData = directSnap.data();
            userKundenId = directSnap.ref.parent.parent.id;
            console.log(`✅ [1] Benutzer direkt gefunden in kunden/${userKundenId}/mitarbeiter/${uid}, Rolle: ${userData.role}`);
          } else {
            console.log(`❌ [1] Direkte Abfrage fehlgeschlagen (Dokument existiert nicht)`);
            
            // Fallback 1: Versuche alte users Collection (nur wenn nicht bereits in admin/users gesucht)
            if (requestedKundenId !== 'admin') {
              const oldUsersDocRef = doc(db, "kunden", requestedKundenId, "users", uid);
              const oldUsersSnap = await getDoc(oldUsersDocRef);
              if (oldUsersSnap.exists()) {
                console.log(`⚠️ [1-Fallback] Benutzer in alter users Collection gefunden, sollte migriert werden`);
                userData = oldUsersSnap.data();
                userKundenId = oldUsersSnap.ref.parent.parent.id;
              }
            }
            
            // Fallback 2: Suche nach UID-Feld in der mitarbeiter Collection (wenn uid != documentId)
            if (!userData) {
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
            
            // Fallback 3: Suche nach E-Mail oder pseudoEmail in mitarbeiter
            if (!userData && email) {
              console.log(`🔄 [1-Fallback] Suche nach email="${email}" in mitarbeiter Collection...`);
              try {
                const mitarbeiterRef = collection(db, "kunden", requestedKundenId, "mitarbeiter");
                let emailSnapshot = await getDocs(query(mitarbeiterRef, where("email", "==", email)));
                if (emailSnapshot.empty) {
                  emailSnapshot = await getDocs(query(mitarbeiterRef, where("pseudoEmail", "==", email)));
                }
                if (!emailSnapshot.empty) {
                  const mitarbeiterDoc = emailSnapshot.docs[0];
                  userData = mitarbeiterDoc.data();
                  userKundenId = mitarbeiterDoc.ref.parent.parent.id;
                  console.log(`✅ [1-Fallback] Benutzer gefunden über email in mitarbeiter/${mitarbeiterDoc.id}, Rolle: ${userData.role}`);
                  // UID und users-Dokument nachtragen für zukünftige Logins
                  const docRef = doc(db, "kunden", userKundenId, "mitarbeiter", mitarbeiterDoc.id);
                  const usersRef = doc(db, "kunden", userKundenId, "users", uid);
                  try {
                    await setDoc(docRef, { uid, updatedAt: serverTimestamp() }, { merge: true });
                    await setDoc(usersRef, { email, role: userData.role || "user", companyId: userKundenId, status: userData.active !== false, mitarbeiterDocId: mitarbeiterDoc.id }, { merge: true });
                    console.log(`✅ uid und users-Dokument nachgetragen für zukünftige Logins`);
                  } catch (e) { console.warn("Nachtragen fehlgeschlagen:", e); }
                }
              } catch (queryError) {
                console.warn(`⚠️ [1-Fallback] Query nach email fehlgeschlagen:`, queryError);
              }
            }
          }
        }
        
        if (userData) {
          const collectionName = (requestedKundenId === 'admin' && userKundenId === 'admin' && userData.role === 'superadmin') ? 'users' : 'mitarbeiter';
          console.log(`✅ Benutzer gefunden in kunden/${userKundenId}/${collectionName}/${uid}`);
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
          const validRoles = ['superadmin', 'admin', 'supervisor', 'leiterssd', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter'];
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

        const validRoles = ['superadmin', 'admin', 'supervisor', 'leiterssd', 'wachleitung', 'ovd', 'user', 'fahrzeugbeauftragter', 'mpg-beauftragter'];
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
