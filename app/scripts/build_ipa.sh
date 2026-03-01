#!/bin/bash
# iOS/Apple-Build: Version und Build-Nummer automatisch erhöhen, dann flutter build ipa
set -e
cd "$(dirname "$0")/.."

echo "Version und Build-Nummer erhöhen (pubspec.yaml)..."
node scripts/increment_pubspec_version.js

echo "Building iOS IPA..."
flutter build ipa

echo "Fertig. IPA liegt unter build/ios/ipa/"
