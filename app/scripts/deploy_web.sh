#!/bin/bash
# RettBase WebApp builden und auf Firebase Hosting deployen

set -e
cd "$(dirname "$0")/.."

echo "Version erhöhen (version.json, index.html)..."
node web/increment_version.js

echo "Building Flutter Web..."
flutter build web --tree-shake-icons

echo "Deploying to Firebase Hosting (rett-fe0fa)..."
firebase deploy --only hosting

echo "Done. WebApp should be live."
