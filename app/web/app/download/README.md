# Ordner `web/app/download/` – Android-Updates & Web

**Ein Ordner** für alles, was Sideload-Updates und die App/Web brauchen:

| Datei | Rolle |
|--------|--------|
| **`version.json`** | Von **Android** und **Web** abgerufen (`AppConfig.androidUpdateCheckUrl`). Enthält u. a. `version`, **`versionCode`**, **`apkUrl`**. |
| **`rettbase.apk`** | Installierbare Android-App (wird von **`./scripts/build_apk.sh`** hierher kopiert). |

Öffentliche URLs (Domain `app.rettbase.de`):

- `https://app.rettbase.de/app/download/version.json`
- `https://app.rettbase.de/app/download/rettbase.apk`

**FTP:** Genau diesen Ordner (`app/download/` auf dem Server) mit beiden Dateien füllen – passt 1:1 zu `web/app/download/` nach dem Build.

`rettbase.apk` ist oft **`.gitignore`** (groß); `version.json` liegt im Repo. Lokal nach `build_apk.sh` sind beide Dateien vorhanden.
