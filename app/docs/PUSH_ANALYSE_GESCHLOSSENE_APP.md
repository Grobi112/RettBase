# Push-Analyse: Keine Benachrichtigung bei geschlossener App

## Symptom

- **Badge** erscheint erst, wenn die App geöffnet und wieder geschlossen wird
- **Push-Benachrichtigung** wird bei geschlossener App nicht angezeigt
- Cloud Function meldet „erfolgreich gesendet“
- Technisch scheint alles eingerichtet

---

## Durchlauf des gesamten Prozesses

### 1. Cloud Function (onNewChatMessage)

| Prüfpunkt | Status | Details |
|-----------|--------|---------|
| Trigger | ✅ | `onCreate` auf `messages/{messageId}` |
| FCM-Token-Lookup | ✅ | `getFcmToken(companyId, uid)` → `users.fcmToken` oder `fcmTokens.fcmToken` |
| Payload-Struktur | ✅ | `notification` + `data` + `apns` mit `alert`, `badge`, `sound` |
| apns-push-type | ✅ | `alert` (sichtbare Benachrichtigung) |
| apns-priority | ✅ | `10` (hoch) |
| content-available | ⚠️ | **Neu ergänzt** – kann iOS bei Hintergrund/Terminated unterstützen |

**Mögliche Fehlerstelle:** Kein Token in Firestore → Log: „Kein FCM-Token für uid=…“

---

### 2. Firebase Cloud Messaging → APNs

| Prüfpunkt | Status | Details |
|-----------|--------|---------|
| FCM akzeptiert Send | ✅ | „erfolgreich gesendet“ in Logs |
| APNs-Key in Firebase | ❓ | Muss in Firebase Console hochgeladen sein (.p8) |
| Sandbox vs. Production | ❓ | Debug-Build → Sandbox; TestFlight → Production |
| Token-Umgebung | ✅ | FCM-Token enthält APNs-Umgebung; Firebase wählt automatisch |

**Mögliche Fehlerstelle:** APNs-Key fehlt oder falsch → FCM sendet, APNs lehnt ab (kein sichtbarer Fehler in Function-Logs).

---

### 3. APNs → Gerät

| Prüfpunkt | Status | Details |
|-----------|--------|---------|
| aps-environment | ✅ | Debug: `development`, Release: `production` (Runner-Debug.entitlements) |
| Entitlements im Build | ✅ | CODE_SIGN_ENTITLEMENTS für Debug/Release korrekt |
| Gerät erreichbar | ❓ | Internet, keine Sperre |

**Mögliche Fehlerstelle:** Falsche aps-environment (z.B. Production-Key bei Debug-Build) → APNs liefert nicht aus.

---

### 4. iOS – Anzeige der Benachrichtigung

| Prüfpunkt | Status | Details |
|-----------|--------|---------|
| UIBackgroundModes | ✅ | `remote-notification` in Info.plist |
| registerForRemoteNotifications | ✅ | AppDelegate.swift |
| Push Notifications Capability | ❓ | In Xcode prüfen (Signing & Capabilities) |
| Benutzer-Einstellungen | ❓ | Einstellungen → RettBase → Benachrichtigungen |
| „Hinweise“ / Banner | ❓ | Muss aktiviert sein |
| Fokus / Nicht stören | ❓ | Kann Anzeige unterdrücken |

**Mögliche Fehlerstelle:** Benachrichtigungen deaktiviert oder „Leise zustellen“ → keine Anzeige.

---

### 5. App-Code (Flutter)

| Prüfpunkt | Status | Details |
|-----------|--------|---------|
| onBackgroundMessage | ✅ | Registriert, Top-Level mit @pragma |
| Registrierungszeitpunkt | ⚠️ | **Angepasst** – jetzt vor Firebase.initializeApp |
| saveToken | ✅ | Nach Login, bei Dashboard, bei Resume |
| Foreground-Optionen | ✅ | setForegroundNotificationPresentationOptions |

**Mögliche Fehlerstelle:** Background-Handler zu spät registriert → erste Benachrichtigung nach App-Kill wird nicht verarbeitet (betrifft vor allem Badge, weniger die System-Anzeige).

---

## Bekannte iOS-Besonderheiten (FlutterFire / FCM)

1. **Erste Benachrichtigung nach App-Kill:** Der Background-Handler wird auf iOS manchmal bei der ersten Benachrichtigung nicht aufgerufen; die **System-Benachrichtigung** sollte trotzdem erscheinen.
2. **Nur echtes Gerät:** Push funktioniert nicht im Simulator.
3. **content-available:** Kann die Zustellung bei Hintergrund/Terminated verbessern.

---

## Durchgeführte Änderungen

1. **Cloud Function:** `content-available: 1` im APNs-Payload ergänzt.
2. **main.dart:** Registrierung von `onBackgroundMessage` an den Anfang von `main()` verschoben (vor `Firebase.initializeApp`).

---

## Manuelle Prüfliste

| # | Aktion | Wo |
|---|--------|-----|
| 1 | APNs-Key (.p8) in Firebase hochgeladen? | Firebase Console → Projekteinstellungen → Cloud Messaging |
| 2 | Push Notifications Capability in Xcode aktiv? | Xcode → Runner → Signing & Capabilities |
| 3 | App-ID mit Push Notifications? | developer.apple.com → Identifiers |
| 4 | Benachrichtigungen für RettBase aktiv? | iPhone: Einstellungen → RettBase → Benachrichtigungen |
| 5 | „Hinweise“ aktiviert? | Einstellungen → RettBase → Benachrichtigungen → Hinweise |
| 6 | FCM-Token in Firestore? | Firestore: `kunden/{companyId}/users/{uid}` oder `fcmTokens/{uid}` |
| 7 | Mit echtem Gerät testen? | Kein Simulator |
| 8 | Debug-Build: Runner-Debug.entitlements? | project.pbxproj → Debug → Runner-Debug.entitlements |

---

## Test mit TestFlight

Wenn Debug-Builds weiterhin keine Push zeigen:

1. `flutter build ios`
2. In Xcode archivieren und zu TestFlight hochladen
3. App über TestFlight installieren und testen

TestFlight nutzt den Production-APNs-Server; wenn es dort funktioniert, liegt das Problem sehr wahrscheinlich an der Debug/Sandbox-Konfiguration.
