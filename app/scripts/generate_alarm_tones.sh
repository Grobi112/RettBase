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

const List<({String id, String assetPath, String label})> kAlarmToneOptions = [
  (id: 'system', assetPath: '', label: 'Systemton (Gerätestandard)'),
HEADER

for mp3 in "$VOICES"/*.mp3; do
  [[ -f "$mp3" ]] || continue
  base=$(basename "$mp3" .mp3)
  label=$(label_from_name "$base")
  echo "  (id: '$(basename "$mp3")', assetPath: 'voices/$(basename "$mp3")', label: '$label')," >> "$OUT"
done

cat >> "$OUT" << 'FOOTER'
];
FOOTER

echo "  alarm_tones.dart generiert ($(grep -c "assetPath:" "$OUT" || true) Töne)."
