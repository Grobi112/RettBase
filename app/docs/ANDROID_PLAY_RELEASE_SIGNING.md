# Android: Release-Signierung für Google Play

Die Play Console akzeptiert nur **Release-signierte** App Bundles. Wenn die Meldung erscheint, dass das AAB **im Debug-Modus signiert** wurde, fehlt die Konfiguration unten oder der Build lief ohne gültige `key.properties`.

## 1. Upload-Keystore anlegen (einmalig)

Im Terminal (Passwörter sicher notieren / Passwort-Manager):

```bash
cd app/android
keytool -genkey -v -keystore upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- **Alias** muss zu `keyAlias` in `key.properties` passen (Standard hier: `upload`).
- Datei `upload-keystore.jks` im Ordner `android/` ablegen (liegt bereits in `.gitignore`).

## 2. `key.properties` anlegen

```bash
cp key.properties.example key.properties
```

`key.properties` bearbeiten:

- `storePassword` / `keyPassword` wie bei `keytool`
- `keyAlias` wie bei `keytool` (z. B. `upload`)
- `storeFile` relativ zu `android/`, z. B. `upload-keystore.jks`

## 3. Release-Bundle bauen

```bash
cd app
flutter build appbundle
```

oder `./scripts/build_aab.sh` (erhöht vorher die Version in `pubspec.yaml`).

Die signierte Datei liegt unter:

`build/app/outputs/bundle/release/app-release.aab`

## Hinweise

- **Keystore verlieren** = keine Updates mehr mit derselben App-ID auf Play möglich. Backup sicher aufbewahren.
- Google Play **App Signing** kann den Upload-Key ersetzen; der **App-Signing-Key** bleibt bei Google – Upload-Key nur für deine Uploads.
- Ohne `key.properties` nutzt das Projekt weiterhin **Debug-Signatur** für `release` (nur lokal); für Play **immer** `key.properties` setzen.
