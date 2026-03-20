#!/bin/bash
# Erzeugt lib/generated/alarm_tones.dart aus allen MP3-Dateien in voices/.
# Wird von setup_ios_sounds.sh und setup_android_sounds.sh aufgerufen.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"
OUT="$APP_DIR/lib/generated/alarm_tones.dart"

mkdir -p "$(dirname "$OUT")"

# Label aus Dateiname: "Ton1" -> "Ton 1", "EFDN-Gong" -> "EFDN-Gong"
label_from_name() {
  local name="$1"
  if [[ "$name" =~ ^Ton([0-9]+)$ ]]; then
    echo "Ton ${BASH_REMATCH[1]}"
  else
    echo "$name"
  fi
}

cat > "$OUT" << 'HEADER'
// Auto-generated from voices/*.mp3 – nicht manuell bearbeiten.
// Wird von scripts/generate_alarm_tones.sh erzeugt.
// Quelle der Wahrheit: MP3-Dateien in voices/ (iOS-WAV wird aus MP3 erzeugt).

const List<({String id, String assetPath, String label})> kAlarmToneOptions = [
  (id: 'system', assetPath: '', label: 'Systemton (Gerätestandard)'),
HEADER

# Sortiert, damit die Reihenfolge stabil ist; nullglob = leeres Glob wenn keine MP3s
shopt -s nullglob
mp3_sorted=()
while IFS= read -r line; do
  [[ -n "$line" ]] && mp3_sorted+=("$line")
done < <(printf '%s\n' "$VOICES"/*.mp3 | LC_ALL=C sort)

for mp3 in "${mp3_sorted[@]}"; do
  [[ -f "$mp3" ]] || continue
  base=$(basename "$mp3" .mp3)
  label=$(label_from_name "$base")
  echo "  (id: '$(basename "$mp3")', assetPath: 'voices/$(basename "$mp3")', label: '$label')," >> "$OUT"
done
shopt -u nullglob

cat >> "$OUT" << 'FOOTER'
];
FOOTER

echo "  alarm_tones.dart generiert ($(grep -c "assetPath:" "$OUT" || true) Töne)."
