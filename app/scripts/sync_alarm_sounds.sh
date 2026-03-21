#!/bin/bash
# Alle Alarmtöne aus app/voices/*.mp3:
#   1) Android → android/app/src/main/res/raw/*.wav (ffmpeg, PCM)
#   2) iOS     → WAV in app/voices/ (Push/APNs) via ffmpeg
#   3) Dart    → lib/generated/alarm_tones.dart
#
# Immer aus dem App-Root ausführen:
#   cd /Users/.../RettBase/app && ./scripts/sync_alarm_sounds.sh
#
# Wird von build_ipa.sh automatisch aufgerufen.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"

cd "$APP_DIR"
echo "=== sync_alarm_sounds.sh ==="
echo "App-Verzeichnis: $APP_DIR"

bash "$SCRIPT_DIR/setup_android_sounds.sh"
bash "$SCRIPT_DIR/setup_ios_sounds.sh"

echo "=== Alarmtöne synchronisiert (Android + iOS) ==="
