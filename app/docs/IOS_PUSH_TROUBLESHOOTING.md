# iOS Push-Benachrichtigung – Fehlerbehebung

Wenn die Cloud Function „erfolgreich gesendet“ meldet, aber **keine Push-Benachrichtigung mit Ton** erscheint, wenn die App im Hintergrund oder geschlossen ist, prüfe diese Punkte.

---

## 1. APNs-Key in Firebase (häufigste Ursache)

**Ohne APNs-Key kann Firebase keine Push-Nachrichten an iOS-Geräte senden.**

### Schritte

1. **Firebase Console** öffnen: https://console.firebase.google.com → Projekt **rett-fe0fa**
2. **Projekteinstellungen** (Zahnrad) → **Cloud Messaging**
3. Unter **Apple-App-Konfiguration** prüfen:
   - **Entwicklungs-APNs-Authentifizierungsschlüssel** – für Debug-Builds (Xcode Run)
   - **Produktions-APNs-Authentifizierungsschlüssel** – für TestFlight/App Store

### APNs-Key erstellen (falls noch nicht vorhanden)

1. **Apple Developer** → https://developer.apple.com/account/resources/authkeys/list
2. **+** → Name z.B. „RettBase Push“
3. **Apple Push Notifications service (APNs)** aktivieren → Weiter → Registrieren
4. **Key ID** notieren, **.p8-Datei** herunterladen (nur einmal möglich)
5. **Team ID** und **Bundle ID** notieren
6. In Firebase: Key hochladen, Key ID, Team ID und Bundle ID eintragen

### Build-Typ vs. APNs-Key

| Wie du testest              | Benötigter Key in Firebase |
|-----------------------------|----------------------------|
| Xcode Run (USB auf Gerät)   | **Entwicklungs-Key**       |
| TestFlight / Archive        | **Produktions-Key**        |

---

## 2. Xcode: Push Notifications Capability

1. Xcode → **Runner** → **Signing & Capabilities**
2. **+ Capability** → **Push Notifications** hinzufügen (falls noch nicht vorhanden)

---

## 3. Gerät & Einstellungen (wichtig für Ton + Banner)

- **Echtes iPhone** (kein Simulator)
- **Einstellungen → RettBase → Benachrichtigungen** → **aktiviert**
- **Hinweise** (Banner) → **aktiviert**
- **Töne** → **aktiviert**
- **Banner** → „Temporär“ oder „Persistent“

---

## 4. Test über Firebase Console (Ursache eingrenzen)

1. **Firebase Console** → Projekt rett-fe0fa → **Cloud Messaging**
2. **„Erste Kampagne erstellen“** oder **„Neue Kampagne“**
3. Benachrichtigungstext eingeben, **„Testnachricht senden“** wählen
4. **FCM-Registrierungstoken** eingeben (aus Firestore: `fcmTokens/{uid}` → Feld `fcmToken`)
5. Senden

**Wenn diese Test-Push ankommt:** APNs/Firebase sind in Ordnung, Problem liegt bei der Cloud Function oder dem Payload.

**Wenn sie nicht ankommt:** APNs-Key oder Geräteeinstellungen prüfen.

## 5. Hinweis: interruption-level

`interruption-level: time-sensitive` wurde aus dem APNs-Payload entfernt. Diese Option erfordert die Capability „Time Sensitive Notifications“ in Xcode. Ohne sie kann iOS die Benachrichtigung anders behandeln. Standard-Push mit `sound: "default"` und `badge` funktioniert ohne diese Capability.

## 6. Schnelltest (Chat-Push)

1. APNs-Key in Firebase prüfen/hochladen
2. App neu bauen und auf Gerät installieren
3. App öffnen, ins Dashboard gehen (Token wird gespeichert)
4. App in den Hintergrund schicken (Home-Taste) oder komplett schließen
5. Von anderem Gerät/Account eine Chat-Nachricht senden

---

## 7. Badge manuell testen

In der App: **Menü (☰) → Einstellungen → Badge testen**

- Setzt das Badge auf 5
- App minimieren (Home-Taste) und App-Icon prüfen
- **Wenn Badge erscheint:** Badge-API funktioniert, Problem liegt bei den Chat-Daten (ungelesene Nachrichten)
- **Wenn kein Badge:** iOS-Benachrichtigungen prüfen (Einstellungen → RettBase → Benachrichtigungen → aktiviert)

## 8. Debug-Log prüfen

In Xcode-Konsole beim App-Start:

```
RettBase Push: APNs-Token vorhanden, hole FCM-Token
RettBase Push: Token gespeichert für uid=... companyId=...
```

Wenn „APNs-Token noch nicht da“ oder „APNs-Token nach Retry weiterhin null“ erscheint → echtes Gerät verwenden, Simulator unterstützt kein Push.
