#!/bin/bash
# Builds the official SpawnSweep (with Pro) and drafts a GitHub Release with build/SpawnSweep.zip attached.
# Run it from a clean checkout with the private Pro repo cloned into Sources/SpawnSweep/Pro.
#
#   scripts/release.sh             signed with Developer ID and notarized by Apple (needs the paid program)
#   scripts/release.sh --unsigned  ad-hoc signed only; people install with scripts/install.sh or "Open Anyway"
#
# One-time setup for signed releases (paid Apple Developer Program):
#   1. A "Developer ID Application" certificate in your login keychain. Check with
#        security find-identity -v -p codesigning
#      If you have more than one, set SPAWNSWEEP_SIGN_IDENTITY to the hash of the one to use.
#   2. A notarytool profile made from an App Store Connect API key:
#        xcrun notarytool store-credentials spawnsweep-notary \
#          --key /path/to/AuthKey_<KEY_ID>.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
#      The profile lives in your keychain; keep the .p8 somewhere safe outside this repo.
#      Use a different name by setting SPAWNSWEEP_NOTARY_PROFILE.
# Both modes need gh signed in to GitHub (gh auth status).
#
# Each release: bump CFBundleShortVersionString (and CFBundleVersion) in Resources/Info.plist,
# commit, run this script, then review and publish the draft on GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."

UNSIGNED=0
case "${1:-}" in
  "") ;;
  --unsigned) UNSIGNED=1 ;;
  *) echo "usage: scripts/release.sh [--unsigned]" >&2; exit 2 ;;
esac

PROFILE="${SPAWNSWEEP_NOTARY_PROFILE:-spawnsweep-notary}"
APP="build/SpawnSweep.app"
ZIP="build/SpawnSweep.zip"   # same name every release, so .../releases/latest/download/SpawnSweep.zip always works
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
INSTALL='curl -fsSL https://raw.githubusercontent.com/samirmaikap/spawnsweep/main/scripts/install.sh | bash'

fail() { echo "release: $*" >&2; exit 1; }

# 1. Everything that can fail before spending time on a build.
[ -z "$(git status --porcelain)" ] || fail "commit your changes first; a release is built from what's committed."
[ -d Sources/SpawnSweep/Pro/.git ] || fail "Sources/SpawnSweep/Pro is missing. Clone samirmaikap/spawnsweep-pro there first."
[ -z "$(git -C Sources/SpawnSweep/Pro status --porcelain)" ] || fail "commit your changes in Sources/SpawnSweep/Pro first."

if [ "$UNSIGNED" -eq 0 ]; then
  IDENTITY="${SPAWNSWEEP_SIGN_IDENTITY:-}"
  if [ -z "$IDENTITY" ]; then
    ids=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: /{print $2}')
    count=$(printf '%s' "$ids" | grep -c . || true)
    [ "$count" -ne 0 ] || fail "no \"Developer ID Application\" certificate in your keychain. See the setup notes at the top of this script, or use --unsigned."
    [ "$count" -eq 1 ] || fail "found $count Developer ID Application certificates. Set SPAWNSWEEP_SIGN_IDENTITY to the hash of one (security find-identity -v -p codesigning)."
    IDENTITY=$ids
  fi
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "notarytool profile \"$PROFILE\" didn't work (missing, wrong key, or offline). See the setup notes at the top of this script."
fi
if gh release view "$TAG" >/dev/null 2>&1; then
  fail "release $TAG already exists. Bump CFBundleShortVersionString in Resources/Info.plist."
fi

# 2. Build the official edition. bundle.sh runs the self-test, refuses a build without Pro, and signs ad hoc.
scripts/bundle.sh --pro

if [ "$UNSIGNED" -eq 0 ]; then
  # 3. Re-sign with Developer ID. Notarization requires the hardened runtime and a secure timestamp.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  # 4. Notarize, then staple the ticket to the app so it also opens offline.
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarizing (usually a few minutes)…"
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)
  status=$(plutil -extract status raw - <<<"$result")
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$(plutil -extract id raw - <<<"$result")" --keychain-profile "$PROFILE" || true
    fail "notarization finished with status \"$status\". Apple's log is above."
  fi
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"   # prints source=Notarized Developer ID
  NOTES="Download SpawnSweep.zip, open it, and move SpawnSweep to Applications."
else
  codesign --verify --strict "$APP"
  NOTES="Install from Terminal: \`$INSTALL\`

Or download SpawnSweep.zip, open it, and move SpawnSweep to Applications. This build isn't notarized by Apple yet, so the first time you open it macOS says it can't check it for malware. Open System Settings › Privacy & Security, scroll down, click **Open Anyway** next to SpawnSweep, then confirm."
fi

# 5. Zip the app and draft the release. Drafts stay hidden until you publish them.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
gh release create "$TAG" "$ZIP" --draft --title "SpawnSweep $VERSION" --notes "$NOTES

Everything free works right away. A SpawnSweep Pro key (Settings › SpawnSweep Pro) unlocks cleaning and Autopilot's Ask first and Automatic modes. Requires macOS 14 or later on Apple silicon."
echo "Drafted $TAG with $ZIP. Review and publish it on GitHub."
