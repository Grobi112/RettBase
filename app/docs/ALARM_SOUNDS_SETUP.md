# Alarm-Töne einrichten

Die App unterstützt benutzerdefinierte Alarm-Töne für Push-Benachrichtigungen. **Alle Töne** werden im Ordner `app/voices/` hinterlegt und bei jedem App-Neubau/Update automatisch übernommen.

## Erforderliche Dateien

Die folgenden Dateien müssen in `app/voices/` liegen (alle mp3-Format):

| Datei | Android res/raw Name | iOS Bundle-Name |
|-------|----------------------|-----------------|
| EFDN-Gong.mp3 | efdn_gong | EFDN-Gong.mp3 |
| Ton1.mp3 | ton1 | Ton1.mp3 |
| Ton2.mp3 | ton2 | Ton2.mp3 |
| Ton3.mp3 | ton3 | Ton3.mp3 |
| Ton4.mp3 | ton4 | Ton4.mp3 |

**Wichtig:** Änderungen an einer Datei (gleicher Name) werden beim nächsten App-Build automatisch übernommen – keine manuellen Kopierschritte nötig.

## Android

- **Automatisch:** Das Skript `scripts/setup_android_sounds.sh` wird vor jedem Build ausgeführt (Gradle-Task `syncAlarmSounds`).
- **Manuell** (falls nötig):
  ```bash
  cd app && ./scripts/setup_android_sounds.sh
  ```

## iOS

- **Automatisch:** Der Ordner `voices/` ist als Referenz im Xcode-Projekt eingebunden (`../voices`). Alle Dateien darin werden beim Build ins App-Bundle kopiert.
- Änderungen an Dateien in `voices/` werden beim nächsten Build automatisch übernommen.

## Systemton

Wenn der Nutzer "Systemton (Gerätestandard)" wählt, wird der vom Gerät eingestellte Standard-Benachrichtigungston verwendet – keine zusätzlichen Dateien nötig.
