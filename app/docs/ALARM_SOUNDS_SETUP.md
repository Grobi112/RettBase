# Alarm-Töne einrichten

Die App unterstützt benutzerdefinierte Alarm-Töne für Push-Benachrichtigungen. **Quelle der Wahrheit sind die MP3-Dateien** in **`app/voices/`** (also `RettBase/app/voices/`, **nicht** ein separater Ordner `RettBase/voices/` neben `app/`).

### Ein Befehl für Android + iOS (empfohlen)

Im **App-Ordner** `app/`:

```bash
cd /Users/mikefullbeck/RettBase/app
./scripts/sync_alarm_sounds.sh
```

Das ruft **`setup_android_sounds.sh`** (res/raw) und **`setup_ios_sounds.sh`** (WAV für Push) auf und erzeugt **`lib/generated/alarm_tones.dart`**.

**`setup_android_sounds.sh` allein erzeugt keine iOS-WAVs** – nur **PCM-WAV** für Android `res/raw` (ffmpeg).

**IPA bauen** (macht Sync automatisch):

```bash
cd /Users/mikefullbeck/RettBase/app
./scripts/build_ipa.sh
```

Wenn du im Finder nur MP3s siehst und **keine** frischen WAVs: prüfe, ob du wirklich **`app/voices`** geöffnet hast. Die Skripte schreiben WAVs **dorthin**, wohin die Zeile „Zielordner“ im Terminal zeigt. Zusätzliche Dateien (z. B. nur `.wav` ohne passendes `.mp3`) erscheinen **nicht** in der Ton-Auswahl und werden für Android `res/raw` nicht kopiert.

## Erforderliche Dateien

- Pro Ton: **`Name.mp3`** in `voices/` (beliebiger Name, z. B. `Ton2.mp3`).
- **Android:** `setup_android_sounds.sh` wandelt jede MP3 per **ffmpeg** nach `android/.../res/raw/` in **OGG** (Name normalisiert, z. B. `ton2.ogg`). MP3 als Notification-Kanalton wird auf vielen Geräten nicht zuverlässig abgespielt → System-Fallback.
- **iOS:** Vor dem Build wandelt `setup_ios_sounds.sh` jede MP3 in **`Name.wav`** im gleichen Ordner (Push/APNs). **ffmpeg** nötig: `brew install ffmpeg`.

## Android

- **Automatisch:** `scripts/setup_android_sounds.sh` läuft vor jedem Build (Gradle `syncAlarmSounds`). **ffmpeg** erforderlich (wie iOS).
- **Manuell:** `cd app && ./scripts/setup_android_sounds.sh`
- **Push-Ton (FCM):** Ab Android 8 kommt der Klang vom **Notification-Kanal**. Die App legt pro Datei in `res/raw` einen Kanal **`rett_alarm_w_<rawName>`** (WAV-Kanäle) mit festem Sound und `USAGE_ALARM` an; `sendAlarmPush` setzt nur **`channelId`** (kein separates `notification.sound` für Custom-Töne). **Kanäle sind nach Erstellung unveränderlich** – bei Wechsel Format/Kanal neues Präfix, damit Geräte frische Kanäle anlegen.
- **„Nicht stören“:** Für Alarm-Kanäle ist `setBypassDnd(true)` (API 29+) gesetzt – je nach Gerät/Hersteller und Nutzer-Einstellungen kann der Ton trotzdem gedämpft oder blockiert sein.
- Nach App-Updates mit geänderten Kanälen: ggf. unter **Einstellungen → Apps → RettBase → Benachrichtigungen** prüfen (Kanäle werden beim ersten Start der neuen Version angelegt).

## iOS (Xcode)

- Der Ordner `voices/` liegt als Folder Reference im Projekt; alle Dateien werden ins Bundle kopiert.
- **Wichtig:** Die Build-Phase **„Sync iOS Alarm Sounds“** läuft bei **jedem** Build (`alwaysOutOfDate`), damit nach Änderungen an **beliebigen** `voices/*.mp3` stets neu konvertiert wird und `lib/generated/alarm_tones.dart` aktualisiert wird. Früher waren nur `EFDN-Gong` als Input/Output eingetragen – dann hat Xcode die Phase übersprungen, wenn nur andere MP3s geändert wurden.
- **`scripts/build_ipa.sh`** ruft **`setup_ios_sounds.sh` explizit auf**, bevor `flutter build ipa` läuft – damit WAV + `alarm_tones.dart` sicher zum IPA-Build aktuell sind (nicht nur die Xcode-Phase).
- **Quelle für Push-Ton auf dem Gerät ist die WAV** (APNs). Das Skript erzeugt WAV aus MP3 nur, wenn die **MP3 neuer ist als die WAV** (oder die WAV fehlt). Wenn du **nur die MP3** ersetzt, wird neu konvertiert. Wenn du **nur die WAV** manuell ersetzt und die MP3 älter bleibt, bleibt deine WAV erhalten (wird nicht wieder von alter MP3 überschrieben).
- Ohne **ffmpeg** schlägt der iOS-Build an dieser Phase fehl.

## Systemton

„Systemton (Gerätestandard)“ nutzt den Geräte-Standard – keine Zusatzdateien.
