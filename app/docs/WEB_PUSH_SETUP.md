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

**Safari iOS – Checkliste (Chrome auf iPhone unterstützt Badge NICHT):**
- **Nur Safari** verwenden – Chrome auf iPhone unterstützt die Badge-API nicht (nutzt WebKit, aber API ist in Chrome nicht verfügbar)
- In **Safari** app.rettbase.de öffnen → „Zum Home-Bildschirm“ hinzufügen
- App vom **Startbildschirm-Icon** öffnen (nicht als Tab, nicht aus Chrome)
- Benachrichtigungen **erlauben** (in Einstellungen oder beim ersten Aufruf)
- Der „Badge testen“-Button in den App-Einstellungen prüft, ob die API verfügbar ist
- Bei Problemen: App einmal vollständig schließen und vom Startbildschirm neu öffnen

**Chrome Android:** Ein Badge kann nur indirekt erscheinen, wenn eine Benachrichtigung angezeigt wird (z.B. bei neuem Push). Nach dem Schließen der Benachrichtigung verschwindet das Badge.

---

## 6. PWA zeigt weißen Bildschirm oder lädt sehr langsam

**Mögliche Ursachen und Lösungen:**

1. **Service Worker / Cache:** Alte Version blockiert oder Firestore/Firebase-Skripte laden langsam.  
   - PWA vom Startbildschirm entfernen  
   - Im Browser: Einstellungen → Website-Daten löschen (oder „Site-Daten und -Berechtigungen entfernen“)  
   - Neu zum Startbildschirm hinzufügen  
   - Die App nutzt `firebase-messaging-sw.js` für Push – beim ersten Öffnen nach langer Pause kann das Laden ein paar Sekunden dauern (Firebase-Skripte von gstatic.com). Preload-Links in `index.html` beschleunigen das.

2. **Unterordner-Deployment:** Läuft die App unter einem Unterordner (z.B. `www.rettbase.de/app/`)?  
   - Beim Build: `flutter build web --base-href /app/`  
   - Im GitHub-Workflow den Schritt „Web-App bauen“ entsprechend anpassen

3. **App steht im Domain-Root:** Wenn die App unter `www.rettbase.de/` liegt, ist `base-href="/"` korrekt (Standard).

4. **Langsames Laden auf Mobile:** Der Standard-Renderer (CanvasKit) lädt ~2 MB WebAssembly – auf mobilen Verbindungen oft langsam. Der GitHub-Workflow nutzt `--web-renderer html` für schnellere Ladezeiten.

---

## 7. Push funktioniert nicht, wenn die App zu / im Hintergrund ist

**Mögliche Ursachen:**

1. **Benachrichtigungs-Berechtigung nicht erteilt:** Ohne Erlaubnis wird kein FCM-Token gespeichert.  
   - Im **Chat** erscheint ein auffälliger Banner „Push-Benachrichtigungen“ – darauf tippen und „Erlauben“ wählen  
   - Alternativ: Menü → „Benachrichtigungen aktivieren“

2. **Kein FCM-Token in Firestore:** Die Cloud Function sendet nur an gespeicherte Tokens.  
   - Im Projektordner ausführen: `cd app/functions && node scripts/check_fcm_tokens.js nfsunna`  
   - Zeigt, welche Nutzer (uid) einen Token haben – fehlt der Token, hat der Nutzer Push nie aktiviert

3. **Push-Link:** Der Klick-Link in der Benachrichtigung führt zu `app.rettbase.de` (konfigurierbar in `functions/index.js` als `WEB_APP_BASE_URL`). Muss zur tatsächlichen App-URL passen.

4. **Cloud Functions deployed?** Nach Änderungen: `firebase deploy --only functions`

---

**Technisch:** Der `firebase-messaging-sw.js` Service Worker zeigt Push-Nachrichten auch bei geschlossenem Tab. Der VAPID-Key identifiziert deine Web-App gegenüber den Push-Servern.
