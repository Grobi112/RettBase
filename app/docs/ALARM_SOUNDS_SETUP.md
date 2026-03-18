# Alarm-Töne einrichten

Die App unterstützt benutzerdefinierte Alarm-Töne für Push-Benachrichtigungen. **Alle Töne** werden im Ordner `app/voices/` hinterlegt und bei jedem App-Neubau/Update automatisch übernommen.

## Erforderliche Dateien

| Datei | Android res/raw | iOS Bundle |
|-------|-----------------|------------|
| EFDN-Gong.mp3 | efdn_gong | EFDN-Gong.**wav** |
| Ton1.mp3 | ton1 | Ton1.**wav** |
| Ton2.mp3 | ton2 | Ton2.**wav** |
| Ton3.mp3 | ton3 | Ton3.**wav** |
| Ton4.mp3 | ton4 | Ton4.**wav** |

**Android:** Nutzt MP3 aus `voices/` (wird nach `res/raw/` kopiert).

**iOS:** Nutzt **WAV** (nicht MP3!). iOS unterstützt für Push-Sounds nur AIFF, WAV, CAF. Die Cloud Function sendet automatisch `.wav` statt `.mp3`. **Pflicht:** `ffmpeg` muss installiert sein (`brew install ffmpeg`). Das Skript `setup_ios_sounds.sh` läuft automatisch vor jedem iOS-Build und konvertiert MP3 → WAV.

## Android

- **Automatisch:** Das Skript `scripts/setup_android_sounds.sh` wird vor jedem Build ausgeführt (Gradle-Task `syncAlarmSounds`).
- **Manuell** (falls nötig):
  ```bash
  cd app && ./scripts/setup_android_sounds.sh
  ```

## iOS

- **Automatisch:** Der Ordner `voices/` ist als Referenz im Xcode-Projekt eingebunden (`../voices`). Alle Dateien darin werden beim Build ins App-Bundle kopiert.
- **ffmpeg erforderlich:** Vor dem iOS-Build werden MP3 automatisch in WAV konvertiert. Dafür muss ffmpeg installiert sein: `brew install ffmpeg`. Ohne ffmpeg schlägt der iOS-Build fehl.

## Systemton

Wenn der Nutzer "Systemton (Gerätestandard)" wählt, wird der vom Gerät eingestellte Standard-Benachrichtigungston verwendet – keine zusätzlichen Dateien nötig.
