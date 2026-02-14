# Web-Push (Chat-Benachrichtigungen) einrichten

Damit Chat-Push-Benachrichtigungen auch in der WebApp funktionieren, muss ein **VAPID-Key** konfiguriert werden.

## Schritte

### 1. VAPID-Key in Firebase erzeugen

1. Öffne [Firebase Console](https://console.firebase.google.com/) und wähle das Projekt **rett-fe0fa**
2. Gehe zu **Projekt-Einstellungen** (Zahnrad) → **Cloud Messaging**
3. Scrolle zu **Web-Konfiguration**
4. Unter **Web-Push-Zertifikate** auf **Schlüsselpaar erzeugen** klicken
5. Den angezeigten **Öffentlichen Schlüssel** (langer String, beginnt z.B. mit `B...`) kopieren

### 2. Key in die App eintragen

In `lib/app_config.dart` den Wert setzen:

```dart
static const String? fcmWebVapidKey = 'BKagOny0KF_2pCJQ3m...';  // Dein Schlüssel hier
```

Ohne diesen Key werden auf Web **keine FCM-Tokens** abgerufen – Push funktioniert dann nur auf iOS/Android.

### 3. Web-App neu deployen

Nach dem Eintragen: `flutter build web` und Deploy (z.B. Firebase Hosting).

### 4. Berechtigung prüfen

Beim ersten Besuch der WebApp fragt der Browser nach Benachrichtigungs-Berechtigung. Der Nutzer muss **Erlauben** wählen.

### 5. PWA-Icon-Badge ( ungelesene Chat-Nachrichten)

**Plattform-Unterstützung:**

| Plattform | Badge (Zahl auf App-Icon) |
|-----------|---------------------------|
| **Safari iOS/iPadOS** (ab 16.4) | ✅ Funktioniert – **wenn** Benachrichtigungs-Berechtigung erteilt |
| **Chrome Android** | ❌ Nicht unterstützt – Badging API fehlt, kein programmatisches Badge möglich |
| **Chrome/Edge Desktop** (Windows/macOS) | ✅ Funktioniert bei installierter PWA |

**Safari iOS – Checkliste:**
- PWA zum Startbildschirm hinzugefügt
- App vom **Startbildschirm-Icon** öffnen (nicht als Tab in Safari)
- Benachrichtigungen **erlauben** (in Einstellungen oder beim ersten Aufruf)
- Der „Badge testen“-Button in den App-Einstellungen prüft, ob die API verfügbar ist
- Bei Problemen: App einmal vollständig schließen und vom Startbildschirm neu öffnen

**Chrome Android:** Ein Badge kann nur indirekt erscheinen, wenn eine Benachrichtigung angezeigt wird (z.B. bei neuem Push). Nach dem Schließen der Benachrichtigung verschwindet das Badge.

---

**Technisch:** Der `firebase-messaging-sw.js` Service Worker zeigt Push-Nachrichten auch bei geschlossenem Tab. Der VAPID-Key identifiziert deine Web-App gegenüber den Push-Servern.
