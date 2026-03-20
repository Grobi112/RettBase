#!/bin/bash
# Android/Play-Store: Version und Build-Nummer automatisch erhöhen, dann flutter build appbundle
set -e
cd "$(dirname "$0")/.."

echo "Version und Build-Nummer erhöhen (pubspec.yaml)..."
node scripts/increment_pubspec_version.js

echo "Building Android App Bundle (AAB)..."
flutter build appbundle

echo "Fertig. AAB liegt unter build/app/outputs/bundle/release/"
