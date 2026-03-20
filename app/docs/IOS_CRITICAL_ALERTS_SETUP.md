# iOS & macOS Critical Alerts – Einrichtung

Kritische Warnmeldungen für Einsatz-Alarme: Durchbrechen Stummschaltung und Fokus-Modus.

## Übersicht

| Komponente | Status |
|------------|--------|
| Cloud Function (`sendAlarmPush`) | ✅ `apns-interruption-level: critical`, `sound: { critical: 1, volume: 1.0 }`, Custom-Ton als `voices/<datei>.wav` (Bundle-Ordner) |
| Flutter (`requestPermission`) | ✅ `criticalAlert: true` (iOS + macOS) |
| iOS Entitlements | ✅ `com.apple.developer.usernotifications.critical-alerts` |
| macOS Entitlements | ✅ `com.apple.developer.usernotifications.critical-alerts` |
| Apple-Genehmigung | ⚠️ Pro App ID erforderlich |

### Was Critical Alerts auf iPhone/iPad **können** (Apple)

- **Stummschalter / Lautlos:** Kritische Benachrichtigungen können trotzdem **mit Ton** kommen – dafür ist das Entitlement da.
- **Lautstärke im Push:** Im Payload ist `volume: 1.0` = **maximal** im Rahmen der Critical-Alert-API (0…1). Das ist **nicht** „System-Lautstärke auf 100 % erzwingen“ – das macht nur die **Foreground-Logik** in der App (`FlutterVolumeController` beim Alarm-Ton im Vordergrund).
- **Nutzer muss zustimmen:** Unter **Einstellungen → RettBase → Mitteilungen** muss **Kritische Benachrichtigungen** erlaubt sein (sonst kein Durchbruch).
- **Fokus-Modi:** Oft durch Critical Alerts durchdringbar; der Nutzer kann Critical Alerts für die App aber einschränken.

### Checkliste bis es live wirkt

1. **App** mit Critical-Alerts-Entitlement bauen (TestFlight o. Ä.) und installieren.
2. Beim ersten Push / in den Einstellungen: **Benachrichtigungen** + **Kritische Benachrichtigungen** erlauben.
3. **Cloud Functions deployen** (`firebase deploy --only functions` o. Ä.), damit `sendAlarmPush` mit `apns-interruption-level: critical` auf dem Server läuft.
4. **Custom-Ton:** Nur **WAV/CAF/AIFF** im Bundle unter `voices/` (wie im Xcode-Projekt); MP3 geht für APNs-Ton nicht.

## Schritte zur Apple-Genehmigung

1. **Formular:** https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/
2. **Begründung:** z. B. „Rettungsdienst-App für Schulsanitätsdienst. Einsatz-Alarmierungen müssen auch bei Stummschaltung ankommen, damit Sanitäter nicht verpasste Einsätze haben.“
3. **Warten** (typisch 1–2 Werktage)
4. **Apple Developer Portal** – für **jede** App ID:
   - **Identifiers** → https://developer.apple.com/account/resources/identifiers/list
   - App ID auswählen (z. B. `com.mikefullbeck.rettbase` für iOS, `com.example.app` für macOS)
   - **Edit** → unter „Additional Capabilities“ → **Critical Alerts** aktivieren
   - **Save**
5. **Provisioning Profile** neu erstellen (Xcode → Signing & Capabilities → Automatically manage signing, oder manuell im Portal)

## Nach der Genehmigung

- **iOS:** `flutter build ios` → Xcode archivieren → TestFlight
- **macOS:** `flutter build macos` → Xcode archivieren → TestFlight/App Store
- Beim ersten Nutzer-Login erscheint der Permission-Dialog inkl. „Critical Alerts“-Option
- Einsatz-Alarme kommen auch bei Stummschaltung und Fokus-Modus durch

## Wo findest du was?

| Was | Wo |
|-----|-----|
| **App IDs** | [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list) |
| **Critical Alerts aktivieren** | Identifiers → App ID → Edit → Additional Capabilities → Critical Alerts |
| **Provisioning Profiles** | [developer.apple.com → Profiles](https://developer.apple.com/account/resources/profiles/list) |
| **iOS Bundle ID** | `com.mikefullbeck.rettbase` |
| **macOS Bundle ID** | `com.example.app` (in `macos/Runner/Configs/AppInfo.xcconfig`) |

## Fehlerbehebung

- **Build-Fehler „Invalid entitlements“:** Apple-Genehmigung noch nicht erteilt oder Provisioning Profile nicht aktualisiert.
- **Kein Critical Alerts im Dialog:** `criticalAlert` wird nur angezeigt, wenn das Entitlement im App ID vorhanden ist.
- **Bleibt stumm:** Prüfe Einstellungen → RettBase → Benachrichtigungen; „Critical Alerts“ muss erlaubt sein.
