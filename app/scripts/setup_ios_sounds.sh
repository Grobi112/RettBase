#!/bin/bash
# Konvertiert Alarm-Töne MP3 → WAV für iOS (PUSH-PFLICHT).
# iOS unterstützt KEINE MP3 für Push-Sounds – nur AIFF, WAV, CAF.
# Erfordert ffmpeg. Läuft automatisch vor jedem iOS-Build.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"

if [[ ! -d "$VOICES" ]]; then
  echo "voices/ nicht gefunden: $VOICES"
  exit 1
fi

if ! command -v ffmpeg &>/dev/null; then
  echo "FEHLER: ffmpeg fehlt. iOS-Alarmtöne müssen aus MP3 konvertiert werden."
  echo "Installation: brew install ffmpeg"
  exit 1
fi

echo "iOS-Alarmtöne: alle MP3 in voices/ → WAV konvertieren..."
count=0
for mp3 in "$VOICES"/*.mp3; do
  [[ -f "$mp3" ]] || continue
  base=$(basename "$mp3" .mp3)
  wav="$VOICES/${base}.wav"
  if ffmpeg -y -i "$mp3" -acodec pcm_s16le -ar 44100 "$wav" 2>/dev/null; then
    echo "  $(basename "$mp3") → ${base}.wav"
    ((count++)) || true
  fi
done
echo "Fertig ($count Dateien konvertiert)."

# Dart-Liste für App-Auswahl generieren
"$SCRIPT_DIR/generate_alarm_tones.sh"
