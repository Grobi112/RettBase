#!/bin/bash
# Kopiert Alarm-Töne von voices/ nach android/app/src/main/res/raw/
# Wird automatisch vor jedem Android-Build ausgeführt.
# Quelle: voices/ (EFDN-Gong.mp3, Ton1.mp3, Ton2.mp3, Ton3.mp3, Ton4.mp3)

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"
RAW="$APP_DIR/android/app/src/main/res/raw"

mkdir -p "$RAW"

# Mapping: voices-Dateiname -> Android res/raw (lowercase, ohne Sonderzeichen)
copy_sound() {
  local src="$1"
  local dst="$2"
  if [[ -f "$VOICES/$src" ]]; then
    cp "$VOICES/$src" "$RAW/$dst"
  else
    echo "Warnung: $VOICES/$src nicht gefunden, übersprungen."
  fi
}

copy_sound "EFDN-Gong.mp3" "efdn_gong.mp3"
copy_sound "Ton1.mp3" "ton1.mp3"
copy_sound "Ton2.mp3" "ton2.mp3"
copy_sound "Ton3.mp3" "ton3.mp3"
copy_sound "Ton4.mp3" "ton4.mp3"

echo "Android-Alarmtöne nach res/raw kopiert."
