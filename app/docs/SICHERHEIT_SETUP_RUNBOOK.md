# Sicherheits-Setup – Schritt-für-Schritt-Runbook

Nach dem [Sicherheitsaudit](SICHERHEITSAUDIT.md) sollten diese Schritte durchgeführt werden.

---

## Teil 1: Firebase App Check mit reCAPTCHA (Web) – *optional, aktuell nicht verwendet*

*Entscheidung: reCAPTCHA/App Check für Web wird nicht eingesetzt. Der Rate-Limit (5 Aufrufe/Minute) schützt ausreichend.*

Falls du App Check später doch aktivieren möchtest:

### 1.1 Web-App in App Check registrieren (falls noch nicht geschehen)

1. Öffne: https://console.firebase.google.com/project/rett-fe0fa/appcheck
2. **"Registrieren"** oder **"App registrieren"** klicken (nur wenn die Web-App dort noch nicht erscheint)
3. **Plattform:** Web auswählen
4. **App-Nickname:** z.B. "RettBase Web"
5. **Provider:** „reCAPTCHA v3“ auswählen
6. Firebase führt ggf. zu reCAPTCHA Admin → dort **reCAPTCHA v3** Domains hinzufügen:
   - `*.rettbase.de`
   - `rettbase.de`
   - `localhost` (für lokale Entwicklung)
7. **Site Key** kopieren (Format: `6Lc...`)

*Wenn die App bereits in App Check registriert ist: nur den Site Key aus der bestehenden Registrierung kopieren.*

### 1.2 Key in die App eintragen

**Variante A – direkt im Code (empfohlen für Start):**

- Öffne `lib/app_config.dart`
- Trage den Key in `_appCheckRecaptchaSiteKeyConst` ein:
  ```dart
  static const String? _appCheckRecaptchaSiteKeyConst = '6LcXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
  ```

**Variante B – per Build-Argument (z.B. für CI):**

```bash
flutter build web --dart-define=RETTBASE_APP_CHECK_SITE_KEY=6LcXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

### 1.3 Enforcement aktivieren

1. In Firebase Console → **App Check** → **APIs**
2. **Cloud Functions** auswählen → **"Durchsetzung aktivieren"**
3. Zuerst **Metriken beobachten**, danach Enforcement – sonst können legitime Nutzer blockiert werden

---

## Teil 2: API-Key-Einschränkung (Google Cloud Console)

Begrenzt die Nutzung des Firebase API-Keys auf deine App(s).

### 2.1 Console öffnen

1. Öffne: https://console.cloud.google.com/apis/credentials?project=rett-fe0fa

### 2.2 API-Key bearbeiten

1. Den **API-Key** wählen, den die Flutter-App nutzt
2. **Bearbeiten** klicken (Stift-Icon)

### 2.3 Anwendungseinschränkungen

| Plattform | Einschränkung | Wert |
|-----------|---------------|------|
| **Web** | HTTP-Referrer | `https://*.rettbase.de/*` |
| | | `https://rettbase.de/*` |
| | | `https://localhost:*/*` |
| | | `https://127.0.0.1:*/*` |
| **Android** | App-Paketname | `com.mikefullbeck.rettbase` |
| | SHA-1 Zertifikat | (siehe unten) |
| **iOS** | Bundle-ID | `com.mikefullbeck.rettbase` |

### 2.4 SHA-1 für Android ermitteln

```bash
cd app
./scripts/get_android_sha1.sh
```

Oder manuell:

```bash
# Debug (Entwicklung)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android

# Release (eigener Keystore)
keytool -list -v -keystore /pfad/zum/release.keystore -alias dein-alias
```

Die ausgegebenen **SHA-1** und **SHA-256** Fingerprints in der Google Cloud Console unter dem API-Key eintragen.

### 2.5 API-Einschränkungen

Unter **API-Einschränkungen** nur benötigte APIs zulassen:

- Cloud Firestore API
- Firebase Authentication
- Firebase Cloud Messaging
- Cloud Functions (Callable)
- Firebase Storage

---

## Checkliste (zum Abhaken)

- [ ] ~~App Check~~ (nicht verwendet, Rate-Limit reicht)
- [ ] API-Key: Anwendungseinschränkungen (Web + Android/iOS) gesetzt
- [ ] API-Key: SHA-1 für Android hinzugefügt
- [ ] API-Key: API-Einschränkungen gesetzt
