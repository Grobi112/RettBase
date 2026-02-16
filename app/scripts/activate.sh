#!/bin/bash
# Einmal pro Terminal-Session: source scripts/activate.sh
# Danach erhöht "flutter build web" automatisch die Version.
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$APP_ROOT:$PATH"
echo "Aktiviert: flutter build web erhöht jetzt automatisch die Version."
