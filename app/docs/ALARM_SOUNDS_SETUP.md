# Alarm-Töne einrichten

Die App unterstützt benutzerdefinierte Alarm-Töne für Push-Benachrichtigungen. Die Sound-Dateien müssen für **Android** und **iOS** separat bereitgestellt werden.

## Erforderliche Dateien

Die folgenden Dateien müssen in `app/voices/` liegen (für Flutter-Assets und Vorschau):

| Datei | Android res/raw Name | iOS Bundle-Name |
|-------|----------------------|-----------------|
| EFDN-Gong.mp3 | efdn_gong | EFDN-Gong.mp3 |
| gong-brand.wav | gong_brand | gong-brand.wav |
| Kleinalarm.wav | kleinalarm | Kleinalarm.wav |
| Melder1.wav | melder1 | Melder1.wav |
| Melder2.mp3 | melder2 | Melder2.mp3 |

## Android

1. Sound-Dateien in `app/voices/` ablegen.
2. Skript ausführen:
   ```bash
   cd app && ./scripts/setup_android_sounds.sh
   ```
   Oder manuell kopieren:
   ```bash
   cp voices/EFDN-Gong.mp3 android/app/src/main/res/raw/efdn_gong.mp3
   cp voices/gong-brand.wav android/app/src/main/res/raw/gong_brand.wav
   cp voices/Kleinalarm.wav android/app/src/main/res/raw/kleinalarm.wav
   cp voices/Melder1.wav android/app/src/main/res/raw/melder1.wav
   cp voices/Melder2.mp3 android/app/src/main/res/raw/melder2.mp3
   ```

## iOS

1. Sound-Dateien in `app/voices/` ablegen.
2. In Xcode: `ios/Runner` öffnen, rechte Maustaste auf `Runner` → "Add Files to Runner…"
3. Alle Dateien aus `voices/` auswählen, "Copy items if needed" aktivieren, Target "Runner" anhaken.
4. Sicherstellen, dass die Dateien im Build-Phases → "Copy Bundle Resources" enthalten sind.

## Systemton

Wenn der Nutzer "Systemton (Gerätestandard)" wählt, wird der vom Gerät eingestellte Standard-Benachrichtigungston verwendet – keine zusätzlichen Dateien nötig.
