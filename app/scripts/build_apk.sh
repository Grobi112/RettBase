#!/bin/bash
# Android Sideload / ohne Play Store: Version + web/app/download/version.json, dann signierte Release-APK
set -e
cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "Fehler: android/key.properties fehlt."
  echo "Ohne Release-Keystore signiert Flutter mit Debug."
  echo "Anleitung: docs/ANDROID_PLAY_RELEASE_SIGNING.md  |  Vorlage: android/key.properties.example"
  exit 1
fi

echo "Version und Build-Nummer erhöhen (pubspec.yaml + web/app/download/version.json)..."
node scripts/increment_pubspec_version.js

echo "Building Android Release APK..."
flutter build apk --release

OUT_DIR="build/app/outputs/flutter-apk"
# Gradle kann direkt rettbase.apk erzeugen; ältere Setups: app-release.apk
RELEASE_APK=""
if [[ -f "$OUT_DIR/rettbase.apk" ]]; then
  RELEASE_APK="$OUT_DIR/rettbase.apk"
elif [[ -f "$OUT_DIR/app-release.apk" ]]; then
  RELEASE_APK="$OUT_DIR/app-release.apk"
fi
RETTBASE_APK="$OUT_DIR/rettbase.apk"
if [[ -z "$RELEASE_APK" || ! -f "$RELEASE_APK" ]]; then
  echo "Fehler: Keine Release-APK in $OUT_DIR gefunden (rettbase.apk oder app-release.apk)."
  exit 1
fi
if [[ "$RELEASE_APK" != "$RETTBASE_APK" ]]; then
  cp -f "$RELEASE_APK" "$RETTBASE_APK"
fi
mkdir -p web/app/download
cp -f "$RETTBASE_APK" "web/app/download/rettbase.apk"
echo "Fertig."
echo "  APK: $RETTBASE_APK"
echo "  Kopie für Web-Hosting: web/app/download/rettbase.apk"
echo ""
echo "  Alles in einem Rutsch (Web bauen + Hosting):"
echo "    ./scripts/deploy_apk_and_hosting.sh"
echo "  Oder nur manuell: flutter build web && firebase deploy --only hosting"
