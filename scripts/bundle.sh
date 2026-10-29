#!/bin/bash
# Builds "build/SpawnSweep.app": release binary, Info.plist, rendered icon, ad-hoc signature.
# Usage: scripts/bundle.sh [--pro]   (--pro fails unless Sources/SpawnSweep/Pro is compiled in)
set -euo pipefail
cd "$(dirname "$0")/.."

# Self-tests use assert, which release builds compile out, so they run on the debug build.
swift build
.build/debug/SpawnSweep --selftest
swift build -c release
ED=$(.build/release/SpawnSweep --edition)
if [ "${1:-}" = "--pro" ] && [ "$ED" != "pro" ]; then
  echo "SpawnSweep Pro isn't compiled in. Clone samirmaikap/spawnsweep-pro into Sources/SpawnSweep/Pro first."
  exit 1
fi
APP="build/SpawnSweep.app"
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset
cp .build/release/SpawnSweep "$APP/Contents/MacOS/SpawnSweep"
cp Resources/Info.plist "$APP/Contents/Info.plist"

.build/release/SpawnSweep --render-icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built: $APP ($ED edition)"
