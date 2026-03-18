#!/bin/bash
# Kopiert alle Alarm-Töne von voices/ nach android/app/src/main/res/raw/
# Wird automatisch vor jedem Android-Build ausgeführt.
# Android res/raw: lowercase, Sonderzeichen → Unterstrich.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"
RAW="$APP_DIR/android/app/src/main/res/raw"

mkdir -p "$RAW"

# Dateiname → Android raw-Name (lowercase, - und Leerzeichen → _)
to_raw_name() {
  echo "$1" | sed 's/\.mp3$//' | tr '[:upper:]' '[:lower:]' | tr -s ' -' '_' | tr -cd 'a-z0-9_'
}

echo "Android-Alarmtöne: alle MP3 aus voices/ nach res/raw kopieren..."
count=0
for mp3 in "$VOICES"/*.mp3; do
  [[ -f "$mp3" ]] || continue
  raw=$(to_raw_name "$(basename "$mp3")")
  [[ -n "$raw" ]] || continue
  cp "$mp3" "$RAW/${raw}.mp3"
  echo "  $(basename "$mp3") → ${raw}.mp3"
  ((count++)) || true
done
echo "Fertig ($count Dateien)."

# Dart-Liste für App-Auswahl generieren
"$SCRIPT_DIR/generate_alarm_tones.sh"
