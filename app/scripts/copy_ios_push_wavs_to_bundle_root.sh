#!/bin/bash
# Wird von Xcode nach dem Befüllen des .app aufgerufen.
# APNs erwartet für custom sounds meist den Dateinamen im Haupt-Bundle-Root
# (z. B. "Ton1.wav"), nicht "voices/Ton1.wav".
set -euo pipefail
if [[ -z "${SRCROOT:-}" || -z "${TARGET_BUILD_DIR:-}" ]]; then
  exit 0
fi
APP_ROOT="$(cd "${SRCROOT}/.." && pwd)"
VOICES="$APP_ROOT/voices"
WRAPPER="${WRAPPER_NAME:-Runner.app}"
DEST="${TARGET_BUILD_DIR}/${WRAPPER}"
if [[ ! -d "$DEST" ]]; then
  echo "copy_ios_push_wavs: kein Bundle unter $DEST – überspringe"
  exit 0
fi
if [[ ! -d "$VOICES" ]]; then
  exit 0
fi
shopt -s nullglob
for f in "$VOICES"/*.wav; do
  [[ -f "$f" ]] || continue
  cp -f "$f" "$DEST/"
  echo "  Push-Sound → Bundle-Root: $(basename "$f")"
done
shopt -u nullglob
