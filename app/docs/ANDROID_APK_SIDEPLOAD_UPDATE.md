# Android: APK-Update ohne Play Store

## Einheitlicher Ordner: `app/download/`

**Alles, was die Android-App für Sideload-Updates braucht, liegt unter derselben URL-Basis:**

| Datei | Öffentliche URL (Produktion) | Im Repo (vor `flutter build web`) |
|--------|--------------------------------|-----------------------------------|
| **version.json** | `https://app.rettbase.de/app/download/version.json` | `web/app/download/version.json` |
| **rettbase.apk** | `https://app.rettbase.de/app/download/rettbase.apk` | `web/app/download/rettbase.apk` (nach `build_apk.sh`) |

- **Android-App** (`lib/app_config.dart`): lädt **`androidUpdateCheckUrl`** → obige `version.json`; die APK von **`apkUrl`** in der JSON oder Fallback **`androidApkDownloadUrlDefault`**.
- **FTP / manueller Upload:** Immer **beide Dateien** aus **`web/app/download/`** (nach Build) in den Webordner **`app/download/`** legen – **derselbe Ordner**, **kein** separates Root-`version.json` mehr nötig.
- **Firebase Hosting:** `flutter build web` kopiert `web/` nach `build/web/` → die Dateien liegen unter **`build/web/app/download/`** und gehen mit `firebase deploy` mit.

**Alte App-Versionen** (vor dieser Umstellung) fragen noch **`/version.json`** im Root ab. Optional auf dem Server eine **Kopie** oder **Weiterleitung** von `/version.json` auf `/app/download/version.json` bereitstellen, bis alle Nutzer die neue APK haben.

---

Die Flutter-Web-App läuft auf **`app.rettbase.de`**. Firebase liefert aus **`build/web/`**.

## Empfohlen: ein Befehl (APK + version.json + Hosting)

```bash
cd /Users/mikefullbeck/RettBase/app
./scripts/deploy_apk_and_hosting.sh
```

Ablauf:

1. **`build_apk.sh`** – erhöht `pubspec` + **`web/app/download/version.json`** + **`web/index.html`** (Meta), baut die signierte APK, legt **`web/app/download/rettbase.apk`** ab.
2. **`flutter build web`** – **ohne** `./flutter`-Wrapper (der würde `web/increment_version.js` extra ausführen und die Version verwirren).
3. **`firebase deploy --only hosting`**.

Danach: Nutzer **App neu starten** → Update-Dialog, wenn **`versionCode`** in der JSON **größer** ist als der Build der installierten APK.

## Ablauf (manuell / FTP)

1. **`./scripts/build_apk.sh`**
2. **`flutter build web`**
3. **`web/app/download/version.json`** und **`web/app/download/rettbase.apk`** (oder aus **`build/web/app/download/`**) per FTP nach **`…/app/download/`** auf den Server laden.

Live prüfen:

- `https://app.rettbase.de/app/download/version.json` (muss **`versionCode`** und idealerweise **`apkUrl`** enthalten)
- `https://app.rettbase.de/app/download/rettbase.apk`

## Konfiguration (App)

- `lib/app_config.dart`: `androidUpdateCheckUrl`, `androidApkDownloadUrlDefault`

## Build lokal

```bash
./scripts/build_apk.sh
```

### Kein manuelles Umbenennen der APK

- **`./scripts/flutter_apk_release.sh`** – nur APK + `rettbase.apk` im Build-Ordner
- **`./scripts/build_apk.sh`** – wie oben
- **`./scripts/deploy_apk_and_hosting.sh`** – inkl. Web + Firebase

## `version.json`-Beispiel

```json
{
  "version": "1.0.53",
  "versionCode": 54,
  "apkUrl": "https://app.rettbase.de/app/download/rettbase.apk",
  "releaseNotes": ""
}
```

## Update-Hinweis erscheint nicht?

1. **Gleicher Build wie online:** Wenn du die **neu gebaute** APK sofort installierst, ist `versionCode` gleich dem Server → kein Dialog (erwartet).
2. **Richtige URL:** Browser/App müssen **`…/app/download/version.json`** laden (nach App-Update), nicht mehr nur `/version.json`.
3. **FTP:** Beide Dateien wirklich im Ordner **`app/download/`**?
4. **Logs:** `adb logcat | grep RettBase.apkUpdate`

## Hinweise

- **Gleiche Signatur** wie die installierte App (sonst kein Update).
- **`version.json`** nicht aggressiv cachen (CDN/Server).
- Installation: Nutzer bestätigt weiter den Android-Dialog „Installieren“.
