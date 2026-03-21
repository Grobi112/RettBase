#!/bin/bash
# Android/Play-Store: Version und Build-Nummer automatisch erhöhen, dann flutter build appbundle
set -e
cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "Fehler: android/key.properties fehlt."
  echo "Ohne Release-Keystore signiert Flutter mit Debug – die Play Console lehnt das AAB ab."
  echo "Anleitung: docs/ANDROID_PLAY_RELEASE_SIGNING.md  |  Vorlage: android/key.properties.example"
  exit 1
fi

echo "Version und Build-Nummer erhöhen (pubspec.yaml + web/app/download/version.json)..."
node scripts/increment_pubspec_version.js

echo "Building Android App Bundle (AAB)..."
flutter build appbundle

echo "Fertig. AAB liegt unter build/app/outputs/bundle/release/"
