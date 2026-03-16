#!/bin/bash
# Kopiert Sound-Dateien von voices/ nach android/app/src/main/res/raw/
# Für benutzerdefinierte Alarm-Töne bei Push-Benachrichtigungen.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
VOICES="$APP_DIR/voices"
RAW="$APP_DIR/android/app/src/main/res/raw"

mkdir -p "$RAW"
cp "$VOICES/EFDN-Gong.mp3" "$RAW/efdn_gong.mp3"
cp "$VOICES/gong-brand.wav" "$RAW/gong_brand.wav"
cp "$VOICES/Kleinalarm.wav" "$RAW/kleinalarm.wav"
cp "$VOICES/Melder1.wav" "$RAW/melder1.wav"
cp "$VOICES/Melder2.mp3" "$RAW/melder2.mp3"
echo "Android-Sounds nach res/raw kopiert."
