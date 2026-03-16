# Notification Service Extension – manuell in Xcode hinzufügen

Die Extension läuft **bei jedem Push**, auch wenn die App komplett beendet ist. Sie stellt sicher, dass Badge + Ton + Nachricht angezeigt werden.

## Schritte (ca. 2 Minuten)

1. **Xcode öffnen**
   ```bash
   open /Users/mikefullbeck/RettBase/app/ios/Runner.xcworkspace
   ```

2. **Neues Target erstellen**
   - Menü: **File → New → Target**
   - **iOS** wählen → **Notification Service Extension** → **Next**
   - **Product Name:** `NotificationService`
   - **Team:** dein Team (WMGXT99BVV)
   - **Bundle Identifier:** `com.mikefullbeck.rettbase.NotificationService`
   - **Finish** → Bei "Activate scheme?" → **Cancel**

3. **Code ersetzen**
   - Xcode hat `NotificationService.swift` mit einem Template angelegt
   - Öffne die Datei und **ersetze den gesamten Inhalt** mit dem Code aus `app/ios/NotificationService/NotificationService.swift` (im Projekt bereits vorhanden)

4. **Build & Run**
   ```bash
   cd /Users/mikefullbeck/RettBase/app && flutter run
   ```

## Wichtig

- Der Cloud-Function-Payload enthält bereits `"mutable-content": 1` – dadurch wird die Extension aufgerufen
- Die Extension muss das gleiche **Team** und **Signing** wie die Haupt-App haben
- Nach dem Hinzufügen: **Cloud Function deployen** (`cd functions && npm run deploy`)
