#!/bin/bash
# RettBase WebApp builden und auf Firebase Hosting deployen

set -e
cd "$(dirname "$0")/.."

echo "Building Flutter Web..."
flutter build web

echo "Deploying to Firebase Hosting (rett-fe0fa)..."
firebase deploy --only hosting

echo "Done. WebApp should be live."
