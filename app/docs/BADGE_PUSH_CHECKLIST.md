# Badge & Push – Technische Checkliste

Alle Faktoren, die für funktionierende Push-Benachrichtigungen und App-Icon-Badge auf iOS erforderlich sind.

---

## 1. Apple Developer Portal

| Punkt | Status | Aktion |
|-------|--------|--------|
| App-ID mit **Push Notifications** aktiviert | ❓ | Identifiers → deine App-ID → Push Notifications aktivieren |
| **APNs Key** (.p8) erstellt | ❓ | Keys → + → „Apple Push Notifications service (APNs)“ → .p8 herunterladen, Key ID notieren |
| Provisioning Profile aktuell | ❓ | Nach Änderungen: Profile löschen und neu erstellen |

---

## 2. Firebase Console

| Punkt | Status | Aktion |
|-------|--------|--------|
| **Entwicklungs-APNs-Key** hochgeladen | ❓ | Projekteinstellungen → Cloud Messaging → Apple-App → Entwicklungs-APNs-Authentifizierungsschlüssel |
| **Produktions-APNs-Key** hochgeladen | ❓ | Ebenso → Produktions-APNs-Authentifizierungsschlüssel |
| Key ID + Team ID korrekt | ❓ | Beim Upload prüfen |

**WICHTIG:** Debug-Builds (Xcode Run auf Gerät) nutzen den **APNs Sandbox**. Ohne **Entwicklungs-Key** in Firebase kommt Push bei Debug-Builds **nie** an. TestFlight/App Store nutzt **Produktions-Key**.

---

## 3. Xcode (iOS)

| Punkt | Status | Aktion |
|-------|--------|--------|
| **Push Notifications** Capability | ❓ | Signing & Capabilities → + Capability → Push Notifications |
| **CODE_SIGN_ENTITLEMENTS** | ✅ | `Runner/Runner.entitlements` (bereits gesetzt) |
| **aps-environment** in Entitlements | ✅ | `production` (bereits vorhanden) |
| **UIBackgroundModes** | ✅ | `fetch` + `remote-notification` (bereits in Info.plist) |
| **registerForRemoteNotifications** | ✅ | In AppDelegate.swift (bereits implementiert) |

---

## 4. App-Code (bereits implementiert)

| Punkt | Status |
|-------|--------|
| FCM-Token in Firestore speichern | ✅ |
| `saveToken` beim Dashboard-Start | ✅ |
| `retrySaveTokenIfNeeded` bei App-Resume | ✅ |
| `_firebaseMessagingBackgroundHandler` für Badge | ✅ |
| `setForegroundNotificationPresentationOptions` | ✅ |
| APNs-Token vor FCM-Token abwarten (iOS) | ✅ |
| Cloud Function: `aps.badge` im Payload | ✅ |

---

## 5. Cloud Function (bereits implementiert)

| Punkt | Status |
|-------|--------|
| `apns-push-type: alert` | ✅ |
| `apns-priority: 10` | ✅ |
| `aps.alert`, `aps.badge`, `aps.sound` | ✅ |
| `aps.content-available: 1` | ✅ (iOS-Hintergrund-Zustellung) |
| `data.totalUnread` für Badge | ✅ |

---

## 6. Gerät & Einstellungen

| Punkt | Status | Aktion |
|-------|--------|--------|
| **Echtes Gerät** (kein Simulator) | ❓ | Push funktioniert nur auf physischem iPhone |
| **Benachrichtigungen** aktiviert | ❓ | Einstellungen → RettBase → Benachrichtigungen |
| **Hinweise** (Banner) aktiviert | ❓ | Einstellungen → RettBase → Benachrichtigungen → Hinweise |

---

## 7. Debug-Schritte

### 7.1 Cloud Function Logs

```
Firebase Console → Functions → Logs
```

Nach neuer Chat-Nachricht prüfen:
- `onNewChatMessage: FCM an uid=... erfolgreich gesendet` → FCM-Send OK; Problem liegt bei APNs/Gerät
- `Kein FCM-Token für uid=...` → Token fehlt in Firestore
- `fehlgeschlagen: ...` → Fehlermeldung in Logs prüfen

### 7.2 FCM-Token in Firestore

```
Firestore: kunden/{companyId}/users/{uid}
oder: fcmTokens/{uid}
```

Muss enthalten:
- `fcmToken` (nicht leer)
- `fcmTokenUpdatedAt`

### 7.3 Debug-Build vs. TestFlight

| Build-Typ | APNs-Server | Firebase-Key benötigt |
|-----------|-------------|------------------------|
| Xcode Run (USB) | Sandbox/Development | **Entwicklungs-Key** |
| TestFlight / Archive | Production | **Produktions-Key** |

---

## 8. Offene Punkte (manuell prüfen)

| # | Punkt | Wo prüfen |
|---|-------|-----------|
| 1 | APNs-Key in Firebase (Development + Production) | Firebase Console → Projekteinstellungen → Cloud Messaging |
| 2 | Push Notifications Capability in Xcode | Xcode → Runner → Signing & Capabilities |
| 3 | App-ID Push aktiviert | developer.apple.com → Identifiers |
| 4 | Provisioning Profile neu | developer.apple.com → Profiles (nach Capability-Änderung) |
| 5 | Gerät: Benachrichtigungen an | Einstellungen → RettBase |

---

## 9. Häufige Ursachen für „Badge erscheint nicht“

1. **Kein Entwicklungs-APNs-Key in Firebase** → Debug-Builds erhalten keinen Push
2. **FCM-Token fehlt oder ist abgelaufen** → App öffnen, ins Dashboard, kurz warten, Token wird gespeichert
3. **App im Simulator** → Push funktioniert nur auf echtem Gerät
4. **Benachrichtigungen deaktiviert** → iOS-Einstellungen prüfen
5. **Provisioning Profile veraltet** → Nach Capability-Änderung neu erstellen
