#!/bin/bash
# Alarm-Töne: voices/*.mp3 → android/app/src/main/res/raw/*.wav (PCM, ffmpeg).
# Wird automatisch vor jedem Android-Build ausgeführt (Gradle).
# Android res/raw: lowercase, Sonderzeichen → Unterstrich.
#
# WICHTIG: MP3 in NotificationChannel.setSound() führt auf vielen Geräten zum
# Fallback auf den Systemton. PCM-WAV wird überall decodiert (kein libvorbis nötig).
# ffmpeg wie bei iOS: brew install ffmpeg
#
# Erzeugt KEINE iOS-WAVs. Für iOS: ./scripts/setup_ios_sounds.sh
# Oder beides auf einmal: ./scripts/sync_alarm_sounds.sh (wird von build_ipa.sh genutzt).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"
RAW="$APP_DIR/android/app/src/main/res/raw"

mkdir -p "$RAW"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "FEHLER: ffmpeg nicht gefunden. Für Android-Alarm-WAVs nötig (z. B. brew install ffmpeg)." >&2
  exit 1
fi

echo "MP3-Quelle: $VOICES"
echo "Android res/raw (WAV): $RAW"

# Dateiname → Android raw-Name (lowercase, - und Leerzeichen → _)
to_raw_name() {
  echo "$1" | sed -e 's/\.mp3$//' -e 's/\.wav$//' | tr '[:upper:]' '[:lower:]' | tr -s ' -' '_' | tr -cd 'a-z0-9_'
}

echo "Android-Alarmtöne: MP3/WAV → PCM-WAV nach res/raw …"
count=0
shopt -s nullglob
mp3_sorted=()
while IFS= read -r line; do
  [[ -n "$line" ]] && mp3_sorted+=("$line")
done < <(printf '%s\n' "$VOICES"/*.mp3 | LC_ALL=C sort)

for mp3 in "${mp3_sorted[@]}"; do
  [[ -f "$mp3" ]] || continue
  raw=$(to_raw_name "$(basename "$mp3")")
  [[ -n "$raw" ]] || continue
  # Gleicher R.raw-Name wie früher (ton1), nur eine Datei pro Basisname
  rm -f "$RAW/${raw}.mp3" "$RAW/${raw}.ogg"
  ffmpeg -y -hide_banner -loglevel error -i "$mp3" -acodec pcm_s16le -ar 44100 -ac 1 "$RAW/${raw}.wav"
  echo "  $(basename "$mp3") → ${raw}.wav"
  ((count++)) || true
done

# WAV-Quellen (z. B. nur EFDN-Gong.wav ohne MP3): sonst überspringt Gradle-Sync fälschlich
# oder es fehlen Kanäle rett_alarm_w_* für FCM.
wav_sorted=()
while IFS= read -r line; do
  [[ -n "$line" ]] && wav_sorted+=("$line")
done < <(printf '%s\n' "$VOICES"/*.wav | LC_ALL=C sort)

for wav in "${wav_sorted[@]}"; do
  [[ -f "$wav" ]] || continue
  raw=$(to_raw_name "$(basename "$wav")")
  [[ -n "$raw" ]] || continue
  # MP3 hat Vorrang (gleicher Basisname)
  if [[ -f "$VOICES/$(basename "$wav" .wav).mp3" ]]; then
    echo "  überspringe $(basename "$wav") (MP3 vorhanden)"
    continue
  fi
  rm -f "$RAW/${raw}.mp3" "$RAW/${raw}.ogg"
  ffmpeg -y -hide_banner -loglevel error -i "$wav" -acodec pcm_s16le -ar 44100 -ac 1 "$RAW/${raw}.wav"
  echo "  $(basename "$wav") → ${raw}.wav"
  ((count++)) || true
done
shopt -u nullglob
echo "Fertig ($count Dateien)."

# Dart-Liste für App-Auswahl generieren
"$SCRIPT_DIR/generate_alarm_tones.sh"
