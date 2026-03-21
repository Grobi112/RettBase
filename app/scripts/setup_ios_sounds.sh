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

# Immer absolut ausgeben – es gibt oft zwei Ordner: RettBase/voices vs. RettBase/app/voices
echo "Zielordner (hier landen die WAVs): $VOICES"

if ! command -v ffmpeg &>/dev/null; then
  echo "FEHLER: ffmpeg fehlt. iOS-Alarmtöne müssen aus MP3 konvertiert werden."
  echo "Installation: brew install ffmpeg"
  exit 1
fi

echo "iOS-Alarmtöne: MP3 in voices/ → WAV (immer neu aus MP3, damit der Build nie alte WAVs mitnimmt)…"
count=0
shopt -s nullglob
mp3_sorted=()
while IFS= read -r line; do
  [[ -n "$line" ]] && mp3_sorted+=("$line")
done < <(printf '%s\n' "$VOICES"/*.mp3 | LC_ALL=C sort)

for mp3 in "${mp3_sorted[@]}"; do
  [[ -f "$mp3" ]] || continue
  base=$(basename "$mp3" .mp3)
  wav="$VOICES/${base}.wav"
  if ffmpeg -y -nostdin -i "$mp3" -acodec pcm_s16le -ar 44100 "$wav"; then
    echo "  $(basename "$mp3") → ${base}.wav"
    ((count++)) || true
  else
    echo "FEHLER: ffmpeg für $mp3" >&2
    exit 1
  fi
done
shopt -u nullglob
echo "Fertig ($count MP3 → WAV)."

# Dart-Liste für App-Auswahl generieren
"$SCRIPT_DIR/generate_alarm_tones.sh"
