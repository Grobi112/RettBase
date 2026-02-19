#!/usr/bin/env bash
# Ermittelt SHA-1 Fingerprint für Android API-Key-Einschränkung in Google Cloud Console.
# Nutze diese Werte bei "Anwendungseinschränkungen" → Android-Apps → SHA-1 hinzufügen.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Debug-Keystore (Entwicklung) ==="
echo "Pfad: ~/.android/debug.keystore"
echo ""
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android 2>/dev/null | grep -E "SHA1:|SHA256:"
echo ""

if [ -f "$PROJECT_ROOT/android/app/debug.keystore" ]; then
  echo "=== Projekt debug.keystore ==="
  keytool -list -v -keystore "$PROJECT_ROOT/android/app/debug.keystore" -alias androiddebugkey -storepass android 2>/dev/null | grep -E "SHA1:|SHA256:" || true
  echo ""
fi

echo "Für Release: keytool -list -v -keystore /pfad/zum/release.keystore -alias dein-alias"
echo "Paketname für Einschränkung: com.mikefullbeck.rettbase"
