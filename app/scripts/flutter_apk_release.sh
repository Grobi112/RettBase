#!/bin/bash
# Nur Release-APK bauen und als rettbase.apk ablegen (ohne Versions-Bump / ohne web/).
# Flutter schreibt immer app-release.apk → hier automatisch nach rettbase.apk kopieren.
set -e
cd "$(dirname "$0")/.."

echo "Building Android Release APK..."
flutter build apk --release

OUT_DIR="build/app/outputs/flutter-apk"
SRC="$OUT_DIR/app-release.apk"
DST="$OUT_DIR/rettbase.apk"
if [[ ! -f "$SRC" ]]; then
  echo "Fehler: $SRC nicht gefunden."
  exit 1
fi
cp -f "$SRC" "$DST"
echo "Fertig: $DST"
echo "  (Hosting + Version: ./scripts/build_apk.sh oder ./scripts/deploy_apk_and_hosting.sh)"
