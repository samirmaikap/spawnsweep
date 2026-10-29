#!/bin/bash
# Installs or updates SpawnSweep from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/samirmaikap/spawnsweep/main/scripts/install.sh | bash
# Downloads SpawnSweep.zip, puts SpawnSweep.app in /Applications (or ~/Applications if that isn't writable),
# and opens it. Nothing else on the Mac is touched.
set -euo pipefail

URL="${SPAWNSWEEP_ZIP_URL:-https://github.com/samirmaikap/spawnsweep/releases/latest/download/SpawnSweep.zip}"
fail() { echo "SpawnSweep: $*" >&2; exit 1; }

[ "$(uname)" = Darwin ] || fail "SpawnSweep is a Mac app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "SpawnSweep needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading SpawnSweep…"
curl -fL --progress-bar "$URL" -o "$TMP/SpawnSweep.zip"
ditto -x -k "$TMP/SpawnSweep.zip" "$TMP"
[ -d "$TMP/SpawnSweep.app" ] || fail "the download didn't contain SpawnSweep.app."
file "$TMP/SpawnSweep.app/Contents/MacOS/SpawnSweep" | grep -q "$(uname -m)" \
  || fail "this release doesn't run on $(uname -m) Macs yet."

# Replace an older copy: quit it first so nothing is half-written while it runs.
pkill -x SpawnSweep 2>/dev/null && sleep 1 || true
rm -rf "$DEST/SpawnSweep.app"
ditto "$TMP/SpawnSweep.app" "$DEST/SpawnSweep.app"
echo "Installed $DEST/SpawnSweep.app"
open "$DEST/SpawnSweep.app"
