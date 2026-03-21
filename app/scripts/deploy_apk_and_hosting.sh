#!/bin/bash
# Ein Befehl: Release-APK bauen, version.json setzen, Web bauen, Hosting deployen.
#
# 1) APK bauen + web/download/version.json + rettbase.apk (build_apk.sh)
# 2) flutter build web → kopiert alles nach build/web/ (was Firebase ausliefert)
# 3) firebase deploy --only hosting → download/version.json + APK + Web-App online
#
# Danach: Nutzer App neu starten → Update-Dialog (versionCode aus JSON > installierte APK).
#
# WICHTIG: Nicht ./flutter build web nutzen (Wrapper bump-t version.json nochmal).
#          Dieses Skript ruft „flutter“ direkt auf.

set -e
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Fehler: flutter nicht im PATH."
  exit 1
fi
if ! command -v firebase >/dev/null 2>&1; then
  echo "Fehler: firebase CLI nicht im PATH (npm i -g firebase-tools)."
  exit 1
fi

echo "=== 1/3 APK + version.json (increment_pubspec_version.js) ==="
bash scripts/build_apk.sh

echo ""
echo "=== 2/3 Flutter Web (ohne web/increment_version.js – Version kommt aus Schritt 1) ==="
flutter build web --tree-shake-icons

echo ""
echo "=== 3/3 Firebase Hosting (rett-fe0fa) ==="
firebase deploy --only hosting

echo ""
echo "Fertig."
echo "  - https://app.rettbase.de/download/version.json"
echo "  - https://app.rettbase.de/download/rettbase.apk"
echo "  Nutzer: App komplett schließen und neu öffnen → Update-Hinweis."
