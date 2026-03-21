#!/bin/bash
# iOS/Apple-Build: Alarmtöne (Android raw + iOS WAV + Dart), Version, flutter build ipa
set -e
cd "$(dirname "$0")/.."

# Pflicht vor jedem IPA: gleiche MP3s → Android res/raw + iOS WAV + alarm_tones.dart
# (nur setup_ios allein reicht für das IPA-Bundle; sync_alarm_sounds hält alles konsistent.)
bash scripts/sync_alarm_sounds.sh

echo "Version und Build-Nummer erhöhen (pubspec.yaml)..."
node scripts/increment_pubspec_version.js

echo "Building iOS IPA..."
flutter build ipa

echo "Fertig. IPA liegt unter build/ios/ipa/"
