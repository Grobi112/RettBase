# iOS Push-Benachrichtigungen – Checkliste

Wenn Chat-Push-Benachrichtigungen auf iOS nicht ankommen (weder Banner noch Badge, bis die App geöffnet wird), prüfe diese Punkte:

## 1. Projekt-Änderungen (bereits umgesetzt)

- ✅ `Runner.entitlements` mit `aps-environment: production` erstellt
- ✅ `CODE_SIGN_ENTITLEMENTS` im Xcode-Projekt gesetzt
- ✅ `UIBackgroundModes`: `fetch` + `remote-notification` in Info.plist
- ✅ Cloud Function: APNs-Payload mit explizitem `alert`, `badge`, `sound`

## 2. Xcode – Push Notifications Capability

1. Öffne `ios/Runner.xcworkspace` in Xcode
2. Wähle das **Runner**-Target
3. Tab **Signing & Capabilities**
4. Klicke **+ Capability**
5. Suche **Push Notifications** und füge sie hinzu

(Falls die Capability schon vorhanden ist, überspringen.)

## 3. Apple Developer Portal

1. Gehe zu [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles
2. **Identifiers** → deine App-ID (z.B. `com.mikefullbeck.rettbase`)
3. Prüfe: **Push Notifications** muss aktiviert sein
4. Falls nicht: aktivieren und **Profiles** neu erstellen/herunterladen

## 4. Firebase Console – APNs Key

1. Gehe zu [Firebase Console](https://console.firebase.google.com) → Projekt **rett-fe0fa**
2. ⚙️ **Projekteinstellungen** → Tab **Cloud Messaging**
3. Unter **Apple-App-Konfiguration**:
   - **APNs-Authentifizierungsschlüssel** hochladen (`.p8`-Datei)
   - **Key ID** und **Team ID** eintragen

APNs-Key anlegen (falls noch nicht vorhanden):

1. [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) → Keys
2. **+** → Name z.B. „RettBase APNs“
3. **Apple Push Notifications service (APNs)** aktivieren
4. Erstellen → `.p8` herunterladen und Key ID notieren

## 5. Neubau und TestFlight

Nach Änderungen an Entitlements oder Capabilities:

1. App neu bauen: `flutter build ios`
2. In Xcode archivieren und zu TestFlight hochladen
3. Neue Build-Version auf dem Gerät installieren

## 6. Geräte-Einstellungen

- **Einstellungen** → **RettBase** → **Benachrichtigungen**: aktiviert
- **Benachrichtigungen erlauben** und **Töne** aktiviert

## 7. Debug – wenn Badge erst nach App-Öffnen erscheint

**Symptom:** Badge erscheint nur, wenn du die App geöffnet, die Nachricht nicht gelesen und die App wieder verlassen hast – nicht direkt bei neuer Nachricht.

**Ursache:** Der Push kommt nicht auf dem Gerät an, wenn die App im Hintergrund oder beendet ist. Der Badge wird nur gesetzt, weil die App beim Öffnen den Firestore-Stream lädt und `updateBadge` aufruft.

### Schritte zur Fehlersuche

1. **Cloud Function Logs prüfen**
   - Firebase Console → Functions → Logs
   - Nach einer neuen Chat-Nachricht: Wird `onNewChatMessage: FCM an uid=... erfolgreich gesendet` geloggt?
   - Wenn **ja**: FCM-Send war erfolgreich → Problem liegt bei APNs/Gerät (siehe unten)
   - Wenn **nein** oder Fehler: Prüfe `Kein FCM-Token für uid=...` oder `fehlgeschlagen: ...`

2. **FCM-Token in Firestore prüfen**
   - In der App einloggen, App kurz offen lassen (Dashboard laden)
   - Firestore: `kunden/{companyId}/users/{uid}` bzw. `fcmTokens/{uid}`
   - Muss `fcmToken` (nicht leer) und `fcmTokenUpdatedAt` enthalten

3. **TestFlight vs. Debug-Build**
   - **TestFlight/Archive**: nutzt `aps-environment: production` (APNs-Produktionsserver)
   - **Debug von Xcode** (Run auf Gerät): kann Sandbox/Development nutzen
   - Empfehlung: Mit **TestFlight-Build** testen – dort ist die Konfiguration am zuverlässigsten

4. **Provisioning Profile neu erzeugen**
   - Apple Developer → Profiles → dein App-Profile
   - Löschen und neu erstellen (damit Push-Entitlement übernommen wird)
   - In Xcode: Product → Clean Build Folder, dann neu archivieren

5. **APNs-Key in Firebase**
   - Firebase Console → Projekteinstellungen → Cloud Messaging
   - APNs-Authentifizierungsschlüssel (.p8) muss hochgeladen sein
   - Key ID und Team ID müssen stimmen
