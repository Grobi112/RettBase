# Alarm-Töne einrichten

Die App unterstützt benutzerdefinierte Alarm-Töne für Push-Benachrichtigungen. **Quelle der Wahrheit sind die MP3-Dateien** in **`app/voices/`** (also `RettBase/app/voices/`, **nicht** ein separater Ordner `RettBase/voices/` neben `app/`).

Wenn du im Finder nur MP3s siehst und **keine** frischen WAVs: prüfe, ob du wirklich **`app/voices`** geöffnet hast. Die Skripte schreiben WAVs **dorthin**, wohin die Zeile „Zielordner“ im Terminal zeigt. Zusätzliche Dateien (z. B. nur `.wav` ohne passendes `.mp3`) erscheinen **nicht** in der Ton-Auswahl und werden für Android `res/raw` nicht kopiert.

## Erforderliche Dateien

- Pro Ton: **`Name.mp3`** in `voices/` (beliebiger Name, z. B. `Ton2.mp3`).
- **Android:** `setup_android_sounds.sh` kopiert jede MP3 nach `android/.../res/raw/` (Name normalisiert, z. B. `ton2.mp3`).
- **iOS:** Vor dem Build wandelt `setup_ios_sounds.sh` jede MP3 in **`Name.wav`** im gleichen Ordner (Push/APNs). **ffmpeg** nötig: `brew install ffmpeg`.

## Android

- **Automatisch:** `scripts/setup_android_sounds.sh` läuft vor jedem Build (Gradle `syncAlarmSounds`).
- **Manuell:** `cd app && ./scripts/setup_android_sounds.sh`

## iOS (Xcode)

- Der Ordner `voices/` liegt als Folder Reference im Projekt; alle Dateien werden ins Bundle kopiert.
- **Wichtig:** Die Build-Phase **„Sync iOS Alarm Sounds“** läuft bei **jedem** Build (`alwaysOutOfDate`), damit nach Änderungen an **beliebigen** `voices/*.mp3` stets neu konvertiert wird und `lib/generated/alarm_tones.dart` aktualisiert wird. Früher waren nur `EFDN-Gong` als Input/Output eingetragen – dann hat Xcode die Phase übersprungen, wenn nur andere MP3s geändert wurden.
- Ohne **ffmpeg** schlägt der iOS-Build an dieser Phase fehl.

## Systemton

„Systemton (Gerätestandard)“ nutzt den Geräte-Standard – keine Zusatzdateien.
