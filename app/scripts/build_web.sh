#!/bin/bash
# WebApp bauen inkl. Versionserhöhung (für FTP-Deploy zu Strato)
set -e
cd "$(dirname "$0")/.."

echo "Version erhöhen (version.json, index.html)..."
node web/increment_version.js

echo "Building Flutter Web..."
flutter build web --tree-shake-icons

echo "Fertig. build/web/ kann per FTP hochgeladen werden."
